import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/cloud_models.dart';
import 'package:look_whos_talking/models/conversation_record.dart';
import 'package:look_whos_talking/services/cloud_storage_provider.dart';
import 'package:look_whos_talking/services/conversation_store.dart';
import 'package:look_whos_talking/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// In-memory cloud: a map of remotePath → bytes plus an app folder.
class FakeCloud implements CloudStorageProvider {
  @override
  String get displayName => 'Sync Cloud';
  final Map<String, List<int>> files = {};
  bool authenticated = false;
  bool failNextUpload = false;
  int uploadCalls = 0;
  final List<String> deleted = [];

  String get appFolder => 'conversations';

  @override
  Future<void> authenticate() async => authenticated = true;

  @override
  Future<bool> isAuthenticated() async => authenticated;

  @override
  Future<void> signOut() async => authenticated = false;

  @override
  Future<void> upload(String localPath, String remotePath) async {
    uploadCalls++;
    if (failNextUpload) {
      failNextUpload = false;
      throw const StorageException('simulated upload failure');
    }
    files[remotePath] = await File(localPath).readAsBytes();
  }

  @override
  Future<void> download(String remotePath, String localPath) async {
    final bytes = files[remotePath];
    if (bytes == null) {
      throw StorageException('remote file not found: $remotePath');
    }
    await File(localPath).writeAsBytes(bytes);
  }

  @override
  Future<List<RemoteFileInfo>> listFiles(String folder) async {
    final prefix = folder == '' ? '' : '$folder/';
    final names = <String>{};
    for (final path in files.keys) {
      if (path.startsWith(prefix) && path != prefix) {
        final rest = path.substring(prefix.length);
        final first = rest.split('/').first;
        names.add(first);
      }
    }
    return names.map((n) {
      final full = prefix.isEmpty ? n : '$prefix$n';
      final bytes = files[full];
      return RemoteFileInfo(
        remotePath: full,
        filename: n,
        sizeBytes: bytes?.length ?? 0,
        modifiedAt: DateTime(2026, 9, 1),
      );
    }).toList();
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    deleted.add(remotePath);
    files.remove(remotePath);
  }
}

ConversationRecord record({
  required String id,
  String? audioPath,
  bool isSynced = false,
  String? filename,
}) =>
    ConversationRecord(
      id: id,
      filename: filename ?? 'Team call $id',
      createdAt: DateTime(2026, 9, 7, 10, 30),
      durationSec: 120.5,
      speakerCount: 3,
      resultJson: jsonEncode({'job_id': id, 'speaker_count': 3}),
      audioPath: audioPath,
      isSynced: isSynced,
    );

