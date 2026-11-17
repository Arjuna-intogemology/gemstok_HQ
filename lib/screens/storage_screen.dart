import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../services/services_data.dart';
import '../widgets/pie_chart.dart';
import '../widgets/screen_frame.dart';
import '../widgets/source_line.dart';

/// Storage: two pies.
///   · Databases — size of each Supabase database (free plan: 500 MB EACH). Click a slice or a name → it grows,
///     and its 5 biggest tables show.
///   · R2 — photo storage per Cloudflare bucket (free: 10 GB for the whole account).
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key, required this.data, required this.services});
  final HqData data;
  final ServicesData services;

  static const dbFree = 500 * 1024 * 1024; // Supabase free: 500 MB per database
  static const r2Free = 10 * 1024 * 1024 * 1024; // R2 free: 10 GB per account

  static String size(num bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  int? _db; // chosen database slice
  int? _bucket; // chosen R2 slice

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Storage',
      subtitle: 'Databases (Supabase, 500 MB each on the free plan) and photo storage (Cloudflare R2, 10 GB free). '
          'Click a slice or a name to look closer.',
      data: widget.data,
      queries: Q.dbSizes,
      body: () => [
        const Heading('Databases'),
        _databases(),
        const Heading('Photos — Cloudflare R2'),
        ListenableBuilder(listenable: widget.services, builder: (context, _) => _r2()),
      ],
    );
  }

  // ------------------------------------------------------------------ databases

  Widget _databases() {
    final d = widget.data;
    final rows = <(HqQuery, Map<String, dynamic>?)>[for (final q in Q.dbSizes) (q, d.rows(q)?.firstOrNull)];
    final loaded = [for (final r in rows) if (r.$2 != null) r];
    final slices = [
      for (var i = 0; i < loaded.length; i++)
        PieSlice(loaded[i].$1.project.name, ((loaded[i].$2!['bytes'] as int?) ?? 0).toDouble(), pieColors[i % pieColors.length]),
    ];
    final total = slices.fold(0.0, (a, s) => a + s.value);
    final chosen = (_db != null && _db! < loaded.length) ? loaded[_db!] : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 28, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
        PieChart(
          slices: slices,
          selected: _db,
          onSelect: (i) => setState(() => _db = i),
          centerText: total == 0 ? null : StorageScreen.size(total),
        ),
        SizedBox(
          width: 420,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < loaded.length; i++)
              _legendRow(
                color: slices[i].color,
                name: slices[i].label,
                right: () {
                  final b = slices[i].value;
                  final share = b / StorageScreen.dbFree;
                  return ('${StorageScreen.size(b)} · ${(share * 100).toStringAsFixed(1)}% of 500 MB', _level(share).$2);
                }(),
                selected: _db == i,
                onTap: () => setState(() => _db = _db == i ? null : i),
              ),
            for (final r in rows)
              if (r.$2 == null)
                Padding(
                  padding: const EdgeInsets.only(left: 22, top: 6),
                  child: Text('${r.$1.project.name} — ${d.isNotSet(r.$1) ? 'not connected yet' : 'loading…'}',
                      style: jost(13, color: HqColors.muted)),
                ),
          ]),
        ),
      ]),
      if (chosen != null) _dbDetail(chosen.$1, chosen.$2!, slices[_db!].color),
    ]);
  }

  Widget _dbDetail(HqQuery q, Map<String, dynamic> r, Color color) {
    final bytes = (r['bytes'] as int?) ?? 0;
    final share = (bytes / StorageScreen.dbFree).clamp(0.0, 1.0);
    final top = <Map<String, dynamic>>[
      for (final t in (jsonDecode('${r['top'] ?? '[]'}') as List? ?? const [])) Map<String, dynamic>.from(t as Map),
    ];
    final at = widget.data.loadedAt(q);
    return _card(color, [
      Row(children: [
        Expanded(child: Text(q.project.name, style: jost(17, weight: 600))),
        Text('${StorageScreen.size(bytes)} of 500 MB', style: jost(14, weight: 600, color: _level(share).$2)),
      ]),
      const SizedBox(height: 8),
      _bar(share, _level(share).$2),
      const SizedBox(height: 12),
      Text('Biggest tables', style: jost(12, weight: 600, color: HqColors.muted)),
      const SizedBox(height: 4),
      for (final t in top)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text('${t['name']}', style: jost(14))),
            Text(StorageScreen.size(t['bytes'] as num), style: jost(14, weight: 500)),
          ]),
        ),
      if (at != null) ...[const SizedBox(height: 8), SourceLine(source: q.source, loadedAt: at)],
    ]);
  }

  // ------------------------------------------------------------------ R2

  Widget _r2() {
    final s = widget.services;
    final cf = s.state['cloudflare']!;
    if (!cf.keysSet) {
      return const NoteBox(color: HqColors.line, text: 'Add the Cloudflare token in Settings → Other services to see R2 storage.');
    }
    if (s.r2Error != null) {
      return NoteBox(
          color: HqColors.bad,
          text: 'R2: ${s.r2Error}\nThe Cloudflare token needs "Account Analytics: Read" (Account policy). '
              'Cloudflare → My Profile → API Tokens → Gemstok HQ → Edit.');
    }
    if (s.r2LoadedAt == null) return Text('Loading R2…', style: jost(13, color: HqColors.muted));
    final buckets = s.r2Buckets;
    if (buckets.isEmpty) return Text('No R2 buckets with data found.', style: jost(13, color: HqColors.muted));
    final slices = [
      for (var i = 0; i < buckets.length; i++)
        PieSlice('${buckets[i]['bucket']}', (buckets[i]['bytes'] as num).toDouble(), pieColors[(i + 3) % pieColors.length]),
    ];
    final total = slices.fold(0.0, (a, x) => a + x.value);
    final share = total / StorageScreen.r2Free;
    final chosen = (_bucket != null && _bucket! < buckets.length) ? buckets[_bucket!] : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${StorageScreen.size(total)} of 10 GB free (whole account) · ${(share * 100).toStringAsFixed(1)}%',
          style: jost(14, weight: 600, color: _level(share).$2)),
      const SizedBox(height: 6),
      SizedBox(width: 420, child: _bar(share.clamp(0.0, 1.0), _level(share).$2)),
      const SizedBox(height: 16),
      Wrap(spacing: 28, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
        PieChart(
          slices: slices,
          selected: _bucket,
          onSelect: (i) => setState(() => _bucket = i),
          centerText: StorageScreen.size(total),
        ),
        SizedBox(
          width: 420,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < buckets.length; i++)
              _legendRow(
                color: slices[i].color,
                name: slices[i].label,
                right: ('${StorageScreen.size(slices[i].value)} · ${_count(buckets[i]['objects'] as num)} files', HqColors.ink),
                selected: _bucket == i,
                onTap: () => setState(() => _bucket = _bucket == i ? null : i),
              ),
          ]),
        ),
      ]),
      if (chosen != null)
        _card(slices[_bucket!].color, [
          Text('${chosen['bucket']}', style: jost(17, weight: 600)),
          const SizedBox(height: 6),
          Text('${StorageScreen.size(chosen['bytes'] as num)} · ${_count(chosen['objects'] as num)} files · '
              '${(((chosen['bytes'] as num) / (total == 0 ? 1 : total)) * 100).toStringAsFixed(0)}% of your R2',
              style: jost(14)),
          const SizedBox(height: 8),
          SourceLine(source: 'Cloudflare · R2 storage analytics', loadedAt: s.r2LoadedAt!),
        ]),
      const SizedBox(height: 8),
      Text('Cloudflare updates R2 sizes a few times a day; HQ reloads every hour.', style: jost(12, color: HqColors.muted)),
    ]);
  }

  // ------------------------------------------------------------------ pieces

  static String _count(num n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(1)}M'
      : n >= 1000
          ? '${(n / 1000).toStringAsFixed(1)}k'
          : '${n.toInt()}';

  static (String, Color) _level(double share) =>
      share > 0.8 ? ('high', HqColors.bad) : share > 0.5 ? ('watch', HqColors.warn) : ('ok', HqColors.good);

  Widget _legendRow({
    required Color color,
    required String name,
    required (String, Color) right,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? HqColors.surface : null,
            border: selected ? Border.all(color: color) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(child: Text(name, style: jost(14, weight: selected ? 600 : 500), overflow: TextOverflow.ellipsis)),
            Text(right.$1, style: jost(13, weight: 500, color: right.$2)),
          ]),
        ),
      );

  Widget _bar(double share, Color color) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: share, minHeight: 6, color: color, backgroundColor: HqColors.line),
      );

  Widget _card(Color accent, List<Widget> children) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HqColors.surface,
          border: Border.all(color: accent, width: 1.5), // one colour: rounded corners need a uniform border
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}
