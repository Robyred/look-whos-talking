import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/cloud_storage_provider.dart';
import '../services/conversation_store.dart';
import 'processing_screen.dart';

class UploadScreen extends StatefulWidget {
  final ConversationStore store;
  final CloudStorageProvider cloud;

  const UploadScreen({super.key, required this.store, required this.cloud});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _selectedFile;
  String? _selectedName;
  AudioPlayer? _previewPlayer;
  bool _previewReady = false;

  @override
  void dispose() {
    _previewPlayer?.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'ogg', 'flac', 'aac'],
    );

    if (picked == null || picked.path == null) return;

    await _previewPlayer?.dispose();
    _previewPlayer = null;
    if (mounted) {
      setState(() {
        _selectedFile = File(picked.path!);
        _selectedName = picked.name;
        _previewReady = false;
      });
    }

    final player = AudioPlayer();
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await player.setFilePath(picked.path!);
      if (mounted) {
        setState(() {
          _previewPlayer = player;
          _previewReady = true;
        });
      } else {
        player.dispose();
      }
    } catch (_) {
      player.dispose();
    }
  }

  void _analyze() {
    if (_selectedFile == null) return;
    _previewPlayer?.pause();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          audioFile: _selectedFile!,
          store: widget.store,
          cloud: widget.cloud,
          sourceFilename: _selectedName,
          // The picked file lives in the picker's cache, so its path is not
          // persisted for History playback.
          retainAudio: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload File')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Icon(Icons.audio_file, size: 72, color: Colors.deepOrange),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _pickFile,
                  child: DottedBorder(
                    selected: _selectedName != null,
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          Icon(
                            _selectedName != null
                                ? Icons.check_circle_outline
                                : Icons.cloud_upload_outlined,
                            size: 48,
                            color: _selectedName != null
                                ? Colors.green
                                : Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedName ?? 'Tap to select audio file',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: _selectedName != null
                                      ? Colors.black87
                                      : Colors.grey[500],
                                ),
                          ),
                          if (_selectedName == null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'WAV • MP3 • M4A • FLAC • OGG',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey[400]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_previewReady && _previewPlayer != null) ...[
                  const SizedBox(height: 16),
                  _AudioPreview(player: _previewPlayer!),
                ],
                const Spacer(),
                if (_selectedName != null) ...[
                  FilledButton.icon(
                    onPressed: _analyze,
                    icon: const Icon(Icons.analytics),
                    label: const Text('Analyze File'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Choose Different File'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Browse Files'),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioPreview extends StatelessWidget {
  final AudioPlayer player;

  const _AudioPreview({required this.player});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, durSnap) {
            final total = durSnap.data ?? Duration.zero;
            final totalMs = total.inMilliseconds.toDouble();
            return StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, posSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final posMs = pos.inMilliseconds.toDouble().clamp(0.0, totalMs);
                return Row(
                  children: [
                    StreamBuilder<PlayerState>(
                      stream: player.playerStateStream,
                      builder: (context, stateSnap) {
                        final playing = stateSnap.data?.playing ?? false;
                        final completed = stateSnap.data?.processingState ==
                            ProcessingState.completed;
                        return IconButton(
                          icon: Icon(completed
                              ? Icons.replay
                              : playing
                                  ? Icons.pause
                                  : Icons.play_arrow),
                          onPressed: () async {
                            if (completed) {
                              await player.seek(Duration.zero);
                              await player.play();
                            } else if (playing) {
                              await player.pause();
                            } else {
                              await player.play();
                            }
                          },
                        );
                      },
                    ),
                    Text(_fmt(pos),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                    Expanded(
                      child: Slider(
                        value: totalMs > 0 ? posMs : 0,
                        max: totalMs > 0 ? totalMs : 1,
                        onChanged: totalMs > 0
                            ? (v) => player
                                .seek(Duration(milliseconds: v.toInt()))
                            : null,
                      ),
                    ),
                    Text(_fmt(total),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// Simple dashed-border container — no extra package needed.
class DottedBorder extends StatelessWidget {
  final bool selected;
  final Widget child;

  const DottedBorder({super.key, required this.selected, required this.child});

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.green : Colors.grey[300]!;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(16),
        color: selected ? Colors.green.withAlpha(13) : Colors.grey[50],
      ),
      child: child,
    );
  }
}
