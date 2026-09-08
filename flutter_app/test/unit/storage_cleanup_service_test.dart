import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/conversation_record.dart';
import 'package:look_whos_talking/services/conversation_store.dart';
import 'package:look_whos_talking/services/storage_cleanup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ConversationRecord _record({
  required String id,
  DateTime? createdAt,
  String? audioPath,
}) =>
    ConversationRecord(
      id: id,
      filename: 'rec_$id',
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      durationSec: 10,
      speakerCount: 1,
      resultJson: '{"id":"$id"}',
      audioPath: audioPath,
    );

void main() {
  setUpAll(sqfliteFfiInit);
  final now = DateTime(2026, 9, 7, 12);

  late ConversationStore store;
  late StorageCleanupService service;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lwt_cleanup_test');
    store = ConversationStore(
      factory: databaseFactoryFfi,
      dbPath: '${tempDir.path}/test.db',
    );
    service = StorageCleanupService(store: store, now: () => now);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await store.close();
    await tempDir.delete(recursive: true);
  });

  Future<String> audioFile(String name) async {
    final f = File('${tempDir.path}/$name');
    await f.writeAsBytes(List.filled(100, 1));
    return f.path;
  }

  group('findOldAudioRecords', () {
    test('returns empty when store is empty', () async {
      expect(
        await service.findOldAudioRecords(olderThanDays: 90),
        isEmpty,
      );
    });

    test('returns only records with audioPath older than the cutoff',
        () async {
      final oldPath = await audioFile('old.aac');
      final freshPath = await audioFile('fresh.aac');
      await store.save(_record(
        id: 'old',
        createdAt: now.subtract(const Duration(days: 91)),
        audioPath: oldPath,
      ));
      await store.save(_record(
        id: 'fresh',
        createdAt: now.subtract(const Duration(days: 10)),
        audioPath: freshPath,
      ));

      final old = await service.findOldAudioRecords(olderThanDays: 90);
      expect(old.map((r) => r.id), ['old']);
    });

    test('excludes records with no audio even when old (transcript kept)',
        () async {
      await store.save(_record(
        id: 'no_audio',
        createdAt: now.subtract(const Duration(days: 200)),
      ));
      expect(
        await service.findOldAudioRecords(olderThanDays: 90),
        isEmpty,
      );
    });

    test('boundary: record exactly at the cutoff is NOT old', () async {
      final path = await audioFile('edge.aac');
      await store.save(_record(
        id: 'edge',
        createdAt: now.subtract(const Duration(days: 90)),
        audioPath: path,
      ));
      expect(
        await service.findOldAudioRecords(olderThanDays: 90),
        isEmpty,
      );
    });
  });

  group('totalAudioSizeBytes', () {
    test('returns 0 for an empty list (zero case)', () async {
      expect(await service.totalAudioSizeBytes([]), 0);
    });

    test('sums the on-disk sizes of present audio files', () async {
      final a = await audioFile('a.aac'); // 100 bytes
      final b = await audioFile('b.aac'); // 100 bytes
      final records = [
        _record(id: 'a', audioPath: a),
        _record(id: 'b', audioPath: b),
      ];
      expect(await service.totalAudioSizeBytes(records), 200);
    });

    test('counts missing files as zero instead of throwing', () async {
      final records = [
        _record(id: 'gone', audioPath: '${tempDir.path}/missing.aac'),
      ];
      expect(await service.totalAudioSizeBytes(records), 0);
    });

    test('skips records whose audioPath is null', () async {
      final a = await audioFile('a.aac');
      final records = [
        _record(id: 'a', audioPath: a),
        _record(id: 'noaudio'),
      ];
      expect(await service.totalAudioSizeBytes(records), 100);
    });
  });

  group('deleteAudioForRecords', () {
    test('deletes audio files but keeps the records (transcripts survive)',
        () async {
      final a = await audioFile('a.aac');
      final b = await audioFile('b.aac');
      await store.save(_record(id: 'a', audioPath: a));
      await store.save(_record(id: 'b', audioPath: b));

      await service.deleteAudioForRecords([
        _record(id: 'a', audioPath: a),
        _record(id: 'b', audioPath: b),
      ]);

      expect(await File(a).exists(), isFalse);
      expect(await File(b).exists(), isFalse);
      final storedA = await store.get('a');
      expect(storedA!.audioPath, isNull);
      expect(storedA.resultJson, '{"id":"a"}'); // transcript intact
      expect(await store.list(), hasLength(2)); // records remain
    });

    test('handles records whose audio file is already gone', () async {
      await store.save(_record(id: 'a', audioPath: '${tempDir.path}/gone.aac'));
      await expectLater(
        service.deleteAudioForRecords([_record(id: 'a')]),
        completes,
      );
    });
  });

  group('shouldPrompt + recordPromptShown', () {
    test('false when no audio is older than threshold', () async {
      final path = await audioFile('recent.aac');
      await store.save(_record(
        id: 'recent',
        createdAt: now.subtract(const Duration(days: 5)),
        audioPath: path,
      ));
      expect(await service.shouldPrompt(), isFalse);
    });

    test('true when old audio exists and user has never been prompted',
        () async {
      final path = await audioFile('old.aac');
      await store.save(_record(
        id: 'old',
        createdAt: now.subtract(const Duration(days: 100)),
        audioPath: path,
      ));
      expect(await service.shouldPrompt(), isTrue);
    });

    test('false when prompted within the last 30 days', () async {
      final path = await audioFile('old.aac');
      await store.save(_record(
        id: 'old',
        createdAt: now.subtract(const Duration(days: 100)),
        audioPath: path,
      ));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        StorageCleanupService.lastPromptKey,
        now.subtract(const Duration(days: 10)).toIso8601String(),
      );
      expect(await service.shouldPrompt(), isFalse);
    });

    test('true again once 30 days have passed since the prompt', () async {
      final path = await audioFile('old.aac');
      await store.save(_record(
        id: 'old',
        createdAt: now.subtract(const Duration(days: 100)),
        audioPath: path,
      ));
      await service.recordPromptShown(); // recorded at `now`
      // Move the clock forward 31 days.
      final later = DateTime(2026, 10, 8, 12);
      final laterService =
          StorageCleanupService(store: store, now: () => later);
      expect(await laterService.shouldPrompt(), isTrue);
    });

    test('recordPromptShown suppresses for the default window', () async {
      final path = await audioFile('old.aac');
      await store.save(_record(
        id: 'old',
        createdAt: now.subtract(const Duration(days: 100)),
        audioPath: path,
      ));
      await service.recordPromptShown();
      expect(await service.shouldPrompt(), isFalse);
    });
  });
}
