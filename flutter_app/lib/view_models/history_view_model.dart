import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/conversation_record.dart';
import '../models/job_result.dart';
import '../models/sync_summary.dart';
import '../services/conversation_store.dart';
import '../services/sync_service.dart';

enum HistoryLoadState { loading, loaded, error }

/// State for the History screen: list of saved conversations plus sync
/// actions. All dependencies are injected so the logic is unit-testable.
class HistoryViewModel extends ChangeNotifier {
  HistoryViewModel({
    required this.store,
    required this.syncService,
  });

  final ConversationStore store;
  final SyncService syncService;

  HistoryLoadState state = HistoryLoadState.loading;
  String? error;
  List<ConversationRecord> records = const [];
  SyncSummary? lastSyncSummary;
  bool cloudAuthenticated = false;

  /// True when at least one stored conversation has not been synced yet.
  bool get hasUnsynced => records.any((r) => !r.isSynced);

  /// Reads the cloud auth state so the screen can show/hide sync actions.
  /// An error (e.g. no sign-in plugin on this host) simply reads as
  /// "not authenticated" — never crash the screen over it.
  Future<void> refreshCloudAuth() async {
    try {
      cloudAuthenticated = await syncService.provider.isAuthenticated();
    } catch (_) {
      cloudAuthenticated = false;
    }
    notifyListeners();
  }


  /// Parses the stored backend JSON into a [DiarizationResult].
  DiarizationResult? parseResult(ConversationRecord record) {
    try {
      return DiarizationResult.fromJson(
        jsonDecode(record.resultJson) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    state = HistoryLoadState.loading;
    error = null;
    notifyListeners();
    try {
      records = await store.list();
      state = HistoryLoadState.loaded;
    } catch (e) {
      error = '$e';
      state = HistoryLoadState.error;
    }
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await store.delete(id);
    records = records.where((r) => r.id != id).toList();
    notifyListeners();
  }

  Future<void> deleteAudio(String id) async {
    await store.deleteAudio(id);
    records = [
      for (final r in records)
        if (r.id == id)
          ConversationRecord(
            id: r.id,
            filename: r.filename,
            createdAt: r.createdAt,
            durationSec: r.durationSec,
            speakerCount: r.speakerCount,
            resultJson: r.resultJson,
            isSynced: r.isSynced,
          )
        else
          r,
    ];
    notifyListeners();
  }

  /// Uploads every unsynced conversation. Refreshes the list afterwards so the
  /// sync-status icons reflect the outcome.
  Future<SyncSummary> syncAll() async {
    final summary = await syncService.syncAll();
    lastSyncSummary = summary;
    await load();
    return summary;
  }

  /// Lists the remote index and downloads any conversation not already
  /// present locally. Refreshes state on completion.
  ///
  /// Throws [AuthException] when the cloud provider is not authenticated.
  Future<void> restoreFromCloud() async {
    final remote = await syncService.fetchRemoteIndex();
    final localIds = (await store.list()).map((r) => r.id).toSet();
    for (final meta in remote) {
      if (!localIds.contains(meta.id)) {
        await syncService.downloadConversation(meta.id);
      }
    }
    await load();
  }
}
