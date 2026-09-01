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

  String _statusMessage = 'Uploading audio…';
  bool _failed = false;
  String? _error;

  // Poll interval in seconds.
  static const _pollIntervalSec = 3;
  // Give up after 10 minutes.
  static const _maxPolls = 200;

  @override
  void initState() {
    super.initState();
    _runPipeline();
  }

  Future<void> _runPipeline() async {
    // --- Upload ---
    String jobId;
    try {
      jobId = await _api.submitJob(widget.audioFile);
    } catch (e) {
      _setFailed('Upload failed: $e');
      return;
    }

    _setMessage('Processing audio — this can take a minute…');

    // --- Poll ---
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
    if (mounted) {
      setState(() => _statusMessage = msg);
    }
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
      canPop: _failed,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Analyzing'),
          automaticallyImplyLeading: _failed,
        ),
        body: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_failed) ...[
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ).let((w) => Center(child: w)),
                const SizedBox(height: 32),
                Text(
                  _statusMessage,
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
              ] else ...[
                const Icon(Icons.error_outline, size: 56, color: Colors.red),
                const SizedBox(height: 24),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Unknown error',
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
            ],
          ),
        ),
      ),
    );
  }
}

// Small helper so we can write widget.let((w) => Center(child: w)).
extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
