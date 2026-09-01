import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/insights.dart';
import '../models/job_result.dart';
import '../services/api_service.dart';
import '../utils/speaker_utils.dart';

String _formatSec(double sec) {
  final m = (sec ~/ 60).toString().padLeft(2, '0');
  final s = (sec.toInt() % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

class ResultsScreen extends StatelessWidget {
  final String jobId;
  final DiarizationResult result;
  final Map<String, String> nameMap;

  const ResultsScreen({
    super.key,
    required this.jobId,
    required this.result,
    this.nameMap = const {},
  });

  @override
  Widget build(BuildContext context) {
    final hasTranscript = result.transcript.isNotEmpty;
    final tabCount = hasTranscript ? 4 : 1;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Results'),
          bottom: hasTranscript
              ? const TabBar(tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Transcript'),
                  Tab(text: 'Insights'),
                  Tab(text: 'Chat'),
                ])
              : null,
        ),
        body: hasTranscript
            ? TabBarView(children: [
                _OverviewTab(result: result, nameMap: nameMap),
                _TranscriptTab(
                    segments: result.transcript,
                    nameMap: nameMap,
                    filename: result.filename),
                _InsightsTab(jobId: jobId, result: result, nameMap: nameMap),
                _ChatTab(jobId: jobId, nameMap: nameMap),
              ])
            : _OverviewTab(result: result, nameMap: nameMap),
      ),
    );
  }
}

// ─── Overview tab ────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final DiarizationResult result;
  final Map<String, String> nameMap;

  const _OverviewTab({required this.result, required this.nameMap});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SummaryCard(result: result),
        const SizedBox(height: 16),
        Text('Speakers', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...result.speakers
            .map((s) => _SpeakerCard(speaker: s, nameMap: nameMap)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final DiarizationResult result;

  const _SummaryCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.filename,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatChip(
                  icon: Icons.people,
                  label:
                      '${result.speakerCount} speaker${result.speakerCount == 1 ? '' : 's'}',
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.timer,
                  label: _formatSec(result.totalDurationSec),
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.volume_up,
                  label:
                      '${(result.speechSec / result.totalDurationSec * 100).round()}% speech',
                ),
              ],
            ),
            if (result.overlapSec > 0.5) ...[
              const SizedBox(height: 8),
              _StatChip(
                icon: Icons.layers,
                label: '${_formatSec(result.overlapSec)} overlap',
                color: Colors.orange,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _StatChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.indigo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: c, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _SpeakerCard extends StatelessWidget {
  final SpeakerResult speaker;
  final Map<String, String> nameMap;

  const _SpeakerCard({required this.speaker, required this.nameMap});

  @override
  Widget build(BuildContext context) {
    final color = colorForSpeaker(speaker.speakerId);
    final label = speakerLabel(speaker.speakerId, nameMap);
    final initials = speakerInitials(speaker.speakerId, nameMap);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withAlpha(26),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(initials,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${speaker.percentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: speaker.percentage / 100,
                      backgroundColor: color.withAlpha(26),
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_formatSec(speaker.durationSec),
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Transcript tab ───────────────────────────────────────────────────────────

class _TranscriptTab extends StatelessWidget {
  final List<TranscriptSegment> segments;
  final Map<String, String> nameMap;
  final String filename;

  const _TranscriptTab({
    required this.segments,
    required this.nameMap,
    required this.filename,
  });

  String _asText() {
    final buf = StringBuffer('Transcript: $filename\n\n');
    String? lastSpeaker;
    for (final seg in segments) {
      final label = speakerLabel(seg.speakerId, nameMap);
      if (seg.speakerId != lastSpeaker) {
        buf.writeln('\n[$label — ${_formatSec(seg.start)}]');
        lastSpeaker = seg.speakerId;
      }
      buf.writeln(seg.text.trim());
    }
    return buf.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: segments.length,
            itemBuilder: (context, i) {
              final seg = segments[i];
              final color = colorForSpeaker(seg.speakerId);
              final label = speakerLabel(seg.speakerId, nameMap);
              final showHeader =
                  i == 0 || segments[i - 1].speakerId != seg.speakerId;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showHeader) ...[
                    if (i > 0) const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withAlpha(26),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(label,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Text(_formatSec(seg.start),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[400])),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(seg.text.trim(),
                        style:
                            const TextStyle(fontSize: 15, height: 1.5)),
                  ),
                ],
              );
            },
          ),
        ),
        _ShareBar(
          onShare: () => SharePlus.instance.share(
            ShareParams(text: _asText(), subject: 'Transcript — $filename'),
          ),
        ),
      ],
    );
  }
}

// ─── Insights tab ─────────────────────────────────────────────────────────────

enum _InsightsState { idle, loading, loaded, failed }

class _InsightsTab extends StatefulWidget {
  final String jobId;
  final DiarizationResult result;
  final Map<String, String> nameMap;

  const _InsightsTab({
    required this.jobId,
    required this.result,
    required this.nameMap,
  });

  @override
  State<_InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<_InsightsTab> {
  final _api = ApiService();
  _InsightsState _state = _InsightsState.idle;
  InsightsResult? _insights;
  String? _error;

  Future<void> _generate() async {
    setState(() => _state = _InsightsState.loading);
    try {
      final result =
          await _api.fetchInsights(widget.jobId, widget.nameMap);
      if (mounted) setState(() {
        _insights = result;
        _state = _InsightsState.loaded;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _state = _InsightsState.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _InsightsState.idle => _IdleView(onGenerate: _generate),
      _InsightsState.loading => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Asking DeepSeek…'),
            ],
          ),
        ),
      _InsightsState.loaded => _InsightsView(
          insights: _insights!,
          nameMap: widget.nameMap,
          filename: widget.result.filename,
        ),
      _InsightsState.failed => _FailedView(
          error: _error ?? 'Unknown error',
          onRetry: _generate,
        ),
    };
  }
}

