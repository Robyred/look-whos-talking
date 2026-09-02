import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'processing_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _selectedFile;
  String? _selectedName;

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'ogg', 'flac', 'aac'],
    );

    if (picked == null || picked.path == null) return;

    setState(() {
      _selectedFile = File(picked.path!);
      _selectedName = picked.name;
    });
  }

  void _analyze() {
    if (_selectedFile == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(audioFile: _selectedFile!),
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
