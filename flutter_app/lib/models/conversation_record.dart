// Local record of one completed diarization job — persisted in SQLite by
// ConversationStore and mirrored to the cloud by SyncService.

class ConversationRecord {
  final String id;
  final String filename;
  final DateTime createdAt;
  final double durationSec;
  final int speakerCount;
  final String resultJson;
  final String? audioPath;
  final bool isSynced;

  const ConversationRecord({
    required this.id,
    required this.filename,
    required this.createdAt,
    required this.durationSec,
    required this.speakerCount,
    required this.resultJson,
    this.audioPath,
    this.isSynced = false,
  });

  // Column names are shared with ConversationStore's SQL schema — keep in sync.
  // createdAt is stored as UTC ISO-8601 so SQL ORDER BY is chronologically
  // correct regardless of timezone or DST.
  Map<String, Object?> toMap() => {
        'id': id,
        'filename': filename,
        'created_at': createdAt.toUtc().toIso8601String(),
        'duration_sec': durationSec,
        'speaker_count': speakerCount,
        'result_json': resultJson,
        'audio_path': audioPath,
        'is_synced': isSynced ? 1 : 0,
      };

  factory ConversationRecord.fromMap(Map<String, Object?> map) {
    return ConversationRecord(
      id: map['id'] as String,
      filename: map['filename'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      durationSec: (map['duration_sec'] as num).toDouble(),
      speakerCount: map['speaker_count'] as int,
      resultJson: map['result_json'] as String,
      audioPath: map['audio_path'] as String?,
      isSynced: (map['is_synced'] as int) == 1,
    );
  }
}
