import 'package:flutter/material.dart';

const speakerColors = [
  Color(0xFF4A90D9),
  Color(0xFFE67E22),
  Color(0xFF27AE60),
  Color(0xFF9B59B6),
  Color(0xFFE74C3C),
  Color(0xFF1ABC9C),
  Color(0xFFF39C12),
  Color(0xFF2C3E50),
];

Color colorForSpeaker(String speakerId) {
  final idx = int.tryParse(speakerId.split('_').last) ?? 0;
  return speakerColors[idx % speakerColors.length];
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
