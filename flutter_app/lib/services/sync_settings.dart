import 'package:shared_preferences/shared_preferences.dart';

/// Preference key: whether a newly completed conversation is auto-synced to
/// the cloud immediately. Off by default — sync is an explicit user action.
const autoSyncPrefKey = 'auto_sync_conversations';

/// Reads the auto-sync preference. Defaults to false (opt-in).
Future<bool> autoSyncEnabled() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(autoSyncPrefKey) ?? false;
  } catch (_) {
    return false;
  }
}

/// Persists the auto-sync preference.
Future<void> setAutoSyncEnabled(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(autoSyncPrefKey, value);
}