void main() {
  setUpAll(sqfliteFfiInit);

  late ConversationStore store;
  late FakeCloud cloud;
  late SyncService service;
  late Directory tempDir;
  late Directory docsDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lwt_sync_test');
    docsDir = await Directory.systemTemp.createTemp('lwt_sync_docs');
    store = ConversationStore(
      factory: databaseFactoryFfi,
      dbPath: '${tempDir.path}/test.db',
    );
    cloud = FakeCloud();
    service = SyncService(
      store: store,
      provider: cloud,
      documentsDirProvider: () async => docsDir,
      tempDirProvider: () => Directory('${tempDir.path}/tmp'),
    );
    await Directory('${tempDir.path}/tmp').create();
  });

  tearDown(() async {
    await store.close();
    await tempDir.delete(recursive: true);
    await docsDir.delete(recursive: true);
  });

  Future<String> writeAudio(String name) async {
    final f = File('${tempDir.path}/$name');
    await f.writeAsBytes([1, 2, 3]);
    return f.path;
  }

  group('syncConversation', () {
    test('throws AuthException when provider is not authenticated', () async {
      await store.save(record(id: 'job_1'));
      await expectLater(
        service.syncConversation('job_1'),
        throwsA(isA<AuthException>()),
      );
    });

    test('uploads result.json + manifest.json + audio.aac', () async {
      cloud.authenticated = true;
      final audioPath = await writeAudio('clip.aac');
      await store.save(record(id: 'job_1', audioPath: audioPath));

      await service.syncConversation('job_1');

      expect(cloud.files.containsKey('conversations/team-call-job-1_job_1/result.json'), isTrue);
      expect(cloud.files.containsKey('conversations/team-call-job-1_job_1/manifest.json'), isTrue);
      expect(cloud.files.containsKey('conversations/team-call-job-1_job_1/audio.aac'), isTrue);

      final resultBody = utf8.decode(
          cloud.files['conversations/team-call-job-1_job_1/result.json']!);
      expect(jsonDecode(resultBody), {'job_id': 'job_1', 'speaker_count': 3});
      expect(cloud.files['conversations/team-call-job-1_job_1/audio.aac'], [1, 2, 3]);

      // Result JSON is stored verbatim, not wrapped.
      final manifest = jsonDecode(utf8.decode(
          cloud.files['conversations/team-call-job-1_job_1/manifest.json']!)) as Map;
      expect(manifest['filename'], 'Team call job_1');
      expect(manifest['duration_sec'], 120.5);
      expect(manifest['speaker_count'], 3);

      final stored = await store.get('job_1');
      expect(stored!.isSynced, isTrue);
    });

    test('uploads only JSON when audio was deleted locally — no error',
        () async {
      cloud.authenticated = true;
      // audioPath recorded but file no longer on disk (deleted out-of-band).
      await store.save(record(
        id: 'job_1',
        audioPath: '${tempDir.path}/gone.aac',
      ));

      await service.syncConversation('job_1');

      expect(cloud.files.containsKey('conversations/team-call-job-1_job_1/result.json'), isTrue);
      expect(cloud.files.containsKey('conversations/team-call-job-1_job_1/manifest.json'), isTrue);
      expect(cloud.files.containsKey('conversations/team-call-job-1_job_1/audio.aac'), isFalse);
      final stored = await store.get('job_1');
      expect(stored!.isSynced, isTrue);
    });

    test('no-op without error for an unknown id', () async {
      cloud.authenticated = true;
      await service.syncConversation('missing');
      expect(cloud.uploadCalls, 0);
    });

    test('does not mark synced when an upload fails', () async {
      cloud.authenticated = true;
      cloud.failNextUpload = true;
      await store.save(record(id: 'job_1'));

      await expectLater(
        service.syncConversation('job_1'),
        throwsA(isA<StorageException>()),
      );
      final stored = await store.get('job_1');
      expect(stored!.isSynced, isFalse);
    });

    test('overlapping syncs for the same id upload only once', () async {
      cloud.authenticated = true;
      await store.save(record(id: 'job_1'));

      await Future.wait([
        service.syncConversation('job_1'),
        service.syncConversation('job_1'),
      ]);

      // One full upload set (result.json + manifest.json; no audio) — the
      // second overlapping call must no-op rather than create duplicates.
      expect(cloud.uploadCalls, 2);
      expect(cloud.files.keys.where((k) => k.startsWith('conversations/team-call-job-1_job_1/')),
          hasLength(2));
    });
  });

  group('syncAll', () {
    test('syncs every conversation, synced or not (overwrite)', () async {
      cloud.authenticated = true;
      await store.save(record(id: 'job_1', isSynced: true));
      await store.save(record(id: 'job_2'));
      await store.save(record(id: 'job_3'));

      final summary = await service.syncAll();

      expect(summary.succeeded, 3);
      expect(summary.failed, 0);
      expect(cloud.files.containsKey('conversations/team-call-job-1_job_1/result.json'), isTrue);
      expect(cloud.files.containsKey('conversations/team-call-job-2_job_2/result.json'), isTrue);
      expect(cloud.files.containsKey('conversations/team-call-job-3_job_3/result.json'), isTrue);
    });

    test('is safe to run when everything is already synced', () async {
      cloud.authenticated = true;
      await store.save(record(id: 'job_1', isSynced: true));
      final summary = await service.syncAll();
      expect(summary.succeeded, 1);
      expect(summary.failed, 0);
      expect(summary.errors, isEmpty);
    });

    test('continues past an individual failure and collects the error',
        () async {
      cloud.authenticated = true;
      await store.save(record(id: 'job_1'));
      await store.save(record(id: 'job_2'));
      cloud.failNextUpload = true; // first upload (job_1) fails

      final summary = await service.syncAll();

      expect(summary.failed, 1);
      expect(summary.succeeded, 1);
      expect(summary.errors.single, contains('job_1'));
      final job1 = await store.get('job_1');
      expect(job1!.isSynced, isFalse, reason: 'failed record stays unsynced');
      final job2 = await store.get('job_2');
      expect(job2!.isSynced, isTrue);
    });

    test('throws AuthException up front when not authenticated', () async {
      await store.save(record(id: 'job_1'));
      await expectLater(service.syncAll(), throwsA(isA<AuthException>()));
    });
  });

  group('syncByIds', () {
    test('syncs only the given ids', () async {
      cloud.authenticated = true;
      await store.save(record(id: 'a', isSynced: true));
      await store.save(record(id: 'b'));
      await store.save(record(id: 'c'));

      final summary = await service.syncByIds(['a', 'c']);

      expect(summary.succeeded, 2);
      expect(cloud.files.containsKey('conversations/team-call-a_a/result.json'), isTrue);
      expect(cloud.files.containsKey('conversations/team-call-c_c/result.json'), isTrue);
      expect(cloud.files.containsKey('conversations/team-call-b_b/result.json'), isFalse);
    });

    test('throws AuthException up front when not authenticated', () async {
      await store.save(record(id: 'a'));
      await expectLater(
        service.syncByIds(['a']),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('deleteConversationFromCloud', () {
    test('removes result.json, manifest.json and audio.aac', () async {
      cloud.authenticated = true;
      final audioPath = await writeAudio('clip.aac');
      await store.save(record(id: 'job_1', audioPath: audioPath));
      await service.syncConversation('job_1');
      expect(
        cloud.files.keys.where((k) => k.startsWith('conversations/team-call-job-1_job_1/')),
        hasLength(3),
      );

      await service.deleteConversationFromCloud('job_1', 'Team call job_1');

      expect(
        cloud.files.keys.where((k) => k.startsWith('conversations/team-call-job-1_job_1/')),
        isEmpty,
      );
      expect(
        cloud.deleted,
        contains('conversations/team-call-job-1_job_1'),
        reason: 'the emptied conversation folder is pruned too',
      );
    });

    test('throws AuthException when not authenticated', () async {
      await expectLater(
        service.deleteConversationFromCloud('job_1', 'Team call job_1'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('human-readable folder names', () {
    test('slugifies a filename with an extension', () async {
      cloud.authenticated = true;
      await store.save(record(id: 'job_1', filename: 'My Interview.mp3'));
      await service.syncConversation('job_1');
      expect(
        cloud.files
            .containsKey('conversations/my-interview_job_1/result.json'),
        isTrue,
      );
    });

    test('strips punctuation, spaces and apostrophes', () async {
      cloud.authenticated = true;
      await store.save(
        record(id: 'job_2', filename: "Interview — Jan '26.m4a"),
      );
      await service.syncConversation('job_2');
      expect(
        cloud.files
            .containsKey('conversations/interview-jan-26_job_2/result.json'),
        isTrue,
      );
    });

    test('truncates the slug to 40 characters', () async {
      cloud.authenticated = true;
      final long = 'a' * 50;
      await store.save(record(id: 'job_3', filename: '$long.wav'));
      await service.syncConversation('job_3');
      expect(
        cloud.files
            .containsKey('conversations/${'a' * 40}_job_3/result.json'),
        isTrue,
      );
    });

    test('falls back to "recording" when the slug would be empty', () async {
      cloud.authenticated = true;
      await store.save(record(id: 'job_4', filename: '!!!.wav'));
      await service.syncConversation('job_4');
      expect(
        cloud.files.containsKey('conversations/recording_job_4/result.json'),
        isTrue,
      );
    });

    test('remote audio carries the source file extension', () async {
      cloud.authenticated = true;
      final audioPath = await writeAudio('clip.m4a');
      await store.save(record(id: 'job_1', audioPath: audioPath));
      await service.syncConversation('job_1');
      expect(
        cloud.files
            .containsKey('conversations/team-call-job-1_job_1/audio.m4a'),
        isTrue,
      );
      expect(cloud.files.keys.any((k) => k.endsWith('audio.aac')), isFalse);
    });
  });

  group('fetchRemoteIndex', () {
    test('returns empty list when nothing is remote', () async {
      cloud.authenticated = true;
      expect(await service.fetchRemoteIndex(), isEmpty);
    });

    test('returns one meta per remote conversation with manifest metadata',
        () async {
      cloud.authenticated = true;
      final audioPath = await writeAudio('c.aac');
      await store.save(record(id: 'job_1', audioPath: audioPath));
      await service.syncConversation('job_1');

      final metas = await service.fetchRemoteIndex();
      expect(metas.length, 1);
      final meta = metas.single;
      expect(meta.id, 'job_1');
      expect(meta.remoteDir, 'team-call-job-1_job_1');
      expect(meta.filename, 'Team call job_1');
      expect(meta.createdAt, DateTime(2026, 9, 7, 10, 30));
      expect(meta.hasAudio, isTrue);
    });

    test('falls back to the folder name when no manifest is present',
        () async {
      cloud.authenticated = true;
      // Legacy layout: conversations/{uuid}/ with no manifest.
      const folder = '9212d114-fcb0-49be-8866-b7b96dbcd254';
      cloud.files['conversations/$folder/result.json'] = utf8.encode('{}');

      final metas = await service.fetchRemoteIndex();
      expect(metas.single.id, folder); // uuid extracted from folder name
      expect(metas.single.remoteDir, folder);
      expect(metas.single.filename, folder);
      expect(metas.single.hasAudio, isFalse);
    });
  });

  group('downloadConversation', () {
    test('restores record + audio into the documents directory', () async {
      cloud.authenticated = true;
      final audioPath = await writeAudio('clip.aac');
      await store.save(record(id: 'job_1', audioPath: audioPath));
      await service.syncConversation('job_1');
      // Forget it locally, as on a fresh device.
      await store.delete('job_1');

      await service.downloadConversation('team-call-job-1_job_1');

      final restored = await store.get('job_1');
      expect(restored, isNotNull);
      expect(restored!.filename, 'Team call job_1');
      expect(restored.createdAt, DateTime(2026, 9, 7, 10, 30));
      expect(restored.durationSec, 120.5);
      expect(restored.speakerCount, 3);
      expect(restored.isSynced, isTrue);
      expect(
        jsonDecode(restored.resultJson),
        {'job_id': 'job_1', 'speaker_count': 3},
      );
      expect(restored.audioPath, isNotNull);
      final audioFile = File(restored.audioPath!);
      expect(audioFile.path, startsWith(docsDir.path));
      expect(await audioFile.readAsBytes(), [1, 2, 3]);
    });

    test('restores without audio when the remote has none', () async {
      cloud.authenticated = true;
      await store.save(record(id: 'job_1')); // no audioPath
      await service.syncConversation('job_1');
      await store.delete('job_1');

      await service.downloadConversation('team-call-job-1_job_1');

      final restored = await store.get('job_1');
      expect(restored!.audioPath, isNull);
      expect(restored.isSynced, isTrue);
    });

    test('throws StorageException when result.json is missing remotely',
        () async {
      cloud.authenticated = true;
      await expectLater(
        service.downloadConversation('never_synced'),
        throwsA(isA<StorageException>()),
      );
    });

    test('restores a legacy conversation with no manifest', () async {
      cloud.authenticated = true;
      const folder = 'aa11bb22-cc33-44dd-55ee-66ff77008899';
      cloud.files['conversations/$folder/result.json'] = utf8.encode(
        jsonEncode({
          'filename': 'Old recording',
          'total_duration_sec': 55.0,
          'speaker_count': 2,
        }),
      );

      await service.downloadConversation(folder);

      final restored = await store.get(folder); // uuid from the folder name
      expect(restored!.filename, 'Old recording');
      expect(restored.durationSec, 55.0);
      expect(restored.speakerCount, 2);
    });
  });
}
