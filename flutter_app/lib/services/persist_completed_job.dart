import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/conversation_record.dart';
import 'cloud_storage_provider.dart';
import 'conversation_store.dart';
import 'sync_service.dart';

/// Persists one completed diarization job to the local [store]. A cloud
/// upload only happens after a save when [autoSync] is true (cloud sync is
/// opt-in — the Settings "Auto-sync" switch defaults to off) and the provider
/// is authenticated; otherwise the user syncs explicitly from History.
///
/// All steps are best-effort by design: a local save failure must never block
/// navigation to the results, and a cloud failure is recoverable later from
/// the History screen, so this function never throws.
Future<void> persistCompletedJob({
  required ConversationStore store,
  required String jobId,
  required String filename,
  required DateTime createdAt,
  required double durationSec,
  required int speakerCount,
  required String resultJson,
  String? audioPath,
  CloudStorageProvider? cloud,
  bool autoSync = false,
  SyncService Function(ConversationStore store, CloudStorageProvider cloud)?
      syncServiceFactory,
}) async {
  try {
    await store.save(
      ConversationRecord(
        id: jobId,
        filename: filename,
        createdAt: createdAt,
        durationSec: durationSec,
        speakerCount: speakerCount,
        resultJson: resultJson,
        audioPath: audioPath,
        // isSynced defaults to false — only an upload marks it synced.
      ),
    );
  } catch (e) {
    debugPrint('persistCompletedJob: failed to save job $jobId: $e');
    return;
  }

  if (!autoSync) return; // opt-in only

  final provider = cloud;
  if (provider == null) return;

  try {
    if (!await provider.isAuthenticated()) return;
    final sync = (syncServiceFactory ??
        (store, provider) => SyncService(store: store, provider: provider))(
      store,
      provider,
    );
    // Errors are deliberately swallowed: the user can sync manually from
    // the History screen.
    unawaited(sync.syncConversation(jobId).catchError((Object e) {
      debugPrint('persistCompletedJob: background sync of $jobId failed: $e');
    }));
  } catch (e) {
    // Auth state is unknowable (e.g. no sign-in plugin on this host) — treat
    // as "not signed in" and move on.
    debugPrint('persistCompletedJob: cloud auth check failed for $jobId: $e');
  }
}
