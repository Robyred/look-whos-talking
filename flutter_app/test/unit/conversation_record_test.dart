import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/conversation_record.dart';

ConversationRecord _record({String? audioPath, bool isSynced = false}) =>
    ConversationRecord(
      id: 'job_123',
      filename: 'Recording 2026-09-07 14:30',
      createdAt: DateTime.parse('2026-09-07T14:30:00.123456'),
      durationSec: 92.75,
      speakerCount: 3,
      resultJson: '{"speaker_count":3,"total_duration_sec":92.75}',
      audioPath: audioPath,
      isSynced: isSynced,
    );

void main() {
  group('ConversationRecord.toMap', () {
    test('exposes all eight spec fields under stable keys', () {
      final map = _record(audioPath: '/audio/job_123.aac').toMap();
      expect(map.keys.toSet(), {
        'id',
        'filename',
        'created_at',
        'duration_sec',
        'speaker_count',
        'result_json',
        'audio_path',
        'is_synced',
      });
    });

    test('serialises createdAt losslessly including microseconds', () {
      final map = _record().toMap();
      final stored = DateTime.parse(map['created_at'] as String);
      // Stored as UTC so SQL ordering is chronologically correct.
      expect(stored.isUtc, isTrue);
      expect(
        stored.toLocal(),
        DateTime.parse('2026-09-07T14:30:00.123456'),
      );
    });

    test('stores isSynced=true as integer 1 and false as 0', () {
      expect(_record(isSynced: true).toMap()['is_synced'], 1);
      expect(_record(isSynced: false).toMap()['is_synced'], 0);
    });
  });

  group('ConversationRecord.fromMap', () {
    test('accepts integer duration (SQLite stores whole doubles as int)', () {
      final map = _record().toMap()..['duration_sec'] = 92;
      final record = ConversationRecord.fromMap(map);
      expect(record.durationSec, 92.0);
    });

    test('round-trips a full record with audio present', () {
      final original = _record(audioPath: '/audio/job_123.aac');
      final restored = ConversationRecord.fromMap(original.toMap());
      expect(restored.id, original.id);
      expect(restored.filename, original.filename);
      expect(restored.createdAt, original.createdAt);
      expect(restored.durationSec, original.durationSec);
      expect(restored.speakerCount, original.speakerCount);
      expect(restored.resultJson, original.resultJson);
      expect(restored.audioPath, '/audio/job_123.aac');
      expect(restored.isSynced, isFalse);
    });

    test('round-trips audioPath=null (deleted audio case)', () {
      final original = _record(audioPath: null);
      final restored = ConversationRecord.fromMap(original.toMap());
      expect(restored.audioPath, isNull);
    });

    test('round-trips isSynced=true', () {
      final original = _record(audioPath: '/audio/job_123.aac', isSynced: true);
      final restored = ConversationRecord.fromMap(original.toMap());
      expect(restored.isSynced, isTrue);
    });

    test('keeps resultJson byte-for-byte (quotes, unicode, newlines)', () {
      const json =
          '{"transcript":[{"text":"café \\"said\\"\\nnext","who":"SPEAKER_00"}]}';
      final original = ConversationRecord(
        id: 'j',
        filename: 'f',
        createdAt: DateTime(2026),
        durationSec: 1,
        speakerCount: 1,
        resultJson: json,
      );
      final restored = ConversationRecord.fromMap(original.toMap());
      expect(restored.resultJson, json);
    });

    test('handles boundary values: zero duration, zero speakers', () {
      final original = ConversationRecord(
        id: 'j0',
        filename: 'f0',
        createdAt: DateTime(2026, 1, 1),
        durationSec: 0.0,
        speakerCount: 0,
        resultJson: '{}',
      );
      final restored = ConversationRecord.fromMap(original.toMap());
      expect(restored.durationSec, 0.0);
      expect(restored.speakerCount, 0);
    });
  });
}
