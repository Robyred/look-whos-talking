import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/cloud_models.dart';
import 'package:look_whos_talking/models/job_result.dart';
import 'package:look_whos_talking/services/cloud_storage_provider.dart';
import 'package:look_whos_talking/services/conversation_store.dart';
import 'package:look_whos_talking/services/persist_completed_job.dart';
import 'package:look_whos_talking/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RecordingCloud implements CloudStorageProvider {
  @override
  String get displayName => 'Recording Cloud';
  _RecordingCloud({this.authenticated = false, this.throwOnAuthCheck = false});
  bool authenticated;
  bool throwOnAuthCheck;
  final List<String> uploadedPaths = [];

  @override
  Future<void> authenticate() async => authenticated = true;
  @override
  Future<bool> isAuthenticated() async {
    if (throwOnAuthCheck) throw Exception('sign-in plugin unavailable');
    return authenticated;
  }

  @override
  Future<void> signOut() async => authenticated = false;
  @override
  Future<void> upload(String localPath, String remotePath) async {
    uploadedPaths.add(remotePath);
  }

  @override
  Future<void> download(String remotePath, String localPath) async {
    throw const StorageException('unexpected download');
  }

  @override
  Future<List<RemoteFileInfo>> listFiles(String folder) async => const [];
  @override
  Future<void> deleteFile(String remotePath) async {}
}

class _RecordingSyncService extends SyncService {
  _RecordingSyncService({
    required super.store,
    required super.provider,
    this.throwOnSync = false,
  });
  final bool throwOnSync;
  bool synced = false;

