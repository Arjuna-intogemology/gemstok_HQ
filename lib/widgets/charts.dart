import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Small bar chart: one bar per item, hover shows the exact value.
/// Labels are shown under some bars only, so they don't crowd.
class Bars extends StatelessWidget {
  const Bars({super.key, required this.items, this.height = 140});

  final List<(String label, double value)> items;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Text('No data yet.', style: jost(13, color: HqColors.muted));
    final max = items.map((e) => e.$2).fold<double>(0, (a, b) => b > a ? b : a);
    final every = (items.length / 8).ceil().clamp(1, 1000);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final e in items)
                  Expanded(
                    child: Tooltip(
                      message: '${e.$1}: ${e.$2 == e.$2.roundToDouble() ? e.$2.toInt() : e.$2.toStringAsFixed(1)}',
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        height: max == 0 ? 1 : (e.$2 / max * height).clamp(1, height),
                        decoration: BoxDecoration(
                          color: e.$2 == 0 ? HqColors.line : HqColors.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Text(
                    i % every == 0 ? items[i].$1 : '',
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: jost(10, color: HqColors.muted),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Simple table: header row + rows of text. First column left, the rest right-aligned.
class SimpleTable extends StatelessWidget {
  const SimpleTable({super.key, required this.header, required this.rows, this.firstColumnWidth = 2});

  final List<String> header;
  final List<List<String>> rows;
  final double firstColumnWidth;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Text('Nothing yet.', style: jost(13, color: HqColors.muted));
    Widget cell(String t, int i, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            t,
            textAlign: i == 0 ? TextAlign.left : TextAlign.right,
            style: head ? jost(12, weight: 600, color: HqColors.muted) : jost(14),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Table(
        columnWidths: {0: FlexColumnWidth(firstColumnWidth)},
        defaultColumnWidth: const FlexColumnWidth(1),
        border: const TableBorder(horizontalInside: BorderSide(color: HqColors.line)),
        children: [
          TableRow(children: [for (var i = 0; i < header.length; i++) cell(header[i], i, head: true)]),
          for (final r in rows) TableRow(children: [for (var i = 0; i < r.length; i++) cell(r[i], i)]),
        ],
      ),
    );
  }
}
