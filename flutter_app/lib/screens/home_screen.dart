import 'package:flutter/material.dart';

import '../models/conversation_record.dart';
import '../services/cloud_storage_provider.dart';
import '../services/conversation_store.dart';
import '../services/storage_cleanup_service.dart';
import '../services/sync_service.dart';
import '../view_models/history_view_model.dart';
import 'history_screen.dart';
import 'record_screen.dart';
import 'settings_screen.dart';
import 'upload_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Shared local store — same instance used by ProcessingScreen and History.
  final ConversationStore store;

  /// Shared cloud backend — same instance used by ProcessingScreen and History.
  final CloudStorageProvider cloud;

  /// All connectable providers, shown on the Settings screen.
  final List<CloudStorageProvider> cloudProviders;

  const HomeScreen({
    super.key,
    required this.store,
    required this.cloud,
    this.cloudProviders = const [],
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Delayed to after the first frame so the dialog never interrupts build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptStorageCleanup();
    });
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HistoryScreen(
          viewModel: HistoryViewModel(
            store: widget.store,
            // A fresh view model per push is deliberate — each visit reloads.
            syncService: SyncService(
              store: widget.store,
              provider: widget.cloud,
            ),
          ),
        ),
      ),
    );
  }

  // Offer to delete audio files that have aged past the threshold, unless the
  // user was asked recently. All failures are swallowed — this is a launch
  // nicety, never something that should stop the app starting.
  Future<void> _maybePromptStorageCleanup() async {
    final cleanup = StorageCleanupService(store: widget.store);

    bool should;
    try {
      should = await cleanup.shouldPrompt();
    } catch (_) {
      return;
    }
    if (!should || !mounted) return;

    List<ConversationRecord> old;
    int bytes;
    try {
      old = await cleanup.findOldAudioRecords(
        olderThanDays: StorageCleanupService.defaultOlderThanDays,
      );
      bytes = await cleanup.totalAudioSizeBytes(old);
    } catch (_) {
      return;
    }
    if (old.isEmpty || !mounted) return;

    final days = StorageCleanupService.defaultOlderThanDays;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Free up storage?'),
        content: Text(
          '${old.length} recording(s) older than $days days '
          '(${_formatMb(bytes)} MB). Delete audio files? '
          'Transcripts and insights are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // "Remind me later" — no suppression, re-prompt next launch.
            },
            child: const Text('Remind me later'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await cleanup.recordPromptShown(); // suppress for 30 days
            },
            child: const Text('Keep for now'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await cleanup.deleteAudioForRecords(old);
              await cleanup.recordPromptShown();
            },
            child: Text(
              'Delete audio',
              style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(providers: widget.cloudProviders),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: _openHistory,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Icon(Icons.record_voice_over,
                      size: 72, color: Colors.indigo),
                  const SizedBox(height: 16),
                  Text(
                    'Look Who\'s Talking',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Upload or record a conversation\nto identify speakers',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  _ActionCard(
                    icon: Icons.mic,
                    label: 'Record Audio',
                    subtitle: 'Use your phone\'s microphone',
                    color: Colors.indigo,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecordScreen(
                          store: widget.store,
                          cloud: widget.cloud,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ActionCard(
                    icon: Icons.upload_file,
                    label: 'Upload File',
                    subtitle: 'WAV, MP3, M4A, FLAC',
                    color: Colors.deepOrange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UploadScreen(
                          store: widget.store,
                          cloud: widget.cloud,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatMb(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 100 ? mb.round().toString() : mb.toStringAsFixed(1);
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600])),
                  ],
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
