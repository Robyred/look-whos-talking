import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/cloud_storage_provider.dart';
import '../theme.dart';
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

class _MicButton extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onTap;

  const _MicButton({required this.isRecording, required this.onTap});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  static const _size = 88.0;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isRecording) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isRecording && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: _size * 1.3,
          height: _size * 1.3,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing ring while recording (DESIGN_PLAN_v1 §5.2).
              if (widget.isRecording)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final scale = 1.0 + 0.3 * _pulse.value;
                    return Container(
                      width: _size * scale,
                      height: _size * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kPrimaryCoral.withValues(alpha: 0.15),
                      ),
                    );
                  },
                ),
              Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kPrimaryCoral,
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryCoral.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  widget.isRecording ? Icons.stop : Icons.mic,
                  color: kBackground,
                  size: 40,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
