import 'package:flutter/material.dart';

import '../services/cloud_storage_provider.dart';
import '../services/sync_settings.dart';

/// Cloud-storage connections. Each provider in [providers] gets a row with
/// Connect/Disconnect — sync through those providers is wired up later.
class SettingsScreen extends StatefulWidget {
  final List<CloudStorageProvider> providers;

  const SettingsScreen({super.key, required this.providers});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Auth state per provider instance, loaded in initState.
  final Map<CloudStorageProvider, bool> _authState = {};
  bool _loading = false;
  bool _autoSync = false;

  @override
  void initState() {
    super.initState();
    for (final provider in widget.providers) {
      _authState[provider] = false;
    }
    _refreshAuthStates();
    _loadAutoSync();
  }

  Future<void> _loadAutoSync() async {
    final value = await autoSyncEnabled();
    if (mounted) setState(() => _autoSync = value);
  }

  Future<void> _setAutoSync(bool value) async {
    setState(() => _autoSync = value);
    await setAutoSyncEnabled(value);
  }

  // Best-effort initial read; an unavailable provider simply shows as
  // "Not connected" rather than crashing the screen.
  Future<void> _refreshAuthStates() async {
    for (final provider in widget.providers) {
      try {
        _authState[provider] = await provider.isAuthenticated();
      } catch (_) {
        _authState[provider] = false;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _connect(CloudStorageProvider provider) async {
    setState(() => _loading = true);
    try {
      await provider.authenticate();
      _authState[provider] = await provider.isAuthenticated();
    } on AuthException {
      // User cancelled (or auth refused) — no snack needed.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect — $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disconnect(CloudStorageProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Disconnect ${provider.displayName}?'),
        content: const Text('Your files won\'t be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await provider.signOut();
      _authState[provider] = false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              'Cloud storage',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ),
          for (final provider in widget.providers)
            _ProviderRow(
              provider: provider,
              isAuthenticated: _authState[provider] ?? false,
              loading: _loading,
              onConnect: () => _connect(provider),
              onDisconnect: () => _disconnect(provider),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              'Sync',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ),
          SwitchListTile(
            value: _autoSync,
            onChanged: _setAutoSync,
            secondary: const Icon(Icons.sync),
            title: const Text('Auto-sync new conversations'),
            subtitle: const Text(
              'Upload new conversations to the cloud automatically. '
              'Off by default — sync is manual from History.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  final CloudStorageProvider provider;
  final bool isAuthenticated;
  final bool loading;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _ProviderRow({
    required this.provider,
    required this.isAuthenticated,
    required this.loading,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final connected = isAuthenticated;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            (connected ? Colors.green : Colors.grey).withAlpha(26),
        child: Icon(
          Icons.cloud_outlined,
          color: connected ? Colors.green[700] : Colors.grey[600],
        ),
      ),
      title: Text(provider.displayName),
      subtitle: Text(
        connected ? 'Connected' : 'Not connected',
        style: TextStyle(
          color: connected ? Colors.green[700] : Colors.grey[500],
        ),
      ),
      trailing: connected
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: loading ? null : onDisconnect,
                  child: const Text('Disconnect'),
                ),
              ],
            )
          : FilledButton(
              // The app theme makes FilledButtons full-width; inside a
              // ListTile trailing that would overflow, so cap the size here.
              style: FilledButton.styleFrom(
                minimumSize: const Size(96, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: loading ? null : onConnect,
              child: const Text('Connect'),
            ),
    );
  }
}
