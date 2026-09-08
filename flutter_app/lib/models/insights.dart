class SpeakerNameProposal {
  final String speakerId;
  final String? proposedName;

  const SpeakerNameProposal({required this.speakerId, this.proposedName});

  factory SpeakerNameProposal.fromJson(Map<String, dynamic> json) =>
      SpeakerNameProposal(
        speakerId: json['speaker_id'] as String,
        proposedName: json['proposed_name'] as String?,
      );
}

class ActionItem {
  final String task;
  final String? assignee;
  final String? deadline;

  const ActionItem({required this.task, this.assignee, this.deadline});

  factory ActionItem.fromJson(Map<String, dynamic> json) => ActionItem(
        task: json['task'] as String,
        assignee: json['assignee'] as String?,
        deadline: json['deadline'] as String?,
      );
}

class InsightsResult {
  final List<SpeakerNameProposal> speakerNames;
  final List<ActionItem> actionItems;
  final String minutes;

  const InsightsResult({
    required this.speakerNames,
    required this.actionItems,
    required this.minutes,
  });

  factory InsightsResult.fromJson(Map<String, dynamic> json) => InsightsResult(
        speakerNames: (json['speaker_names'] as List)
            .map((e) => SpeakerNameProposal.fromJson(e as Map<String, dynamic>))
            .toList(),
        actionItems: (json['action_items'] as List)
            .map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        minutes: json['minutes'] as String? ?? '',
      );
}
