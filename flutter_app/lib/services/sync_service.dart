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
///   conversations/{slug}_{id}/result.json   — the raw backend result JSON
///   conversations/{slug}_{id}/`audio.<ext>` — only when audio was present
///   conversations/{slug}_{id}/manifest.json — filename/date metadata
/// where {slug} is a human-readable slug of the conversation filename and
/// {ext} is the source audio file's real extension.
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
  static const manifestFileName = 'manifest.json';

  final ConversationStore store;
  final CloudStorageProvider provider;
  final Future<Directory> Function() _documentsDirProvider;
  final Directory Function() _tempDirProvider;

  // Conversation ids whose upload is currently in flight (see syncConversation).
  final Set<String> _inFlight = {};

  /// Human-readable, filesystem/URL-safe slug of [filename], used as the
  /// leading part of the remote conversation folder name.
  static String _remoteSlug(String filename) {
    var slug = p.basenameWithoutExtension(filename).toLowerCase();
    slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-'); // runs → single '-'
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), ''); // strip leading/trailing '-'
    if (slug.length > 40) slug = slug.substring(0, 40);
    return slug.isEmpty ? 'recording' : slug;
  }

  /// Remote audio filename carrying the source file's real extension.
  static String _audioRemoteName(String localPath) =>
      'audio${p.extension(localPath)}';

  /// Legacy/robust id extraction from a remote folder name: the uuid suffix
  /// after the last '_' (or the whole name when there is no underscore).
  static String _idFromFolderName(String folderName) {
    final index = folderName.lastIndexOf('_');
    return index == -1 ? folderName : folderName.substring(index + 1);
  }

  String _conversationDir(String id, String filename) =>
      'conversations/${_remoteSlug(filename)}_$id';
  String _remotePath(String id, String filename, String name) =>
      '${_conversationDir(id, filename)}/$name';

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
        _remotePath(id, record.filename, resultFileName),
      );
      await provider.upload(
        manifestFile.path,
        _remotePath(id, record.filename, manifestFileName),
      );

      final audioPath = record.audioPath;
      if (audioPath != null && await File(audioPath).exists()) {
        await provider.upload(
          audioPath,
          _remotePath(id, record.filename, _audioRemoteName(audioPath)),
        );
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
  /// when present, the audio file whatever its extension) and prunes the
  /// now-empty conversation folder. Idempotent — missing entries are not an
  /// error.
  Future<void> deleteConversationFromCloud(String id, String filename) async {
    if (!await provider.isAuthenticated()) {
      throw const AuthException('Not authenticated');
    }
    final dir = _conversationDir(id, filename);
    await provider.deleteFile('$dir/$resultFileName');
    await provider.deleteFile('$dir/$manifestFileName');
    final audio = await _findRemoteAudio(dir);
    if (audio != null) {
      await provider.deleteFile('$dir/$audio');
    }
    // Prune the folder itself so the cloud tree doesn't fill with empties.
    await provider.deleteFile(dir);
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
      final meta = await _metaFor(
        entry.filename,
        fallbackModifiedAt: entry.modifiedAt,
      );
      if (meta != null) metas.add(meta);
    }
    return metas;
  }

  // Reads one conversation's manifest (createdAt/name), falling back to the
  // folder name when the manifest is absent (e.g. pre-manifest uploads).
  // [folderName] is the remote folder name (e.g. my-interview_<uuid>).
  Future<RemoteConversationMeta?> _metaFor(
    String folderName, {
    required DateTime fallbackModifiedAt,
  }) async {
    final tempDir = _tempDirProvider();
    final manifestLocal =
        File(p.join(tempDir.path, '$folderName-manifest.json'));
    final remoteDir = 'conversations/$folderName';
    try {
      await provider.download(
        '$remoteDir/$manifestFileName',
        manifestLocal.path,
      );
      final manifest =
          ConversationManifest.decode(await manifestLocal.readAsString());
      final hasAudio = await _findRemoteAudio(remoteDir) != null;
      return RemoteConversationMeta(
        id: manifest.id, // authoritative id comes from the manifest
        remoteDir: folderName,
        filename: manifest.filename,
        createdAt: manifest.createdAt,
        hasAudio: hasAudio,
      );
    } on StorageException {
      // No manifest (legacy). Folder name is the best filename we have.
      final hasAudio = await _findRemoteAudio(remoteDir) != null;
      return RemoteConversationMeta(
        id: _idFromFolderName(folderName),
        remoteDir: folderName,
        filename: folderName,
        createdAt: fallbackModifiedAt,
        hasAudio: hasAudio,
      );
    } finally {
      await _deleteQuietly(manifestLocal);
    }
  }

  /// Filename of the first `audio.*` file in [remoteDir], or null when none.
  Future<String?> _findRemoteAudio(String remoteDir) async {
    final files = await provider.listFiles(remoteDir);
    for (final file in files) {
      if (file.filename.startsWith('audio.')) return file.filename;
    }
    return null;
  }

  /// Restores one conversation: downloads result.json (+ its audio file if the
  /// remote has one) and saves a local record. Audio goes to the app documents
  /// directory; result.json is stored verbatim as resultJson.
  ///
  /// [remoteDir] is the remote folder name (e.g. `my-interview_<uuid>`). The
  /// local record id comes from the manifest, or from the uuid suffix of
  /// [remoteDir] for legacy folders with no manifest.
  Future<void> downloadConversation(String remoteDir) async {
    if (!await provider.isAuthenticated()) {
      throw const AuthException('Not authenticated');
    }
    final docsDir = await _documentsDirProvider();
    final tempDir = _tempDirProvider();
    final resultLocal = File(p.join(tempDir.path, '$remoteDir-result.json'));
    final manifestLocal = File(p.join(tempDir.path, '$remoteDir-manifest.json'));
    final remoteFolder = 'conversations/$remoteDir';

    try {
      await provider.download(
        '$remoteFolder/$resultFileName',
        resultLocal.path,
      );
      final resultJson = await resultLocal.readAsString();

      String id;
      String filename;
      DateTime createdAt;
      double durationSec;
      int speakerCount;
      try {
        await provider.download(
          '$remoteFolder/$manifestFileName',
          manifestLocal.path,
        );
        final manifest =
            ConversationManifest.decode(await manifestLocal.readAsString());
        id = manifest.id;
        filename = manifest.filename;
        createdAt = manifest.createdAt;
        durationSec = manifest.durationSec;
        speakerCount = manifest.speakerCount;
      } on StorageException {
        // Legacy conversation without a manifest: derive what we can from the
        // result JSON itself.
        final parsed = jsonDecode(resultJson) as Map<String, dynamic>;
        id = _idFromFolderName(remoteDir);
        filename = parsed['filename'] as String? ?? remoteDir;
        createdAt = DateTime.now();
        durationSec = (parsed['total_duration_sec'] as num?)?.toDouble() ?? 0;
        speakerCount = parsed['speaker_count'] as int? ?? 0;
      }

      String? audioPath;
      final audioName = await _findRemoteAudio(remoteFolder);
      if (audioName != null) {
        audioPath = p.join(docsDir.path, '$id${p.extension(audioName)}');
        await provider.download('$remoteFolder/$audioName', audioPath);
      }

      await store.save(
        ConversationRecord(
          id: id,
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
