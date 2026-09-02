import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/job_result.dart';
import 'package:look_whos_talking/utils/name_detector.dart';

TranscriptSegment seg(String speakerId, String text) =>
    TranscriptSegment(speakerId: speakerId, start: 0, end: 1, text: text);

void main() {
  group('detectNames — empty input', () {
    test('empty list → empty proposals map', () {
      final result = detectNames([]);
      expect(result.proposals, isEmpty);
    });
  });

  group('self-introduction patterns', () {
    test('"I\'m Jane" → SPEAKER_00 gets Jane', () {
      final result = detectNames([seg('SPEAKER_00', "I'm Jane, nice to meet you")]);
      expect(result.proposals['SPEAKER_00'], equals('Jane'));
    });

    test('"I am Sarah" → SPEAKER_00 gets Sarah', () {
      final result = detectNames([seg('SPEAKER_00', 'I am Sarah and I work here')]);
      expect(result.proposals['SPEAKER_00'], equals('Sarah'));
    });

    test('"My name is Tom" → SPEAKER_00 gets Tom', () {
      final result = detectNames([seg('SPEAKER_00', 'My name is Tom')]);
      expect(result.proposals['SPEAKER_00'], equals('Tom'));
    });

    test('"Call me Max" → SPEAKER_00 gets Max', () {
      final result = detectNames([seg('SPEAKER_00', 'Call me Max please')]);
      expect(result.proposals['SPEAKER_00'], equals('Max'));
    });

    test('"I go by Alex" → SPEAKER_00 gets Alex', () {
      final result = detectNames([seg('SPEAKER_00', 'I go by Alex')]);
      expect(result.proposals['SPEAKER_00'], equals('Alex'));
    });

    test('non-name filtered: "I\'m going" → no proposal', () {
      final result = detectNames([seg('SPEAKER_00', "I'm going to the shops")]);
      expect(result.proposals, isEmpty);
    });

    test('non-name filtered: "I\'m fine" → no proposal', () {
      final result = detectNames([seg('SPEAKER_00', "I'm fine thanks")]);
      expect(result.proposals, isEmpty);
    });

    test('non-name filtered: "I am not sure" → no proposal', () {
      final result = detectNames([seg('SPEAKER_00', 'I am not sure about that')]);
      expect(result.proposals, isEmpty);
    });

    test('frequency wins: Jane × 2 beats Janet × 1', () {
      final result = detectNames([
        seg('SPEAKER_00', "I'm Jane"),
        seg('SPEAKER_00', "My name is Jane"),
        seg('SPEAKER_00', "I am Janet"),
      ]);
      expect(result.proposals['SPEAKER_00'], equals('Jane'));
    });

    test('two speakers can each self-introduce independently', () {
      final result = detectNames([
        seg('SPEAKER_00', "I'm Alice"),
        seg('SPEAKER_01', "My name is Bob"),
      ]);
      expect(result.proposals['SPEAKER_00'], equals('Alice'));
      expect(result.proposals['SPEAKER_01'], equals('Bob'));
    });
  });

  group('greeting inference — 2 speakers only', () {
    test('"Hi John" from SPEAKER_00 → SPEAKER_01 gets John', () {
      final result = detectNames([
        seg('SPEAKER_00', 'Hi John, how are you?'),
        seg('SPEAKER_01', 'Good thanks'),
      ]);
      expect(result.proposals['SPEAKER_01'], equals('John'));
    });

    test('"Good morning Sarah" from SPEAKER_01 → SPEAKER_00 gets Sarah', () {
      final result = detectNames([
        seg('SPEAKER_00', 'Hello'),
        seg('SPEAKER_01', 'Good morning Sarah'),
      ]);
      expect(result.proposals['SPEAKER_00'], equals('Sarah'));
    });

    test('greeting inference does not apply with 3+ speakers', () {
      final result = detectNames([
        seg('SPEAKER_00', 'Hi John'),
        seg('SPEAKER_01', 'Hello'),
        seg('SPEAKER_02', 'Hey there'),
      ]);
      expect(result.proposals.containsKey('SPEAKER_01'), isFalse);
      expect(result.proposals.containsKey('SPEAKER_02'), isFalse);
    });

    test('greeting inference does not overwrite an existing self-intro', () {
      final result = detectNames([
        seg('SPEAKER_00', "I'm Alice"),
        seg('SPEAKER_01', 'Hi Alice'),
      ]);
      // SPEAKER_00 should keep her self-intro name, not be overwritten
      expect(result.proposals['SPEAKER_00'], equals('Alice'));
    });
  });

  group('third-party intro — 2 speakers only', () {
    test('"please welcome Vicky" from SPEAKER_00 → SPEAKER_01 gets Vicky', () {
      final result = detectNames([
        seg('SPEAKER_00', 'Please welcome Vicky to the show'),
        seg('SPEAKER_01', 'Thank you'),
      ]);
      expect(result.proposals['SPEAKER_01'], equals('Vicky'));
    });

    test('"let me introduce my colleague Ben" → SPEAKER_01 gets Ben', () {
      final result = detectNames([
        seg('SPEAKER_00', 'Let me introduce my colleague Ben'),
        seg('SPEAKER_01', 'Hi everyone'),
      ]);
      expect(result.proposals['SPEAKER_01'], equals('Ben'));
    });

    test('"this is my friend Anna" → SPEAKER_01 gets Anna', () {
      final result = detectNames([
        seg('SPEAKER_00', 'This is my friend Anna'),
        seg('SPEAKER_01', 'Nice to be here'),
      ]);
      expect(result.proposals['SPEAKER_01'], equals('Anna'));
    });

    test('third-party inference does not apply with 3+ speakers', () {
      final result = detectNames([
        seg('SPEAKER_00', 'Please welcome Vicky'),
        seg('SPEAKER_01', 'Thanks'),
        seg('SPEAKER_02', 'Hello'),
      ]);
      // No inference because there are 3 speakers
      expect(result.proposals.containsKey('SPEAKER_01'), isFalse);
      expect(result.proposals.containsKey('SPEAKER_02'), isFalse);
    });

    test('third-party intro does not overwrite self-intro', () {
      final result = detectNames([
        seg('SPEAKER_01', "I'm Clara"),
        seg('SPEAKER_00', 'Please welcome Vicky'),
      ]);
      // SPEAKER_01 introduced herself as Clara; that wins over the third-party Vicky
      expect(result.proposals['SPEAKER_01'], equals('Clara'));
    });
  });
}
