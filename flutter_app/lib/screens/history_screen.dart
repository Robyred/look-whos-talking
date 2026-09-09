import 'dart:io';

import 'package:flutter/material.dart';

import '../models/conversation_record.dart';
import '../models/sync_summary.dart';
import '../view_models/history_view_model.dart';
import 'results_screen.dart';

String _formatDate(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDuration(double sec) {
  final h = sec ~/ 3600;
  final m = (sec ~/ 60) % 60;
  final s = sec.toInt() % 60;
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// History tab: past conversations with sync and audio-management actions.
///
/// The [HistoryViewModel] (and its store/sync/cloud dependencies) is injected
/// so this screen stays fully testable; wiring lives at the call site.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.viewModel});

  final HistoryViewModel viewModel;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryViewModel get _vm => widget.viewModel;

  // True while a sync/restore is running — disables the action buttons so a
  // double tap can't start two overlapping runs (which could duplicate uploads).
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onVmChanged);
    _vm.load();
    _vm.refreshCloudAuth();
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    super.dispose();
  }

  void _onVmChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openRecord(ConversationRecord record) async {
    final result = _vm.parseResult(record);
    if (result == null || !mounted) return;
    // Pass the stored audio through so recordings keep their Playback tab.
    File? audioFile;
    final audioPath = record.audioPath;
    if (audioPath != null && await File(audioPath).exists()) {
      audioFile = File(audioPath);
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          jobId: record.id,
          result: result,
          audioFile: audioFile,
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(ConversationRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          '"${record.filename}" and its audio file will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteAudioOnly(ConversationRecord record) async {
    await _vm.deleteAudio(record.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Audio deleted — transcript kept for '
              '"${record.filename}"'),
        ),
      );
    }
  }

  Future<void> _syncAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    SyncSummary summary;
    try {
      summary = await _vm.syncAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    for (final error in summary.errors) {
      debugPrint('sync failure: $error');
    }
    String message;
    if (summary.failed == 0) {
      message = 'Synced ${summary.succeeded} conversation(s)';
    } else if (summary.errors.isNotEmpty) {
      final first = summary.errors.first;
      message = 'Synced ${summary.succeeded}, ${summary.failed} failed: '
          '${first.length > 220 ? '${first.substring(0, 220)}…' : first}';
    } else {
      message = 'Synced ${summary.succeeded}, ${summary.failed} failed';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    int restored;
    try {
      restored = await _vm.restoreFromCloud();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored > 0
              ? 'Restored $restored conversation(s) from cloud'
              : 'Nothing new to restore',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildActionBar(context),
            const Divider(height: 1),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final showSync = _vm.cloudAuthenticated && _vm.hasUnsynced;
    final showRestore = _vm.cloudAuthenticated;
    if (!showSync && !showRestore) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (showSync) ...[
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _syncAll,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Sync all'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (showRestore)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.cloud_download),
                label: const Text('Restore from cloud'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_vm.state) {
      case HistoryLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case HistoryLoadState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load history',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  _vm.error ?? 'Unknown error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: _vm.load, child: const Text('Retry')),
              ],
            ),
          ),
        );
      case HistoryLoadState.loaded:
        if (_vm.records.isEmpty) {
          return const Center(child: Text('No conversations yet'));
        }
        return ListView.separated(
          itemCount: _vm.records.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final record = _vm.records[index];
            return _buildRow(context, record);
          },
        );
    }
  }

  Widget _buildRow(BuildContext context, ConversationRecord record) {
    final hasAudio = record.audioPath != null;

    return Dismissible(
      key: ValueKey('history-${record.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(record),
      onDismissed: (_) => _vm.delete(record.id),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        onTap: () => _openRecord(record),
        onLongPress: () => _showRowMenu(record),
        title: Text(
          record.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_formatDate(record.createdAt)} · '
          '${_formatDuration(record.durationSec)} · '
          '${record.speakerCount} speaker${record.speakerCount == 1 ? '' : 's'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              record.isSynced ? Icons.cloud_done : Icons.cloud_upload,
              size: 18,
              color: record.isSynced
                  ? Colors.green.shade600
                  : Colors.grey.shade500,
            ),
            const SizedBox(width: 10),
            Icon(
              hasAudio ? Icons.graphic_eq : Icons.music_off,
              size: 18,
              color: hasAudio ? Colors.indigo : Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _showRowMenu(ConversationRecord record) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                record.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              subtitle: const Text('Conversation options'),
            ),
            const Divider(height: 1),
            ListTile(
              enabled: record.audioPath != null,
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete audio only'),
              subtitle: const Text('Keeps transcript and insights'),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteAudioOnly(record);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: const Text('Delete conversation'),
              subtitle: const Text('Removes the record and audio'),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteWithConfirm(record);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteWithConfirm(ConversationRecord record) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          '"${record.filename}" and its audio file will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _vm.delete(record.id);
    }
  }
}
