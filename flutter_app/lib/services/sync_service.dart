import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;

import '../models/cloud_models.dart';
import '../models/conversation_record.dart';
import '../models/sync_summary.dart';
import 'cloud_storage_provider.dart';
import 'conversation_manifest.dart';
import 'conversation_store.dart';

/// Coordinates between the local [ConversationStore] and a cloud provider.
///
/// Remote layout per conversation, all under the provider's app folder:
///   conversations/{id}/result.json   — the raw backend result JSON
///   conversations/{id}/audio.aac     — only when audio was present locally
///   conversations/{id}/manifest.json — filename/date metadata for restore
class SyncService {
  SyncService({
    required this.store,
    required this.provider,
    Future<Directory> Function()? documentsDirProvider,
    Directory Function()? tempDirProvider,
  })  : _documentsDirProvider =
            documentsDirProvider ?? defaultDocumentsDir,
        _tempDirProvider = tempDirProvider ?? (() => Directory.systemTemp);

  static const resultFileName = 'result.json';
  static const audioFileName = 'audio.aac';
  static const manifestFileName = 'manifest.json';

  final ConversationStore store;
  final CloudStorageProvider provider;
  final Future<Directory> Function() _documentsDirProvider;
  final Directory Function() _tempDirProvider;

  // Conversation ids whose upload is currently in flight (see syncConversation).
  final Set<String> _inFlight = {};

  String _conversationDir(String id) => 'conversations/$id';
  String _remotePath(String id, String name) =>
      '${_conversationDir(id)}/$name';

  /// Uploads result.json, manifest.json and — when audio still exists
  /// locally — audio.aac for one conversation. Marks the record synced only
  /// after every upload succeeds.
  ///
  /// Throws [AuthException] when the provider is not authenticated.
  /// A locally-deleted audio file (audioPath null or gone from disk) is not an
  /// error: only the JSON is uploaded.
  Future<void> syncConversation(String id) async {
    // Guard against overlapping calls for the same id (e.g. a background
    // auto-sync racing a manual "Sync all", or a double tap): the upload path
    // is find-then-create, which is not atomic, so two concurrent runs could
    // each create a duplicate remote file. A second call while one is in
    // flight simply no-ops.
    if (!_inFlight.add(id)) return;
    try {
      await _syncConversationUnsafe(id);
    } finally {
      _inFlight.remove(id);
    }
  }

  Future<void> _syncConversationUnsafe(String id) async {
    if (!await provider.isAuthenticated()) {
      throw const AuthException('Not authenticated');
    }
    final record = await store.get(id);
    if (record == null) return; // nothing stored to sync

    final tempDir = _tempDirProvider();
    final resultFile = File(p.join(tempDir.path, '$id-$resultFileName'));
    final manifestFile = File(p.join(tempDir.path, '$id-$manifestFileName'));
    try {
      await resultFile.writeAsString(record.resultJson);
      await manifestFile.writeAsString(
        ConversationManifest.fromRecord(record).encode(),
      );

      await provider.upload(
        resultFile.path,
        _remotePath(id, resultFileName),
      );
      await provider.upload(
        manifestFile.path,
        _remotePath(id, manifestFileName),
      );

      final audioPath = record.audioPath;
      if (audioPath != null && await File(audioPath).exists()) {
        await provider.upload(audioPath, _remotePath(id, audioFileName));
      }

      await store.markSynced(id);
    } finally {
      await _deleteQuietly(resultFile);
      await _deleteQuietly(manifestFile);
    }
  }

  /// Uploads every unsynced conversation. Never aborts on an individual
  /// failure — each error is collected in [SyncSummary.errors].
  /// Uploads EVERY conversation (overwrite/create), synced or not. Safe to
  /// run repeatedly and after an external delete. Never aborts on an
  /// individual failure — each error is collected in [SyncSummary.errors].
  Future<SyncSummary> syncAll() async {
    final records = await store.list();
    return syncByIds(records.map((r) => r.id).toList());
  }

  /// Uploads exactly the given conversation ids (overwrite/create). Used by
  /// the History "Sync selected" action.
  Future<SyncSummary> syncByIds(List<String> ids) async {
    if (!await provider.isAuthenticated()) {
      throw const AuthException('Not authenticated');
    }
    var succeeded = 0;
    var failed = 0;
    final errors = <String>[];
    for (final id in ids) {
      try {
        await syncConversation(id);
        succeeded++;
      } catch (e) {
        failed++;
        errors.add('$id: $e');
      }
    }
    return SyncSummary(succeeded: succeeded, failed: failed, errors: errors);
  }

