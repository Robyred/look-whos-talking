import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/job_result.dart';
import '../services/api_service.dart';
import '../utils/name_detector.dart';
import 'name_review_screen.dart';

class ProcessingScreen extends StatefulWidget {
  final File audioFile;

  const ProcessingScreen({super.key, required this.audioFile});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final _api = ApiService();

  // null = show configure UI; non-null = pipeline running or failed
  bool _configuring = true;
  int? _speakerCount; // null = don't know

  String _statusMessage = 'Uploading audio…';
  bool _failed = false;
  String? _error;

  static const _pollIntervalSec = 3;
  static const _maxPolls = 200;

  void _start() {
    setState(() => _configuring = false);
    _runPipeline();
  }

  Future<void> _runPipeline() async {
    String jobId;
    try {
      jobId = await _api.submitJob(
        widget.audioFile,
        speakerCount: _speakerCount,
      );
    } catch (e) {
      _setFailed('Upload failed: $e');
      return;
    }

    _setMessage('Processing audio — this can take a minute…');

    for (var i = 0; i < _maxPolls; i++) {
      await Future.delayed(const Duration(seconds: _pollIntervalSec));

      JobStatusResponse status;
      try {
        status = await _api.pollJob(jobId);
      } catch (e) {
        _setFailed('Connection error: $e');
        return;
      }

      switch (status.status) {
        case JobStatus.pending:
          _setMessage('Queued — waiting to start…');
        case JobStatus.processing:
          _setMessage('Diarizing speakers…');
        case JobStatus.complete:
          if (status.result == null) {
            _setFailed('Job complete but no result received');
            return;
          }
          if (!mounted) return;
          final detection = detectNames(status.result!.transcript);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => NameReviewScreen(
                jobId: status.jobId,
                result: status.result!,
                proposals: detection.proposals,
                audioFile: widget.audioFile,
              ),
            ),
          );
          return;
        case JobStatus.failed:
          _setFailed(status.error ?? 'Processing failed');
          return;
      }
    }

    _setFailed('Timed out — try a shorter recording');
  }

  void _setMessage(String msg) {
    if (mounted) setState(() => _statusMessage = msg);
  }

  void _setFailed(String err) {
    if (mounted) {
      setState(() {
        _failed = true;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filename = p.basename(widget.audioFile.path);

    return PopScope(
      canPop: _failed || _configuring,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_configuring ? 'Configure' : 'Analyzing'),
          automaticallyImplyLeading: _failed || _configuring,
        ),
        body: Padding(
          padding: const EdgeInsets.all(32.0),
          child: _configuring
              ? _ConfigureBody(
                  filename: filename,
                  speakerCount: _speakerCount,
                  onCountChanged: (v) => setState(() => _speakerCount = v),
                  onStart: _start,
                )
              : _RunningBody(
                  failed: _failed,
                  statusMessage: _statusMessage,
                  filename: filename,
                  error: _error,
                ),
        ),
      ),
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
        _SpeakerPicker(
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

class _SpeakerPicker extends StatelessWidget {
  final int? selected;
  final ValueChanged<int?> onChanged;

  // null = "Don't know", 6 = "6+" (we pass min_speakers=6, no max)
  static const _options = <(int?, String)>[
    (null, "Don't know"),
    (2, '2'),
    (3, '3'),
    (4, '4'),
    (5, '5'),
    (6, '6+'),
  ];

  const _SpeakerPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: _options.map((opt) {
        final (value, label) = opt;
        final isSelected = selected == value;
        return Material(
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => onChanged(value),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? cs.onPrimaryContainer
                      : cs.onSurface,
                ),
              ),
            ),
          ),
        );
      }).toList(),
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
