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

/// Which delete action the user chose from the dialog.
enum _DeleteChoice { none, localOnly, localAndCloud }

/// History screen: past conversations with sync, selection, and audio
/// management. Cloud sync is explicit (auto-sync is opt-in elsewhere).
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

  // Multi-select state for "sync selected".
  bool _selecting = false;
  final Set<String> _selectedIds = {};

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

  void _enterSelection() => setState(() {
        _selecting = true;
        _selectedIds.clear();
      });

  void _exitSelection() => setState(() {
        _selecting = false;
        _selectedIds.clear();
      });

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  Future<void> _openRecord(ConversationRecord record) async {
    if (_selecting) {
      _toggleSelected(record.id);
      return;
    }
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

  Future<void> _showSyncResult(SyncSummary summary) async {
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
    await _showSyncResult(summary);
  }

  Future<void> _syncSelected() async {
    final ids = _selectedIds.toList();
    if (_busy || ids.isEmpty) return;
    setState(() => _busy = true);
    SyncSummary summary;
    try {
      summary = await _vm.syncSelected(ids);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) _exitSelection();
    if (!mounted) return;
    await _showSyncResult(summary);
  }

  Future<void> _syncOne(ConversationRecord record) async {
    if (_busy) return;
    setState(() => _busy = true);
    SyncSummary summary;
    try {
      summary = await _vm.syncSelected([record.id]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await _showSyncResult(summary);
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

  Future<_DeleteChoice> _showDeleteDialog(ConversationRecord record) {
    final synced = record.isSynced;
    return showDialog<_DeleteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          synced
              ? '"${record.filename}" will be deleted locally and, if you '
                  'choose, removed from cloud storage.'
              : '"${record.filename}" and its audio file will be '
                  'permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DeleteChoice.none),
            child: const Text('Cancel'),
          ),
          if (synced)
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_DeleteChoice.localOnly),
              child: const Text('Delete (local)'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
                synced ? _DeleteChoice.localAndCloud : _DeleteChoice.localOnly),
            child: Text(synced ? 'Delete & remove from cloud' : 'Delete'),
          ),
        ],
      ),
    ).then((c) => c ?? _DeleteChoice.none);
  }

  // Swipe-to-delete stays local-only (quick action); cloud removal is offered
  // from the row menu's "Delete conversation".
  Future<bool> _confirmSwipeDelete(ConversationRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          '"${record.filename}" and its audio file will be permanently '
          'deleted from this device.',
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

  Future<void> _deleteWithConfirm(ConversationRecord record) async {
    if (!mounted) return;
    final choice = await _showDeleteDialog(record);
    if (choice == _DeleteChoice.none || !mounted) return;
    await _vm.deleteConversation(
      record,
      alsoCloud: choice == _DeleteChoice.localAndCloud,
    );
  }

  List<ConversationRecord> _selectedRecords() => _vm.records
      .where((r) => _selectedIds.contains(r.id))
      .toList();

  Future<_DeleteChoice> _showBulkDeleteDialog(
    int count, {
    required bool offerCloud,
  }) {
    return showDialog<_DeleteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count conversation(s)?'),
        content: Text(
          offerCloud
              ? 'The selected conversations will be deleted from this device '
                  'and, if you choose, removed from cloud storage.'
              : 'The selected conversations and their audio will be '
                  'permanently deleted from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DeleteChoice.none),
            child: const Text('Cancel'),
          ),
          if (offerCloud)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_DeleteChoice.localOnly),
              child: const Text('Delete (local)'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
                offerCloud ? _DeleteChoice.localAndCloud : _DeleteChoice.localOnly),
            child: Text(offerCloud ? 'Delete & remove from cloud' : 'Delete'),
          ),
        ],
      ),
    ).then((c) => c ?? _DeleteChoice.none);
  }

  Future<void> _deleteSelected() async {
    if (_busy) return;
    final records = _selectedRecords();
    if (records.isEmpty) return;
    final offerCloud =
        _vm.cloudAuthenticated && records.any((r) => r.isSynced);
    final choice = await _showBulkDeleteDialog(
      records.length,
      offerCloud: offerCloud,
    );
    if (choice == _DeleteChoice.none || !mounted) return;

    setState(() => _busy = true);
    try {
      for (final record in records) {
        await _vm.deleteConversation(
          record,
          alsoCloud: choice == _DeleteChoice.localAndCloud,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) _exitSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          choice == _DeleteChoice.localAndCloud
              ? 'Deleted ${records.length} conversation(s), including cloud'
              : 'Deleted ${records.length} conversation(s)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selecting ? '${_selectedIds.length} selected' : 'History',
        ),
        actions: [
          if (_vm.records.isNotEmpty)
            TextButton(
              onPressed: _selecting ? _exitSelection : _enterSelection,
              child: Text(_selecting ? 'Done' : 'Select'),
            ),
          const SizedBox(width: 8),
        ],
      ),
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
    final authed = _vm.cloudAuthenticated;
    if (_selecting) {
      final count = _selectedIds.length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || count == 0 || !authed
                    ? null
                    : _syncSelected,
                icon: const Icon(Icons.cloud_upload),
                label: Text('Sync selected ($count)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || count == 0 ? null : _deleteSelected,
                icon: const Icon(Icons.delete_outline),
                label: Text('Delete selected ($count)'),
              ),
            ),
          ],
        ),
      );
    }
    final showSync = authed;
    if (!showSync) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _syncAll,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Sync all'),
            ),
          ),
          const SizedBox(width: 12),
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
    final selected = _selecting && _selectedIds.contains(record.id);

    final tile = ListTile(
      onTap: () => _openRecord(record),
      onLongPress: _selecting ? null : () => _showRowMenu(record),
      leading: _selecting
          ? Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelected(record.id),
            )
          : null,
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
      selected: selected,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            record.isSynced ? Icons.cloud_done : Icons.cloud_upload,
            size: 18,
            color: record.isSynced ? Colors.green.shade600 : Colors.grey.shade500,
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
    );

    if (_selecting) return tile;
    return Dismissible(
      key: ValueKey('history-${record.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmSwipeDelete(record),
      onDismissed: (_) => _vm.delete(record.id),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: tile,
    );
  }

  void _showRowMenu(ConversationRecord record) {
    final authed = _vm.cloudAuthenticated;
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
              enabled: authed && !_busy,
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Sync to cloud'),
              onTap: () {
                Navigator.of(ctx).pop();
                _syncOne(record);
              },
            ),
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
              subtitle: const Text('Local, with optional cloud removal'),
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
}