class _IdleView extends StatelessWidget {
  final VoidCallback onGenerate;

  const _IdleView({required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 56, color: Colors.indigo[200]),
            const SizedBox(height: 20),
            Text('AI Insights',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Generate speaker names, action items, and meeting minutes using DeepSeek.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onGenerate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate insights'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _FailedView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(error,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsView extends StatelessWidget {
  final InsightsResult insights;
  final Map<String, String> nameMap;
  final String filename;

  const _InsightsView({
    required this.insights,
    required this.nameMap,
    required this.filename,
  });

  String _actionItemsText() {
    if (insights.actionItems.isEmpty) return 'No action items identified.';
    final buf = StringBuffer('Action items — $filename\n\n');
    for (final item in insights.actionItems) {
      buf.write('• ${item.task}');
      if (item.assignee != null) buf.write(' (${item.assignee})');
      if (item.deadline != null) buf.write(' — by ${item.deadline}');
      buf.writeln();
    }
    return buf.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Speaker names from Groq
        if (insights.speakerNames
            .any((s) => s.proposedName != null)) ...[
          _SectionHeader(
              icon: Icons.person, title: 'Speaker names identified by AI'),
          const SizedBox(height: 8),
          ...insights.speakerNames
              .where((s) => s.proposedName != null)
              .map((s) {
            final color = colorForSpeaker(s.speakerId);
            final fallback = speakerLabel(s.speakerId, nameMap);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: color.withAlpha(26),
                        shape: BoxShape.circle),
                    child: Center(
                        child: Text(
                      speakerInitials(s.speakerId, nameMap),
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    )),
                  ),
                  const SizedBox(width: 10),
                  Text(fallback,
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 14,
                      color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(s.proposedName!,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
          const SizedBox(height: 20),
        ],

        // Action items
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionHeader(
                icon: Icons.checklist, title: 'Action items'),
            IconButton(
              icon: const Icon(Icons.share, size: 20),
              tooltip: 'Share action items',
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                    text: _actionItemsText(),
                    subject: 'Action items — $filename'),
              ),
            ),
          ],
        ),
        if (insights.actionItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No action items identified.',
                style: TextStyle(color: Colors.grey[500])),
          )
        else
          ...insights.actionItems.map((item) => _ActionItemCard(item: item)),

        const SizedBox(height: 20),

        // Meeting minutes
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionHeader(
                icon: Icons.summarize, title: 'Meeting minutes'),
            IconButton(
              icon: const Icon(Icons.share, size: 20),
              tooltip: 'Share minutes',
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                    text: 'Meeting minutes — $filename\n\n${insights.minutes}',
                    subject: 'Minutes — $filename'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(insights.minutes,
            style: const TextStyle(fontSize: 15, height: 1.6)),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.indigo),
        const SizedBox(width: 6),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class _ActionItemCard extends StatelessWidget {
  final ActionItem item;

  const _ActionItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.radio_button_unchecked,
                size: 18, color: Colors.indigo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.task,
                      style:
                          const TextStyle(fontWeight: FontWeight.w500)),
                  if (item.assignee != null || item.deadline != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (item.assignee != null)
                          _Pill(
                              icon: Icons.person_outline,
                              label: item.assignee!),
                        if (item.assignee != null &&
                            item.deadline != null)
                          const SizedBox(width: 6),
                        if (item.deadline != null)
                          _Pill(
                              icon: Icons.schedule,
                              label: item.deadline!),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey[500]),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

// ─── Chat tab ─────────────────────────────────────────────────────────────────

class _Bubble {
  final String role; // "user" or "assistant"
  final String text;
  const _Bubble(this.role, this.text);
}

class _ChatTab extends StatefulWidget {
  final String jobId;
  final Map<String, String> nameMap;

  const _ChatTab({required this.jobId, required this.nameMap});

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final _api = ApiService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Bubble> _bubbles = [];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _bubbles.add(_Bubble('user', text));
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();

    final history = _bubbles
        .map((b) => {'role': b.role, 'content': b.text})
        .toList();

    try {
      final answer = await _api.askQuestion(widget.jobId, history, widget.nameMap);
      if (mounted) {
        setState(() => _bubbles.add(_Bubble('assistant', answer)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _bubbles.add(_Bubble('assistant', 'Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _bubbles.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 56, color: Colors.indigo[200]),
                        const SizedBox(height: 16),
                        Text('Ask about the conversation',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          'e.g. "What did Speaker 1 say about the budget?"\nor "Were any deadlines mentioned?"',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _bubbles.length + (_sending ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (_sending && i == _bubbles.length) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final bubble = _bubbles[i];
                    final isUser = bubble.role == 'user';
                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        decoration: BoxDecoration(
                          color: isUser
                              ? Colors.indigo
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isUser ? 16 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 16),
                          ),
                        ),
                        child: Text(
                          bubble.text,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: isUser ? Colors.white : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(
              12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Ask a question…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Shared share bar (used by Transcript tab) ────────────────────────────────

class _ShareBar extends StatelessWidget {
  final VoidCallback onShare;

  const _ShareBar({required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share transcript'),
          ),
        ],
      ),
    );
  }
}
