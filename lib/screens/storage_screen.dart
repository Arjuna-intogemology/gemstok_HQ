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
///   · Databases — one pie PER database (free plan: 500 MB each): its 5 biggest tables + everything else.
///     Click a slice or a name → it grows.
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
  int? _bucket; // chosen R2 slice

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Storage',
      subtitle: 'Databases (Supabase, 500 MB each on the free plan) and photo storage (Cloudflare R2, 10 GB free). '
          'Each database has its own pie of what fills it — click a slice or a name to look closer.',
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
  // Overview: one SMALL pie per database (used vs its 500 MB). Click one → its detail pie below.

  String? _openDb; // query key of the database whose detail is open
  int? _pickedSlice; // chosen slice in the detail pie

  Widget _databases() {
    final d = widget.data;
    final open = Q.dbSizes.where((q) => q.key == _openDb).firstOrNull;
    final openRow = open == null ? null : d.rows(open)?.firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 14, runSpacing: 14, children: [
        for (final q in Q.dbSizes) _smallCard(q, d.rows(q)?.firstOrNull),
      ]),
      if (open != null && openRow != null) _dbDetail(open, openRow),
    ]);
  }

  /// Overview tile: a small pie of used vs free (500 MB), the name and the size.
  Widget _smallCard(HqQuery q, Map<String, dynamic>? r) {
    final selected = q.key == _openDb;
    final bytes = ((r?['bytes'] as num?) ?? 0).toDouble();
    final share = bytes / StorageScreen.dbFree;
    final level = _level(share).$2;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: r == null
          ? null
          : () => setState(() {
                _openDb = selected ? null : q.key;
                _pickedSlice = null;
              }),
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HqColors.surface,
          border: Border.all(color: selected ? HqColors.accent : HqColors.line, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          if (r == null)
            SizedBox(
              height: 96,
              child: Center(
                child: Text(widget.data.isNotSet(q) ? 'not connected' : 'loading…',
                    style: jost(12, color: HqColors.muted)),
              ),
            )
          else
            IgnorePointer( // the whole tile is the button
              child: PieChart(
                size: 96,
                slices: [
                  PieSlice('used', bytes, level),
                  PieSlice('free', (StorageScreen.dbFree - bytes).clamp(0, StorageScreen.dbFree).toDouble(), HqColors.line),
                ],
                centerText: '${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}%',
              ),
            ),
          const SizedBox(height: 8),
          Text(q.project.name, style: jost(14, weight: 600), textAlign: TextAlign.center),
          Text(r == null ? '–' : '${StorageScreen.size(bytes)} of 500 MB',
              style: jost(12, color: HqColors.muted), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  /// Detail of one database: what fills it — its 5 biggest tables, the rest of your tables,
  /// and what Supabase itself keeps there (sign-in data, storage records, indexes, system tables).
  Widget _dbDetail(HqQuery q, Map<String, dynamic> r) {
    final bytes = ((r['bytes'] as num?) ?? 0).toDouble();
    final appBytes = ((r['app_bytes'] as num?) ?? 0).toDouble();
    final share = bytes / StorageScreen.dbFree;
    final level = _level(share).$2;
    final top = <Map<String, dynamic>>[
      for (final t in (jsonDecode('${r['top'] ?? '[]'}') as List? ?? const [])) Map<String, dynamic>.from(t as Map),
    ];
    final topSum = top.fold(0.0, (a, t) => a + (t['bytes'] as num).toDouble());
    final otherApp = (appBytes - topSum).clamp(0.0, double.infinity);
    final system = (bytes - (appBytes > 0 ? appBytes : topSum)).clamp(0.0, double.infinity);
    final slices = [
      for (var i = 0; i < top.length; i++)
        PieSlice('${top[i]['name']}', (top[i]['bytes'] as num).toDouble(), pieColors[i % pieColors.length]),
      if (otherApp > 0) PieSlice('your other tables', otherApp, const Color(0xFF8C9AA6)),
      if (system > 0) PieSlice('Supabase itself (sign-in, storage, system)', system, const Color(0xFFD3D6D9)),
    ];
    final at = widget.data.loadedAt(q);

    return _card(HqColors.accent, [
      Row(children: [
        Expanded(child: Text(q.project.name, style: jost(18, weight: 600))),
        Text('${StorageScreen.size(bytes)} of 500 MB · ${(share * 100).toStringAsFixed(1)}%',
            style: jost(14, weight: 600, color: level)),
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => setState(() => _openDb = null),
        ),
      ]),
      const SizedBox(height: 6),
      _bar(share.clamp(0.0, 1.0), level),
      const SizedBox(height: 16),
      Wrap(spacing: 28, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
        PieChart(
          slices: slices,
          size: 220,
          selected: _pickedSlice,
          onSelect: (i) => setState(() => _pickedSlice = i),
          centerText: _pickedSlice == null ? StorageScreen.size(bytes) : StorageScreen.size(slices[_pickedSlice!].value),
        ),
        SizedBox(
          width: 440,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < slices.length; i++)
              _legendRow(
                color: slices[i].color,
                name: slices[i].label,
                right: (
                  '${StorageScreen.size(slices[i].value)} · ${(slices[i].value / (bytes == 0 ? 1 : bytes) * 100).toStringAsFixed(0)}%',
                  HqColors.ink
                ),
                selected: _pickedSlice == i,
                onTap: () => setState(() => _pickedSlice = _pickedSlice == i ? null : i),
              ),
          ]),
        ),
      ]),
      const SizedBox(height: 8),
      Text('"Supabase itself" is what every project carries: sign-in accounts, file records, indexes and system '
          'tables. A new, empty project already uses about 10 MB of it.',
          style: jost(12, color: HqColors.muted)),
      if (at != null) ...[const SizedBox(height: 6), SourceLine(source: q.source, loadedAt: at)],
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
