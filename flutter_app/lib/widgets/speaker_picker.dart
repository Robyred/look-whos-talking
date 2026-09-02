import 'package:flutter/material.dart';

class SpeakerPicker extends StatelessWidget {
  final int? selected;
  final ValueChanged<int?> onChanged;

  // null = "Don't know", 6 = "6+" (sends min_speakers=6, no max)
  static const _options = <(int?, String)>[
    (null, "Don't know"),
    (2, '2'),
    (3, '3'),
    (4, '4'),
    (5, '5'),
    (6, '6+'),
  ];

  const SpeakerPicker({super.key, required this.selected, required this.onChanged});

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
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
