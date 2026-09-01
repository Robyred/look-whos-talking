import 'package:flutter/material.dart';

import '../models/job_result.dart';
import '../utils/speaker_utils.dart';
import 'results_screen.dart';

class NameReviewScreen extends StatefulWidget {
  final String jobId;
  final DiarizationResult result;
  final Map<String, String> proposals;

  const NameReviewScreen({
    super.key,
    required this.jobId,
    required this.result,
    required this.proposals,
  });

  @override
  State<NameReviewScreen> createState() => _NameReviewScreenState();
}

class _NameReviewScreenState extends State<NameReviewScreen> {
  late final List<_SpeakerEntry> _entries;

  @override
  void initState() {
    super.initState();
    final ids = widget.result.speakers.map((s) => s.speakerId).toList()..sort();
    _entries = ids.map((id) {
      final sample = widget.result.transcript
          .where((seg) => seg.speakerId == id)
          .map((seg) => seg.text.trim())
          .firstWhere((t) => t.isNotEmpty, orElse: () => '');
      final excerpt = sample.length > 80 ? '${sample.substring(0, 80)}…' : sample;
      return _SpeakerEntry(
        speakerId: id,
        controller: TextEditingController(text: widget.proposals[id] ?? ''),
        sample: excerpt,
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.controller.dispose();
    }
    super.dispose();
  }

  void _apply() {
    final nameMap = <String, String>{};
    for (final entry in _entries) {
      final name = entry.controller.text.trim();
      if (name.isNotEmpty) nameMap[entry.speakerId] = name;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          jobId: widget.jobId,
          result: widget.result,
          nameMap: nameMap,
        ),
      ),
    );
  }

  void _skip() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          jobId: widget.jobId,
          result: widget.result,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Who's talking?"),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _skip,
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              widget.proposals.isNotEmpty
                  ? 'We found possible speaker names in the transcript. Edit any entry, then tap Apply — or Skip to keep numbered labels.'
                  : 'No names were detected automatically. You can type names for each speaker, or Skip to keep numbered labels.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _entries
                  .map((e) => _SpeakerNameCard(entry: e))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: FilledButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check),
              label: const Text('Apply names'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeakerEntry {
  final String speakerId;
  final TextEditingController controller;
  final String sample;

  _SpeakerEntry({
    required this.speakerId,
    required this.controller,
    required this.sample,
  });
}

class _SpeakerNameCard extends StatelessWidget {
  final _SpeakerEntry entry;

  const _SpeakerNameCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = colorForSpeaker(entry.speakerId);
    final idx = int.tryParse(entry.speakerId.split('_').last) ?? 0;
    final fallback = 'Speaker ${idx + 1}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withAlpha(26),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${idx + 1}',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(fallback,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            if (entry.sample.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '"${entry.sample}"',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: entry.controller,
              builder: (context, value, _) => TextField(
                controller: entry.controller,
                decoration: InputDecoration(
                  hintText: 'Name (leave blank to keep "$fallback")',
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: value.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => entry.controller.clear(),
                        )
                      : null,
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
