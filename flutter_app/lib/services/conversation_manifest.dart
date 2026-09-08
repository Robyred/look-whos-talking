import 'dart:convert';

import '../models/conversation_record.dart';

/// Metadata sidecar uploaded next to result.json for each conversation.
///
/// The backend result JSON has no filename/createdAt of its own beyond what is
/// inside the transcript payload, so a tiny manifest lets a new device restore
/// real filenames and dates without downloading every result file.
class ConversationManifest {
  final String id;
  final String filename;
  final DateTime createdAt;
  final double durationSec;
  final int speakerCount;

  const ConversationManifest({
    required this.id,
    required this.filename,
    required this.createdAt,
    required this.durationSec,
    required this.speakerCount,
  });

  factory ConversationManifest.fromRecord(ConversationRecord record) =>
      ConversationManifest(
        id: record.id,
        filename: record.filename,
        createdAt: record.createdAt,
        durationSec: record.durationSec,
        speakerCount: record.speakerCount,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'filename': filename,
        'created_at': createdAt.toUtc().toIso8601String(),
        'duration_sec': durationSec,
        'speaker_count': speakerCount,
      };

  factory ConversationManifest.fromJson(Map<String, dynamic> json) {
    return ConversationManifest(
      id: json['id'] as String,
      filename: json['filename'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      durationSec: (json['duration_sec'] as num).toDouble(),
      speakerCount: json['speaker_count'] as int,
    );
  }

  String encode() => jsonEncode(toJson());

  static ConversationManifest decode(String source) =>
      ConversationManifest.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