  @override
  Future<void> syncConversation(String id) async {
    if (throwOnSync) throw const StorageException('upload exploded');
    synced = true;
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDir;
  late ConversationStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lwt_persist_test');
    store = ConversationStore(
      factory: databaseFactoryFfi,
      dbPath: '${tempDir.path}/test.db',
    );
  });

  tearDown(() async {
    await store.close();
    await tempDir.delete(recursive: true);
  });

  Map<String, dynamic> jobPayload() => {
        'job_id': 'job_abc',
        'filename': 'meeting.m4a',
        'status': 'complete',
        'result': {
          'filename': 'meeting.m4a',
          'total_duration_sec': 120.5,
          'speaker_count': 2,
          'speakers': [
            {
              'speaker_id': 'SPEAKER_00',
              'duration_sec': 60.0,
              'percentage': 49.8,
            },
            {
              'speaker_id': 'SPEAKER_01',
              'duration_sec': 60.5,
              'percentage': 50.2,
            },
          ],
          'overlap_sec': 0.0,
          'speech_sec': 120.0,
          'silence_sec': 0.5,
          'transcript': [
            {
              'speaker_id': 'SPEAKER_00',
              'start': 0.0,
              'end': 2.0,
              'text': 'Hello',
            },
          ],
        },
      };

  JobStatusResponse completeStatus() =>
      JobStatusResponse.fromJson(jobPayload());

  group('JobStatusResponse.rawResultJson', () {
    test('carries the result payload verbatim when the job completed',
        () async {
      final status = completeStatus();
      expect(status.rawResultJson, isNotNull);
      expect(jsonDecode(status.rawResultJson!),
          jobPayload()['result']);
    });

    test('is null while the job is still queued/processing', () {
      final status = JobStatusResponse.fromJson({
        'job_id': 'job_abc',
        'filename': 'meeting.m4a',
        'status': 'processing',
      });
      expect(status.rawResultJson, isNull);
      expect(status.result, isNull);
    });
  });

  group('persistCompletedJob', () {
    final createdAt = DateTime(2026, 9, 8, 12, 30);

    Future<void> call({
      _RecordingCloud? cloud,
      bool autoSync = false,
      SyncService Function(ConversationStore, CloudStorageProvider)?
          syncFactory,
      String resultJson = '{"speaker_count":2}',
      String? audioPath,
    }) {
      return persistCompletedJob(
        store: store,
        jobId: 'job_abc',
        filename: 'team meeting.m4a',
        createdAt: createdAt,
        durationSec: 120.5,
        speakerCount: 2,
        resultJson: resultJson,
        audioPath: audioPath,
        cloud: cloud,
        autoSync: autoSync,
        syncServiceFactory: syncFactory,
      );
    }

    test('happy path: saves the record with every field', () async {
      await call(audioPath: '/recordings/a.m4a');

      final saved = await store.get('job_abc');
      expect(saved, isNotNull);
      expect(saved!.filename, 'team meeting.m4a');
      expect(saved.createdAt, createdAt);
      expect(saved.durationSec, 120.5);
      expect(saved.speakerCount, 2);
      expect(saved.resultJson, '{"speaker_count":2}');
      expect(saved.audioPath, '/recordings/a.m4a');
      expect(saved.isSynced, isFalse);
    });

    test('audioPath stays null when none is available', () async {
      await call();
      final saved = await store.get('job_abc');
      expect(saved!.audioPath, isNull);
    });

    test('no cloud: record is saved and nothing is uploaded', () async {
      await call();

      final saved = await store.get('job_abc');
      expect(saved, isNotNull);
      // No cloud passed — nothing to assert beyond completing without error.
    });

    test('does not auto-sync unless autoSync is enabled (opt-in default)',
        () async {
      final cloud = _RecordingCloud(authenticated: true);
      await call(cloud: cloud); // autoSync defaults to false
      await Future<void>.delayed(Duration.zero);
      expect(cloud.uploadedPaths, isEmpty);
      final saved = await store.get('job_abc');
      expect(saved, isNotNull);
    });

    test('cloud not authenticated: record saved, no sync attempted', () async {
      final cloud = _RecordingCloud(authenticated: false);
      await call(cloud: cloud);
      expect(cloud.uploadedPaths, isEmpty);
      final saved = await store.get('job_abc');
      expect(saved, isNotNull);
    });

    test('cloud authenticated + autoSync: background sync is triggered',
        () async {
      final cloud = _RecordingCloud(authenticated: true);
      final sync = _RecordingSyncService(store: store, provider: cloud);
      await call(cloud: cloud, autoSync: true, syncFactory: (_, _) => sync);
      // Give the unawaited sync future a chance to run.
      await Future<void>.delayed(Duration.zero);
      expect(sync.synced, isTrue);
    });

    test('a failing background sync is swallowed', () async {
      final cloud = _RecordingCloud(authenticated: true);
      final sync = _RecordingSyncService(
        store: store,
        provider: cloud,
        throwOnSync: true,
      );
      await call(cloud: cloud, autoSync: true, syncFactory: (_, _) => sync);
      await Future<void>.delayed(Duration.zero);
      expect(sync.synced, isFalse); // threw before recording
    });

    test('auth-check failure is treated as not signed in', () async {
      final cloud = _RecordingCloud(throwOnAuthCheck: true);
      await expectLater(call(cloud: cloud, autoSync: true), completes);
      expect(cloud.uploadedPaths, isEmpty);
      final saved = await store.get('job_abc');
      expect(saved, isNotNull);
    });

    test('save failure is swallowed and the cloud is never touched',
        () async {
      final cloud = _RecordingCloud(authenticated: true);
      // A database path whose parent is a regular file makes every open/query
      // throw deterministically — the save must fail, silently.
      final blocker = File('${tempDir.path}/not-a-dir');
      await blocker.writeAsBytes([1]);
      final broken = ConversationStore(
        factory: databaseFactoryFfi,
        dbPath: '${blocker.path}/x.db',
      );
      await expectLater(
        persistCompletedJob(
          store: broken,
          jobId: 'job_broken',
          filename: 'x.m4a',
          createdAt: createdAt,
          durationSec: 1,
          speakerCount: 1,
          resultJson: '{}',
          cloud: cloud,
          autoSync: true,
        ),
        completes,
      );
      expect(cloud.uploadedPaths, isEmpty);
    });

    test('records the raw backend JSON as resultJson', () async {
      final status = completeStatus();
      await persistCompletedJob(
        store: store,
        jobId: status.jobId,
        filename: 'meeting.m4a',
        createdAt: createdAt,
        durationSec: status.result!.totalDurationSec,
        speakerCount: status.result!.speakerCount,
        resultJson: status.rawResultJson!,
      );
      final saved = await store.get(status.jobId);
      expect(saved!.resultJson, status.rawResultJson);
      // And it re-parses into the same result shape.
      final roundTrip = DiarizationResult.fromJson(
          jsonDecode(saved.resultJson) as Map<String, dynamic>);
      expect(roundTrip.speakerCount, 2);
      expect(roundTrip.totalDurationSec, 120.5);
    });
  });
}