  /// Deletes a conversation's remote files (result.json, manifest.json and,
  /// when present, audio.aac). Idempotent — missing files are not an error.
  Future<void> deleteConversationFromCloud(String id) async {
    if (!await provider.isAuthenticated()) {
      throw const AuthException('Not authenticated');
    }
    for (final name in [resultFileName, manifestFileName, audioFileName]) {
      await provider.deleteFile(_remotePath(id, name));
    }
  }

  /// Lists every conversation present in the remote app folder, reading each
  /// conversation's manifest for its display metadata.
  Future<List<RemoteConversationMeta>> fetchRemoteIndex() async {
    if (!await provider.isAuthenticated()) {
      throw const AuthException('Not authenticated');
    }
    final rootFiles = await provider.listFiles('conversations');
    final metas = <RemoteConversationMeta>[];
    for (final entry in rootFiles) {
      final id = entry.filename;
      final meta = await _metaFor(id, fallbackModifiedAt: entry.modifiedAt);
      if (meta != null) metas.add(meta);
    }
    return metas;
  }

  // Reads one conversation's manifest (createdAt/name), falling back to the
  // folder listing when the manifest is absent (e.g. pre-manifest uploads).
  Future<RemoteConversationMeta?> _metaFor(
    String id, {
    required DateTime fallbackModifiedAt,
  }) async {
    final tempDir = _tempDirProvider();
    final manifestLocal = File(p.join(tempDir.path, '$id-manifest.json'));
    try {
      await provider.download(
        _remotePath(id, manifestFileName),
        manifestLocal.path,
      );
      final manifest =
          ConversationManifest.decode(await manifestLocal.readAsString());
      final hasAudio = await _hasRemoteAudio(id);
      return RemoteConversationMeta(
        id: id,
        filename: manifest.filename,
        createdAt: manifest.createdAt,
        hasAudio: hasAudio,
      );
    } on StorageException {
      // No manifest (legacy). Folder name is the best filename we have.
      final hasAudio = await _hasRemoteAudio(id);
      return RemoteConversationMeta(
        id: id,
        filename: id,
        createdAt: fallbackModifiedAt,
        hasAudio: hasAudio,
      );
    } finally {
      await _deleteQuietly(manifestLocal);
    }
  }

  Future<bool> _hasRemoteAudio(String id) async {
    final files = await provider.listFiles(_conversationDir(id));
    return files.any((f) => f.filename == audioFileName);
  }

  /// Restores one conversation: downloads result.json (+ audio.aac if the
  /// remote has it) and saves a local record. Audio goes to the app documents
  /// directory; result.json is stored verbatim as resultJson.
  Future<void> downloadConversation(String remoteId) async {
    if (!await provider.isAuthenticated()) {
      throw const AuthException('Not authenticated');
    }
    final docsDir = await _documentsDirProvider();
    final tempDir = _tempDirProvider();
    final resultLocal = File(p.join(tempDir.path, '$remoteId-result.json'));
    final manifestLocal = File(p.join(tempDir.path, '$remoteId-manifest.json'));

    try {
      await provider.download(
        _remotePath(remoteId, resultFileName),
        resultLocal.path,
      );
      final resultJson = await resultLocal.readAsString();

      String filename;
      DateTime createdAt;
      double durationSec;
      int speakerCount;
      try {
        await provider.download(
          _remotePath(remoteId, manifestFileName),
          manifestLocal.path,
        );
        final manifest =
            ConversationManifest.decode(await manifestLocal.readAsString());
        filename = manifest.filename;
        createdAt = manifest.createdAt;
        durationSec = manifest.durationSec;
        speakerCount = manifest.speakerCount;
      } on StorageException {
        // Legacy conversation without a manifest: derive what we can from the
        // result JSON itself.
        final parsed = jsonDecode(resultJson) as Map<String, dynamic>;
        filename = parsed['filename'] as String? ?? remoteId;
        createdAt = DateTime.now();
        durationSec = (parsed['total_duration_sec'] as num?)?.toDouble() ?? 0;
        speakerCount = parsed['speaker_count'] as int? ?? 0;
      }

      String? audioPath;
      if (await _hasRemoteAudio(remoteId)) {
        audioPath = p.join(docsDir.path, '$remoteId.$audioFileName');
        await provider.download(
          _remotePath(remoteId, audioFileName),
          audioPath,
        );
      }

      await store.save(
        ConversationRecord(
          id: remoteId,
          filename: filename,
          createdAt: createdAt,
          durationSec: durationSec,
          speakerCount: speakerCount,
          resultJson: resultJson,
          audioPath: audioPath,
          isSynced: true, // it came from the cloud — already backed up
        ),
      );
    } finally {
      await _deleteQuietly(resultLocal);
      await _deleteQuietly(manifestLocal);
    }
  }

  static Future<Directory> defaultDocumentsDir() =>
      path_provider.getApplicationDocumentsDirectory();

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best effort cleanup.
    }
  }
}
