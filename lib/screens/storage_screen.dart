import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../widgets/screen_frame.dart';

/// Storage: database size per Supabase project against the free plan's 500 MB,
/// and each database's 5 biggest tables. (Egress, function calls and R2 come with the
/// Supabase / Cloudflare tokens later.)
class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key, required this.data});
  final HqData data;

  static const freeLimit = 500 * 1024 * 1024; // Supabase free plan: 500 MB database per project

  static String mb(num bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Storage',
      subtitle: 'Database size per project. Supabase free plan: 500 MB per database — above that the project goes read-only.',
      data: data,
      queries: Q.dbSizes,
      body: () => [
        for (final q in Q.dbSizes) _row(q),
        const SizedBox(height: 12),
        const NoteBox(
          color: HqColors.warn,
          text: 'Photos are on Cloudflare R2, not in these databases. Egress, function calls and R2 usage come '
              'next (they need the Supabase / Cloudflare tokens).',
        ),
      ],
    );
  }

  Widget _row(HqQuery q) {
    final r = data.rows(q)?.firstOrNull;
    final name = q.project.name;
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text('$name — ${data.isNotSet(q) ? 'not connected yet' : 'loading…'}',
            style: jost(14, color: HqColors.muted)),
      );
    }
    final bytes = (r['bytes'] as int?) ?? 0;
    final share = (bytes / freeLimit).clamp(0.0, 1.0);
    final colour = share > 0.8 ? HqColors.bad : (share > 0.5 ? HqColors.warn : HqColors.good);
    final top = <Map<String, dynamic>>[
      for (final t in (jsonDecode('${r['top'] ?? '[]'}') as List? ?? const [])) Map<String, dynamic>.from(t as Map),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: jost(15, weight: 600))),
          Text('${mb(bytes)} of 500 MB · ${(share * 100).toStringAsFixed(1)}%',
              style: jost(13, weight: 500, color: colour)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 6,
            color: colour,
            backgroundColor: HqColors.line,
          ),
        ),
        const SizedBox(height: 8),
        Text('Biggest tables: ${top.map((t) => '${t['name']} ${mb(t['bytes'] as num)}').join(' · ')}',
            style: jost(12, color: HqColors.muted)),
      ]),
    );
  }
}
