import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/cloud_storage_provider.dart';
import '../services/conversation_store.dart';
import 'processing_screen.dart';

class RecordScreen extends StatefulWidget {
  final ConversationStore store;
  final CloudStorageProvider cloud;

  const RecordScreen({super.key, required this.store, required this.cloud});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordedPath;
  DateTime? _recordedAt;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/lwt_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordedPath = null;
      _recordedAt = null;
      _elapsed = Duration.zero;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _recordedPath = path;
      _recordedAt = DateTime.now();
    });
  }

  void _analyzeRecording() {
    if (_recordedPath == null) return;
    final recordedAt = _recordedAt ?? DateTime.now();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          audioFile: File(_recordedPath!),
          store: widget.store,
          cloud: widget.cloud,
          sourceFilename: recordingDisplayName(recordedAt),
          retainAudio: true, // lives in app documents — worth persisting
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record Audio')),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            _TimerDisplay(elapsed: _elapsed, isRecording: _isRecording),
            const Spacer(),
            _MicButton(
              isRecording: _isRecording,
              onTap: _isRecording ? _stopRecording : _startRecording,
            ),
            const SizedBox(height: 12),
            Text(
              _isRecording
                  ? 'Tap to stop'
                  : _recordedPath != null
                      ? 'Recording saved'
                      : 'Tap to start recording',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const Spacer(),
            if (_recordedPath != null && !_isRecording) ...[
              FilledButton.icon(
                onPressed: _analyzeRecording,
                icon: const Icon(Icons.analytics),
                label: const Text('Analyze Recording'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _startRecording,
                icon: const Icon(Icons.refresh),
                label: const Text('Record Again'),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _TimerDisplay extends StatelessWidget {
  final Duration elapsed;
  final bool isRecording;

  const _TimerDisplay({required this.elapsed, required this.isRecording});

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _format(elapsed),
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w200,
                color: isRecording ? Colors.indigo : Colors.grey[400],
                letterSpacing: 4,
              ),
        ),
        if (isRecording) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'RECORDING',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.red,
                      letterSpacing: 2,
                    ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onTap;

  const _MicButton({required this.isRecording, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isRecording ? Colors.red : Colors.indigo,
            boxShadow: [
              BoxShadow(
                color: (isRecording ? Colors.red : Colors.indigo)
                    .withAlpha(77),
                blurRadius: isRecording ? 32 : 12,
                spreadRadius: isRecording ? 8 : 2,
              ),
            ],
          ),
          child: Icon(
            isRecording ? Icons.stop : Icons.mic,
            color: Colors.white,
            size: 44,
          ),
        ),
      ),
    );
  }
}
