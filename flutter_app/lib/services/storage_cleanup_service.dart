import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation_record.dart';
import 'conversation_store.dart';

/// Finds conversations whose audio files have aged past a threshold and offers
/// to delete just the audio — transcripts and insights are never touched.
class StorageCleanupService {
  StorageCleanupService({required this.store, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static const defaultOlderThanDays = 90;
  static const promptSuppressionDays = 30;
  static const lastPromptKey = 'storage_cleanup_last_prompt';

  final ConversationStore store;
  final DateTime Function() _now;

  /// Records with a non-null audioPath whose createdAt predates the cutoff.
  Future<List<ConversationRecord>> findOldAudioRecords({
    required int olderThanDays,
  }) async {
    final cutoff = _now().subtract(Duration(days: olderThanDays));
    final records = await store.list();
    return records
        .where(
          (r) => r.audioPath != null && r.createdAt.isBefore(cutoff),
        )
        .toList();
  }

  /// Total bytes of the audio files that actually exist on disk.
  /// Files already deleted (or null paths) contribute zero.
  Future<int> totalAudioSizeBytes(List<ConversationRecord> records) async {
    var total = 0;
    for (final record in records) {
      final path = record.audioPath;
      if (path == null) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      total += await file.length();
    }
    return total;
  }

  /// Deletes audio for each given record. Records themselves survive.
  Future<void> deleteAudioForRecords(List<ConversationRecord> records) async {
    for (final record in records) {
      await store.deleteAudio(record.id);
    }
  }

  /// True when audio is older than the default threshold AND the user has not
  /// been prompted within [promptSuppressionDays].
  Future<bool> shouldPrompt() async {
    final old = await findOldAudioRecords(
      olderThanDays: defaultOlderThanDays,
    );
    if (old.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(lastPromptKey);
    if (stored == null) return true; // never asked before
    final lastPrompt = DateTime.tryParse(stored);
    if (lastPrompt == null) return true; // corrupt stamp — ask again

    final stillSuppressed = lastPrompt
        .isAfter(_now().subtract(Duration(days: promptSuppressionDays)));
    return !stillSuppressed;
  }

  /// Persists today as the last-prompted date, suppressing the prompt for
  /// [promptSuppressionDays].
  Future<void> recordPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastPromptKey, _now().toIso8601String());
  }
}
