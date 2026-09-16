import 'package:flutter/material.dart';

/// Brand speaker colours (DESIGN_PLAN_v1 §2): coral, teal, amber, violet.
/// Speakers 5+ repeat the palette at 70% opacity.
const speakerColors = [
  Color(0xFFFF6B6B), // coral
  Color(0xFF4ECDC4), // teal
  Color(0xFFFFB347), // amber
  Color(0xFF9B7FE8), // violet
];

Color colorForSpeaker(String speakerId) {
  final idx = int.tryParse(speakerId.split('_').last) ?? 0;
  final base = speakerColors[idx % speakerColors.length];
  // 5th speaker onward: same palette, faded, so they stay distinguishable.
  if (idx >= speakerColors.length) return base.withValues(alpha: 0.7);
  return base;
}

// SPEAKER_00 → "Speaker 1", or the mapped name if present.
String speakerLabel(String speakerId, Map<String, String> nameMap) {
  if (nameMap.containsKey(speakerId)) return nameMap[speakerId]!;
  final idx = int.tryParse(speakerId.split('_').last) ?? 0;
  return 'Speaker ${idx + 1}';
}

// Returns initials for the avatar circle: "J" for Jane, "JS" for Jane Smith, "1" for unnamed.
String speakerInitials(String speakerId, Map<String, String> nameMap) {
  if (nameMap.containsKey(speakerId)) {
    final name = nameMap[speakerId]!.trim();
    final words = name.split(RegExp(r'\s+'));
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}'.toUpperCase();
    return name.substring(0, 1).toUpperCase();
  }
  final idx = int.tryParse(speakerId.split('_').last) ?? 0;
  return '${idx + 1}';
}
