// Dart mirrors of the FastAPI response models in backend/models.py.
import 'dart:convert';

class SpeakerResult {
  final String speakerId;
  final double durationSec;
  final double percentage;

  const SpeakerResult({
    required this.speakerId,
    required this.durationSec,
    required this.percentage,
  });

  factory SpeakerResult.fromJson(Map<String, dynamic> json) => SpeakerResult(
        speakerId: json['speaker_id'] as String,
        durationSec: (json['duration_sec'] as num).toDouble(),
        percentage: (json['percentage'] as num).toDouble(),
      );
}

class TranscriptSegment {
  final String speakerId;
  final double start;
  final double end;
  final String text;

  const TranscriptSegment({
    required this.speakerId,
    required this.start,
    required this.end,
    required this.text,
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) =>
      TranscriptSegment(
        speakerId: json['speaker_id'] as String,
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
        text: json['text'] as String,
      );
}

class DiarizationResult {
  final String filename;
  final double totalDurationSec;
  final int speakerCount;
  final List<SpeakerResult> speakers;
  final double overlapSec;
  final double speechSec;
  final double silenceSec;
  final List<TranscriptSegment> transcript;

  const DiarizationResult({
    required this.filename,
    required this.totalDurationSec,
    required this.speakerCount,
    required this.speakers,
    required this.overlapSec,
    required this.speechSec,
    required this.silenceSec,
    required this.transcript,
  });

  factory DiarizationResult.fromJson(Map<String, dynamic> json) =>
      DiarizationResult(
        filename: json['filename'] as String,
        totalDurationSec: (json['total_duration_sec'] as num).toDouble(),
        speakerCount: json['speaker_count'] as int,
        speakers: (json['speakers'] as List)
            .map((s) => SpeakerResult.fromJson(s as Map<String, dynamic>))
            .toList(),
        overlapSec: (json['overlap_sec'] as num).toDouble(),
        speechSec: (json['speech_sec'] as num).toDouble(),
        silenceSec: (json['silence_sec'] as num).toDouble(),
        transcript: (json['transcript'] as List? ?? [])
            .map((s) => TranscriptSegment.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

enum JobStatus { pending, processing, complete, failed }

class JobStatusResponse {
  final String jobId;
  final String filename;
  final JobStatus status;
  final String? error;
  final DiarizationResult? result;

  /// The backend's result object exactly as it arrived over HTTP (encoded
  /// from the decoded payload, never from a re-serialised model), so History
  /// can persist verbatim what the server returned. Null until the job
  /// completes with a result.
  final String? rawResultJson;

  const JobStatusResponse({
    required this.jobId,
    required this.filename,
    required this.status,
    this.error,
    this.result,
    this.rawResultJson,
  });

  factory JobStatusResponse.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String;
    final status = switch (statusStr) {
      'pending' => JobStatus.pending,
      'processing' => JobStatus.processing,
      'complete' => JobStatus.complete,
      'failed' => JobStatus.failed,
      _ => JobStatus.pending,
    };
    return JobStatusResponse(
      jobId: json['job_id'] as String,
      filename: json['filename'] as String,
      status: status,
      error: json['error'] as String?,
      result: json['result'] != null
          ? DiarizationResult.fromJson(json['result'] as Map<String, dynamic>)
          : null,
      rawResultJson:
          json['result'] != null ? jsonEncode(json['result']) : null,
    );
  }
}
