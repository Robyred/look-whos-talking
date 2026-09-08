import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/conversation_record.dart';
import 'package:look_whos_talking/services/conversation_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ConversationRecord _record({
  required String id,
  DateTime? createdAt,
  String? audioPath,
  bool isSynced = false,
}) {
  return ConversationRecord(
    id: id,
    filename: 'recording_$id',
    createdAt: createdAt ?? DateTime(2026, 9, 7, 12),
    durationSec: 60.5,
    speakerCount: 2,
    resultJson: '{"id":"$id"}',
    audioPath: audioPath,
    isSynced: isSynced,
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  late ConversationStore store;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lwt_store_test');
    store = ConversationStore(
      factory: databaseFactoryFfi,
      dbPath: '${tempDir.path}/test.db',
    );
  });

  tearDown(() async {
    await store.close();
    await tempDir.delete(recursive: true);
  });

  group('save', () {
    test('round-trips a record through get', () async {
      final record = _record(id: 'job_1');
      await store.save(record);

      final loaded = await store.get('job_1');
      expect(loaded, isNotNull);
      expect(loaded!.id, 'job_1');
      expect(loaded.filename, 'recording_job_1');
      expect(loaded.createdAt, record.createdAt);
      expect(loaded.durationSec, 60.5);
      expect(loaded.speakerCount, 2);
      expect(loaded.resultJson, '{"id":"job_1"}');
      expect(loaded.isSynced, isFalse);
    });

    test('re-saving the same id overwrites — only one row remains', () async {
      await store.save(_record(id: 'job_1', isSynced: true));
      await store.save(_record(id: 'job_1'));

      final all = await store.list();
      expect(all.length, 1);
      // Second save replaced the row, so isSynced is back to the default false.
      expect(all.single.isSynced, isFalse);
    });
  });

  group('get', () {
    test('returns null for an unknown id', () async {
      expect(await store.get('missing'), isNull);
    });
  });

  group('list', () {
    test('returns empty list when store is empty', () async {
      expect(await store.list(), isEmpty);
    });

    test('orders records by createdAt descending regardless of insert order',
        () async {
      await store.save(_record(
          id: 'old', createdAt: DateTime(2026, 1, 1, 8)));
      await store.save(_record(
          id: 'new', createdAt: DateTime(2026, 9, 7, 8)));
      await store.save(_record(
          id: 'middle', createdAt: DateTime(2026, 6, 1, 8)));

      final all = await store.list();
      expect(all.map((r) => r.id).toList(), ['new', 'middle', 'old']);
    });
  });

  group('deleteAudio', () {
    test('deletes the audio file from disk and nulls audio_path', () async {
      final dir = await Directory.systemTemp.createTemp('lwt_audio_test');
      addTearDown(() => dir.delete(recursive: true));
      final audioFile = File('${dir.path}/clip.aac');
      await audioFile.writeAsBytes([1, 2, 3]);

      await store.save(_record(id: 'job_1', audioPath: audioFile.path));
      await store.deleteAudio('job_1');

      expect(await audioFile.exists(), isFalse);
      final loaded = await store.get('job_1');
      expect(loaded!.audioPath, isNull);
      // Record itself survives.
      expect(loaded.resultJson, '{"id":"job_1"}');
    });

    test('no-op without throwing when audioPath is already null', () async {
      await store.save(_record(id: 'job_1'));
      await expectLater(store.deleteAudio('job_1'), completes);
      final loaded = await store.get('job_1');
      expect(loaded!.audioPath, isNull);
    });

    test('no-op without throwing when the file no longer exists on disk',
        () async {
      await store.save(_record(id: 'job_1', audioPath: '/gone/missing.aac'));
      await expectLater(store.deleteAudio('job_1'), completes);
      final loaded = await store.get('job_1');
      expect(loaded!.audioPath, isNull);
    });

    test('no-op when the record does not exist', () async {
      await expectLater(store.deleteAudio('nope'), completes);
    });
  });

  group('delete', () {
    test('removes record and its audio file from disk', () async {
      final dir = await Directory.systemTemp.createTemp('lwt_delete_test');
      addTearDown(() => dir.delete(recursive: true));
      final audioFile = File('${dir.path}/clip.aac');
      await audioFile.writeAsBytes([1]);

      await store.save(_record(id: 'job_1', audioPath: audioFile.path));
      await store.delete('job_1');

      expect(await store.get('job_1'), isNull);
      expect(await audioFile.exists(), isFalse);
    });

    test('removes a record that has no audio file', () async {
      await store.save(_record(id: 'job_1'));
      await store.delete('job_1');
      expect(await store.get('job_1'), isNull);
      expect(await store.list(), isEmpty);
    });

    test('no-op when id is unknown', () async {
      await expectLater(store.delete('missing'), completes);
      expect(await store.list(), isEmpty);
    });
  });

  group('markSynced', () {
    test('sets isSynced=true on the given record', () async {
      await store.save(_record(id: 'job_1'));
      await store.markSynced('job_1');
      final loaded = await store.get('job_1');
      expect(loaded!.isSynced, isTrue);
    });

    test('no-op without throwing for an unknown id', () async {
      await expectLater(store.markSynced('missing'), completes);
    });
  });

  group('close', () {
    test('actually closes the underlying database handle', () async {
      await store.save(_record(id: 'job_1')); // forces the DB open
      final db = store.debugDatabase;
      expect(db, isNotNull);

      await store.close();

      expect(db!.isOpen, isFalse);
      expect(store.debugDatabase, isNull);
    });

    test('store re-opens cleanly after close', () async {
      await store.save(_record(id: 'job_1'));
      await store.close();

      final loaded = await store.get('job_1');
      expect(loaded!.id, 'job_1');
    });
  });
}
