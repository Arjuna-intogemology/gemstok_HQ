import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import 'format.dart';

/// Every data screen: title, Refresh, "loaded 16:42 · refreshes every 5 min", errors, then the body.
/// The body is built again whenever new data arrives.
class ScreenFrame extends StatefulWidget {
  const ScreenFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.data,
    required this.queries,
    required this.body,
  });

  final String title;
  final String subtitle;
  final HqData data;
  final List<HqQuery> queries;
  final List<Widget> Function() body;

  @override
  State<ScreenFrame> createState() => _ScreenFrameState();
}

class _ScreenFrameState extends State<ScreenFrame> {
  @override
  void initState() {
    super.initState();
    widget.data.use(widget.queries);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.data,
      builder: (context, _) {
        final d = widget.data;
        final loading = widget.queries.any(d.isLoading);
        final times = widget.queries.map(d.loadedAt).whereType<DateTime>().toList()..sort();
        final errors = <String>{
          for (final q in widget.queries)
            if (d.error(q) != null && !d.isNotSet(q) && !q.optional) '${q.project.name}: ${d.error(q)}',
        };
        return ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.title, style: jost(26, weight: 600))),
                if (times.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text('loaded ${fmtTime(times.first)} · refreshes every 5 min',
                        style: jost(12, color: HqColors.muted)),
                  ),
                OutlinedButton(
                  onPressed: loading ? null : () => d.refresh(widget.queries),
                  child: Text(loading ? 'Loading…' : 'Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(widget.subtitle, style: jost(14, color: HqColors.muted)),
            const SizedBox(height: 20),
            for (final e in errors) NoteBox(color: HqColors.bad, text: 'Couldn\'t load — $e\nSettings → Check.'),
            ...widget.body(),
          ],
        );
      },
    );
  }
}

class NoteBox extends StatelessWidget {
  const NoteBox({super.key, required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: jost(13)),
      );
}

/// Section heading inside a screen.
class Heading extends StatelessWidget {
  const Heading(this.text, {super.key, this.note});
  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: jost(17, weight: 600)),
            if (note != null) Text(note!, style: jost(12, color: HqColors.muted)),
          ],
        ),
      );
}

/// Grey card for numbers that need a database HQ isn't connected to yet.
class NotConnectedCard extends StatelessWidget {
  const NotConnectedCard({super.key, required this.label, required this.project});
  final String label;
  final String project;

  @override
  Widget build(BuildContext context) => Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: HqColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: jost(13, color: HqColors.muted, weight: 500)),
            const SizedBox(height: 6),
            Text('–', style: jost(32, weight: 600, color: HqColors.muted)),
            Text('$project not connected yet', style: jost(13, color: HqColors.muted)),
          ],
        ),
      );
}

/// A row of small buttons where one is chosen (e.g. 7 / 30 / 90 days).
class Choice<T> extends StatelessWidget {
  const Choice({super.key, required this.options, required this.value, required this.onChanged});
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        children: [
          for (final e in options.entries)
            e.key == value
                ? FilledButton(onPressed: () {}, child: Text(e.value))
                : OutlinedButton(onPressed: () => onChanged(e.key), child: Text(e.value)),
        ],
      );
}

/// For screens that aren't a ScreenFrame: asks HqData for [queries] once, when the screen opens.
class UseQueries extends StatefulWidget {
  const UseQueries({super.key, required this.data, required this.queries, required this.child});
  final HqData data;
  final List<HqQuery> queries;
  final Widget child;

  @override
  State<UseQueries> createState() => _UseQueriesState();
}

class _UseQueriesState extends State<UseQueries> {
  @override
  void initState() {
    super.initState();
    widget.data.use(widget.queries);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
