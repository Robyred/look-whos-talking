import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/utils/speaker_utils.dart';

void main() {
  group('colorForSpeaker', () {
    test('SPEAKER_00 returns the first palette color', () {
      expect(colorForSpeaker('SPEAKER_00'), equals(speakerColors[0]));
    });

    test('SPEAKER_07 returns the eighth palette color (index 7)', () {
      expect(colorForSpeaker('SPEAKER_07'), equals(speakerColors[7]));
    });

    test('SPEAKER_08 wraps around to index 0 (palette has 8 entries)', () {
      expect(colorForSpeaker('SPEAKER_08'), equals(speakerColors[0]));
    });

    test('SPEAKER_09 wraps to index 1', () {
      expect(colorForSpeaker('SPEAKER_09'), equals(speakerColors[1]));
    });

    test('ID with no trailing number falls back to index 0', () {
      expect(colorForSpeaker('UNKNOWN'), equals(speakerColors[0]));
    });

    test('returns consistent Color values across calls', () {
      expect(colorForSpeaker('SPEAKER_03'), equals(colorForSpeaker('SPEAKER_03')));
    });
  });

  group('speakerLabel', () {
    test('no nameMap → "Speaker 1" for SPEAKER_00', () {
      expect(speakerLabel('SPEAKER_00', {}), equals('Speaker 1'));
    });

    test('no nameMap → "Speaker 3" for SPEAKER_02', () {
      expect(speakerLabel('SPEAKER_02', {}), equals('Speaker 3'));
    });

    test('nameMap contains key → returns mapped name', () {
      expect(
        speakerLabel('SPEAKER_00', {'SPEAKER_00': 'Alice'}),
        equals('Alice'),
      );
    });

    test('nameMap does not contain this key → falls back to "Speaker N"', () {
      expect(
        speakerLabel('SPEAKER_01', {'SPEAKER_00': 'Alice'}),
        equals('Speaker 2'),
      );
    });

    test('nameMap maps a different speaker; this one falls back', () {
      const map = {'SPEAKER_02': 'Bob'};
      expect(speakerLabel('SPEAKER_00', map), equals('Speaker 1'));
      expect(speakerLabel('SPEAKER_02', map), equals('Bob'));
    });
  });

  group('speakerInitials', () {
    test('unnamed SPEAKER_00 → "1"', () {
      expect(speakerInitials('SPEAKER_00', {}), equals('1'));
    });

    test('unnamed SPEAKER_02 → "3"', () {
      expect(speakerInitials('SPEAKER_02', {}), equals('3'));
    });

    test('single-word name "Jane" → "J"', () {
      expect(speakerInitials('SPEAKER_00', {'SPEAKER_00': 'Jane'}), equals('J'));
    });

    test('two-word name "Jane Smith" → "JS"', () {
      expect(
        speakerInitials('SPEAKER_00', {'SPEAKER_00': 'Jane Smith'}),
        equals('JS'),
      );
    });

    test('name with extra surrounding spaces → first-letter initials', () {
      expect(
        speakerInitials('SPEAKER_00', {'SPEAKER_00': '  Alice  Jones  '}),
        equals('AJ'),
      );
    });

    test('three-word name → uses only first two words for initials', () {
      expect(
        speakerInitials('SPEAKER_00', {'SPEAKER_00': 'Mary Jane Watson'}),
        equals('MJ'),
      );
    });

    test('single-character name edge case → that character uppercased', () {
      expect(
        speakerInitials('SPEAKER_00', {'SPEAKER_00': 'A'}),
        equals('A'),
      );
    });
  });
}
