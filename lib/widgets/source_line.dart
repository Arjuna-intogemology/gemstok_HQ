import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Footer under every number: where it came from and when it was loaded.
/// e.g. "Gemstok DB · login_history · loaded 10:42"
class SourceLine extends StatelessWidget {
  const SourceLine({super.key, required this.source, required this.loadedAt, this.guessed = false});

  final String source;
  final DateTime loadedAt;
  final bool guessed; // true = estimated, not exact (shown as "guessed")

  @override
  Widget build(BuildContext context) {
    final t = TimeOfDay.fromDateTime(loadedAt);
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Text(
      '$source · loaded $time${guessed ? ' · guessed' : ''}',
      style: jost(11, color: HqColors.muted),
    );
  }
}

/// A big number with a label and its source line. Charts get added under it later.
class NumberCard extends StatelessWidget {
  const NumberCard({
    super.key,
    required this.label,
    required this.value,
    required this.source,
    required this.loadedAt,
    this.sub,
    this.guessed = false,
  });

  final String label;
  final String value;
  final String? sub; // e.g. "7 days: 41"
  final String source;
  final DateTime loadedAt;
  final bool guessed;

  @override
  Widget build(BuildContext context) => Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HqColors.surface,
          border: Border.all(color: HqColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: jost(13, color: HqColors.muted, weight: 500)),
            const SizedBox(height: 6),
            Text(value, style: jost(32, weight: 600)),
            if (sub != null) Text(sub!, style: jost(13, color: HqColors.muted)),
            const SizedBox(height: 10),
            SourceLine(source: source, loadedAt: loadedAt, guessed: guessed),
          ],
        ),
      );
}
