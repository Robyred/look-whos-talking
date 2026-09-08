import '../models/job_result.dart';

// Words that match the name patterns but are never actual names.
const _nonNames = {
  // filler / adjectives that follow "I am / I'm"
  'going', 'not', 'here', 'just', 'sorry', 'afraid', 'trying', 'thinking',
  'looking', 'sure', 'happy', 'glad', 'ready', 'done', 'fine', 'good',
  'bad', 'ok', 'okay', 'very', 'really', 'still', 'already', 'also',
  'actually', 'basically', 'pleased', 'delighted', 'excited', 'honored',
  'honoured', 'grateful', 'thrilled', 'proud', 'aware', 'certain', 'unsure',
  'confused', 'concerned', 'worried', 'surprised', 'amazed', 'able',
  // prepositions / determiners
  'the', 'a', 'an', 'in', 'on', 'at', 'to', 'for', 'of', 'and', 'or',
  'but', 'so', 'yet', 'from', 'with', 'by', 'as', 'up',
  // pronouns
  'your', 'our', 'their', 'this', 'that', 'it', 'he', 'she', 'we',
  'they', 'you', 'what', 'who', 'how', 'when', 'where', 'why', 'my',
  // gerunds
  'talking', 'speaking', 'saying', 'telling', 'asking', 'doing',
  'working', 'calling', 'coming', 'getting', 'putting', 'taking',
  'introducing', 'presenting', 'joining', 'welcoming',
};

// Speaker introduces themselves: "I'm Jane", "my name is Jane", etc.
final _introPatterns = [
  RegExp(r"i(?:'m| am)\s+([a-z][a-z]+)", caseSensitive: false),
  RegExp(r"my name(?:'s| is)\s+([a-z][a-z]+)", caseSensitive: false),
  RegExp(r'call me\s+([a-z][a-z]+)', caseSensitive: false),
  RegExp(r'i go by\s+([a-z][a-z]+)', caseSensitive: false),
];

// Speaker addresses the other person by name: "Hi John", "Good morning Sarah".
// Only used when there are exactly 2 speakers — infers the OTHER speaker's name.
final _greetingPatterns = [
  RegExp(r'(?:hello|hi|hey)[,\s]+([a-z][a-z]+)', caseSensitive: false),
  RegExp(r'good\s+(?:morning|afternoon|evening)[,\s]+([a-z][a-z]+)', caseSensitive: false),
  RegExp(r'nice to (?:meet|see) you[,\s]+([a-z][a-z]+)', caseSensitive: false),
];

// Speaker introduces a third party by name: "my friend Vicky", "please welcome Sarah".
// Only used when there are exactly 2 speakers — infers the OTHER speaker's name.
final _thirdPartyIntroPatterns = [
  // "introduce [my/our] [friend/colleague/guest] Name"
  RegExp(
    r'\bintroduce\b[^.]{0,30}?\b(?:friend|colleague|guest|co-host|partner|speaker)?\s+([a-z][a-z]+)',
    caseSensitive: false,
  ),
  // "I'd like you to meet Name" / "let me introduce Name"
  RegExp(
    r'(?:like you to meet|let me introduce|allow me to introduce|like to introduce|want to introduce)\s+(?:(?:my|our)\s+)?(?:friend|colleague|guest|co-host|partner)?\s*([a-z][a-z]+)',
    caseSensitive: false,
  ),
  // "this is my friend/colleague Name"
  RegExp(
    r'\bthis is my (?:friend|colleague|guest|partner|co-host)\s+([a-z][a-z]+)',
    caseSensitive: false,
  ),
  // "please welcome Name" / "welcome Name"
  RegExp(r'\bwelcome\s+([a-z][a-z]+)', caseSensitive: false),
  // "joining us [today/here/now] is Name"
  RegExp(
    r'\bjoining us\b[^.]{0,20}?\bis\s+([a-z][a-z]+)',
    caseSensitive: false,
  ),
];

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

bool _isValidName(String candidate) =>
    candidate.length >= 2 && !_nonNames.contains(candidate.toLowerCase());

class NameDetectionResult {
  final Map<String, String> proposals;

  const NameDetectionResult({required this.proposals});
}

NameDetectionResult detectNames(List<TranscriptSegment> segments) {
  if (segments.isEmpty) return const NameDetectionResult(proposals: {});

  final speakerIds = segments.map((s) => s.speakerId).toSet().toList();
  final introTally = <String, Map<String, int>>{};
  final otherNameTally = <String, Map<String, int>>{}; // greetings + third-party intros

  for (final seg in segments) {
    for (final pattern in _introPatterns) {
      for (final match in pattern.allMatches(seg.text)) {
        final candidate = match.group(1)!;
        if (!_isValidName(candidate)) continue;
        final name = _capitalize(candidate);
        final tally = introTally.putIfAbsent(seg.speakerId, () => {});
        tally[name] = (tally[name] ?? 0) + 1;
      }
    }
    for (final pattern in [..._greetingPatterns, ..._thirdPartyIntroPatterns]) {
      for (final match in pattern.allMatches(seg.text)) {
        final candidate = match.group(1)!;
        if (!_isValidName(candidate)) continue;
        final name = _capitalize(candidate);
        final tally = otherNameTally.putIfAbsent(seg.speakerId, () => {});
        tally[name] = (tally[name] ?? 0) + 1;
      }
    }
  }

  final proposals = <String, String>{};

  // Self-introductions: attributed directly to the speaker who said it.
  for (final entry in introTally.entries) {
    final best = entry.value.entries
        .reduce((a, b) => a.value >= b.value ? a : b);
    proposals[entry.key] = best.key;
  }

  // Greeting / third-party inference: "Hi John" or "my friend Vicky" from
  // Speaker A → the OTHER speaker is named John/Vicky.
  // Only reliable with exactly 2 speakers; only fills gaps left by introductions.
  if (speakerIds.length == 2) {
    for (final entry in otherNameTally.entries) {
      final otherSpeaker = speakerIds.firstWhere((id) => id != entry.key);
      if (proposals.containsKey(otherSpeaker)) continue;
      final best = entry.value.entries
          .reduce((a, b) => a.value >= b.value ? a : b);
      proposals[otherSpeaker] = best.key;
    }
  }

  return NameDetectionResult(proposals: proposals);
}
