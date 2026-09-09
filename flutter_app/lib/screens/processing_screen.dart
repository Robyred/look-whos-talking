import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/cloud_storage_provider.dart';
import '../services/conversation_store.dart';
import '../services/persist_completed_job.dart';
import '../services/sync_settings.dart';
import '../view_models/processing_view_model.dart';
import '../widgets/speaker_picker.dart';
import 'name_review_screen.dart';

/// Display name for a recording with no original filename, e.g.
/// "Recording 2026-09-08 14:05".
String recordingDisplayName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Recording ${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

class ProcessingScreen extends StatefulWidget {
  final File audioFile;

  /// Shared local store the completed job is saved into.
  final ConversationStore store;

  /// Cloud backend used for background sync after a successful save.
  final CloudStorageProvider cloud;

  /// Original filename (uploads); null means the audio came from a recording
  /// and the fallback "Recording YYYY-MM-DD HH:mm" label is used.
  final String? sourceFilename;

  /// True when the audio file lives somewhere durable (a fresh recording in
  /// app documents) and its path should be persisted for later playback.
  /// Uploaded files live in the picker's cache, so their paths are not kept.
  final bool retainAudio;

  const ProcessingScreen({
    super.key,
    required this.audioFile,
    required this.store,
    required this.cloud,
    this.sourceFilename,
    this.retainAudio = false,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  late ProcessingViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = ProcessingViewModel(audioFile: widget.audioFile);
    _vm.addListener(_onVmChanged);
  }

  void _onVmChanged() {
    if (_vm.phase == ProcessingPhase.complete && mounted) {
      _persistAndContinue();
    }
  }

  // Saves the completed job (best-effort, never throws) before moving on to
  // name review / results so the history record exists even if the user
  // quits right after.
  Future<void> _persistAndContinue() async {
    final status = _vm.completedStatus!;
    final result = status.result!;
    await persistCompletedJob(
      store: widget.store,
      cloud: widget.cloud,
      autoSync: await autoSyncEnabled(),
      jobId: status.jobId,
      filename: widget.sourceFilename ?? recordingDisplayName(DateTime.now()),
      createdAt: DateTime.now(),
      durationSec: result.totalDurationSec,
      speakerCount: result.speakerCount,
      resultJson: status.rawResultJson ?? '',
      audioPath: widget.retainAudio ? widget.audioFile.path : null,
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => NameReviewScreen(
          jobId: status.jobId,
          result: result,
          proposals: _vm.detectionResult!.proposals,
          audioFile: widget.audioFile,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filename = p.basename(widget.audioFile.path);
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final configuring = _vm.phase == ProcessingPhase.configuring;
        final failed = _vm.phase == ProcessingPhase.failed;
        return PopScope(
          canPop: configuring || failed,
          child: Scaffold(
            appBar: AppBar(
              title: Text(configuring ? 'Configure' : 'Analyzing'),
              automaticallyImplyLeading: configuring || failed,
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: configuring
                      ? _ConfigureBody(
                          filename: filename,
                          speakerCount: _vm.speakerCount,
                          onCountChanged: _vm.setSpeakerCount,
                          onStart: _vm.start,
                        )
                      : _RunningBody(
                          failed: failed,
                          statusMessage: _vm.statusMessage,
                          filename: filename,
                          error: _vm.error,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Configure phase ──────────────────────────────────────────────────────────

class _ConfigureBody extends StatelessWidget {
  final String filename;
  final int? speakerCount;
  final ValueChanged<int?> onCountChanged;
  final VoidCallback onStart;

  const _ConfigureBody({
    required this.filename,
    required this.speakerCount,
    required this.onCountChanged,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mic, size: 48, color: Colors.indigo[300]),
        const SizedBox(height: 20),
        Text(
          filename,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey[500]),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 32),
        Text(
          'How many speakers?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Knowing the speaker count helps the model\nassign voices more accurately.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey[500]),
        ),
        const SizedBox(height: 20),
        SpeakerPicker(
          selected: speakerCount,
          onChanged: onCountChanged,
        ),
        const SizedBox(height: 36),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Analyze recording'),
        ),
      ],
    );
  }
}

// ─── Running / failed phase ───────────────────────────────────────────────────

class _RunningBody extends StatelessWidget {
  final bool failed;
  final String statusMessage;
  final String filename;
  final String? error;

  const _RunningBody({
    required this.failed,
    required this.statusMessage,
    required this.filename,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.error_outline, size: 56, color: Colors.red),
          const SizedBox(height: 24),
          Text(
            'Something went wrong',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            error ?? 'Unknown error',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Go Back'),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          statusMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          filename,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey[500]),
        ),
      ],
    );
  }
}
