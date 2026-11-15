import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import '../widgets/source_line.dart';
import 'services_data.dart';

/// Shows a service's state (no key / loading / error). null = loaded fine.
Widget? _state(ServicesData s, String id) {
  final st = s.state[id]!;
  final name = ServicesData.info(id).name;
  if (!st.keysSet) {
    return NoteBox(
        color: HqColors.line,
        text: id == 'admob'
            ? '$name: add its keys in Settings → Other services, then press "Sign in with Google" there.'
            : '$name: add its key in Settings → Other services.');
  }
  if (st.error != null) return NoteBox(color: HqColors.bad, text: '$name: ${st.error}');
  if (st.loadedAt == null) return Text('$name: loading…', style: jost(13, color: HqColors.muted));
  return null;
}

DateTime? _ymd(String s) {
  final t = s.replaceAll('-', '').trim();
  if (t.length != 8) return null;
  final y = int.tryParse(t.substring(0, 4)), m = int.tryParse(t.substring(4, 6)), d = int.tryParse(t.substring(6));
  return (y == null || m == null || d == null) ? null : DateTime.utc(y, m, d);
}

Map<DateTime, double> _emptyDays(DateTime from) => {
      for (var d = from; !d.isAfter(todayDay()); d = d.add(const Duration(days: 1))) d: 0,
    };

String _stars(Object? r) {
  final n = (r is int) ? r : int.tryParse('$r') ?? 0;
  return '${'★' * n.clamp(0, 5)}${'☆' * (5 - n.clamp(0, 5))}';
}

/// Money (downloads: false): App Store proceeds + in-app purchases, AdMob.
/// Downloads (downloads: true): App Store downloads / updates / reviews, Google Play installs / reviews.
class StoresAndAds extends StatelessWidget {
  const StoresAndAds({super.key, required this.services, required this.days, required this.downloads});
  final ServicesData services;
  final int days;
  final bool downloads;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: services,
        builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ..._appStore(),
          if (downloads) ..._googlePlay() else ..._admob(),
        ]),
      );

  DateTime get _from => todayDay().subtract(Duration(days: days - 1));

  List<Widget> _appStore() {
    final s = services;
    final out = <Widget>[
      Heading(downloads ? 'App Store (iPhone)' : 'App Store money',
          note: days > 30 ? 'Apple daily reports: HQ loads the last 30 days.' : 'Apple publishes each day about a day later.'),
    ];
    final st = _state(s, 'appstore');
    if (st != null) return out..add(st);
    final perDay = _emptyDays(_from);
    final byTitle = <String, List<num>>{}; // downloads, redownloads, updates, iap
    final proceeds = <String, double>{};
    for (final e in s.asSales.entries) {
      if (e.key.isBefore(_from)) continue;
      for (final t in e.value.entries) {
        final v = t.value;
        final b = byTitle.putIfAbsent(t.key, () => [0, 0, 0, 0]);
        b[0] += v['downloads'] as int;
        b[1] += v['redownloads'] as int;
        b[2] += v['updates'] as int;
        b[3] += v['iap'] as int;
        perDay[e.key] = (perDay[e.key] ?? 0) + (v['downloads'] as int);
        (v['proceeds'] as Map<String, double>).forEach((c, a) => proceeds[c] = (proceeds[c] ?? 0) + a);
      }
    }
    num sum(int i) => byTitle.values.fold<num>(0, (a, b) => a + b[i]);
    final at = s.state['appstore']!.loadedAt!;
    const src = 'App Store Connect · sales reports';
    if (!downloads) {
      return out
        ..add(Wrap(spacing: 14, runSpacing: 14, children: [
          NumberCard(
              label: 'Proceeds (after Apple\'s cut)',
              value: proceeds.isEmpty
                  ? '0'
                  : proceeds.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(' · '),
              source: src,
              loadedAt: at),
          NumberCard(label: 'In-app purchases', value: fmtNum(sum(3)), source: src, loadedAt: at),
        ]));
    }
    out.addAll([
      Wrap(spacing: 14, runSpacing: 14, children: [
        NumberCard(label: 'New downloads', value: fmtNum(sum(0)), sub: 're-downloads: ${fmtNum(sum(1))}', source: src, loadedAt: at),
        NumberCard(label: 'Updates', value: fmtNum(sum(2)), source: src, loadedAt: at),
      ]),
      const SizedBox(height: 14),
      Text('New iPhone downloads per day', style: jost(13, weight: 500, color: HqColors.muted)),
      const SizedBox(height: 6),
      Bars(items: [for (final e in perDay.entries) (fmtDay(e.key), e.value)], height: 90),
      const SizedBox(height: 12),
      SimpleTable(
        header: const ['App', 'Downloads', 'Re-downloads', 'Updates'],
        rows: [
          for (final e in byTitle.entries)
            if (!e.key.startsWith('in-app')) [e.key, fmtNum(e.value[0]), fmtNum(e.value[1]), fmtNum(e.value[2])],
        ],
      ),
    ]);
    for (final e in s.asReviews.entries) {
      if (e.value.isEmpty) continue;
      out.add(const SizedBox(height: 10));
      out.add(Text('Newest App Store reviews · ${e.key}', style: jost(13, weight: 600)));
      for (final r in e.value.take(5)) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              '${_stars(r['rating'])}  ${r['title'] ?? ''} — ${r['body'] ?? ''}  '
              '(${r['territory'] ?? ''}, ${fmtDate(DateTime.tryParse('${r['createdDate']}'))})',
              style: jost(13)),
        ));
      }
    }
    return out;
  }

  static num _col(Map<String, String> r, List<String> names) {
    for (final n in names) {
      final v = r[n];
      if (v != null && v.isNotEmpty) return num.tryParse(v) ?? 0;
    }
    return 0;
  }

  List<Widget> _googlePlay() {
    final s = services;
    final out = <Widget>[const Heading('Google Play (Android)', note: 'Play\'s install reports, updated daily.')];
    final st = _state(s, 'googleplay');
    if (st != null) return out..add(st);
    final perDay = _emptyDays(_from);
    final rows = <List<String>>[];
    num allIn = 0, allOut = 0, allActive = 0;
    for (final e in s.playInstalls.entries) {
      num ins = 0, uns = 0, active = 0;
      DateTime? last;
      for (final r in e.value) {
        final d = _ymd(r['Date'] ?? '');
        if (d == null) continue;
        if (last == null || d.isAfter(last)) {
          last = d;
          active = _col(r, const ['Installs On Active Devices', 'Active Device Installs', 'Current Device Installs']);
        }
        if (d.isBefore(_from)) continue;
        final i = _col(r, const ['Daily User Installs', 'Install events', 'Daily Device Installs']);
        ins += i;
        uns += _col(r, const ['Daily User Uninstalls', 'Uninstall events', 'Daily Device Uninstalls']);
        perDay[d] = (perDay[d] ?? 0) + i;
      }
      allIn += ins;
      allOut += uns;
      allActive += active;
      rows.add([e.key, fmtNum(ins), fmtNum(uns), fmtNum(active), last == null ? 'no report yet' : fmtDay(last)]);
    }
    final at = s.state['googleplay']!.loadedAt!;
    const src = 'Google Play · install reports';
    out.addAll([
      Wrap(spacing: 14, runSpacing: 14, children: [
        NumberCard(label: 'Installs', value: fmtNum(allIn), sub: 'uninstalls: ${fmtNum(allOut)}', source: src, loadedAt: at),
        NumberCard(label: 'Active devices now', value: fmtNum(allActive), source: src, loadedAt: at),
      ]),
      const SizedBox(height: 14),
      Text('Android installs per day', style: jost(13, weight: 500, color: HqColors.muted)),
      const SizedBox(height: 6),
      Bars(items: [for (final e in perDay.entries) (fmtDay(e.key), e.value)], height: 90),
      const SizedBox(height: 12),
      SimpleTable(header: const ['App', 'Installs', 'Uninstalls', 'Active devices', 'Latest day'], rows: rows),
      if (days > 45)
        Text('Play reports: HQ loads this month and last month.', style: jost(12, color: HqColors.muted)),
    ]);
    for (final e in s.playReviews.entries) {
      if (e.value.isEmpty) continue;
      out.add(const SizedBox(height: 10));
      out.add(Text('Play reviews, last 7 days · ${e.key}', style: jost(13, weight: 600)));
      for (final r in e.value.take(5)) {
        final secs = r['seconds'] as int?;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              '${_stars(r['rating'])}  ${r['text']}'
              '${secs == null ? '' : '  (${fmtDate(DateTime.fromMillisecondsSinceEpoch(secs * 1000))})'}',
              style: jost(13)),
        ));
      }
    }
    return out;
  }

  List<Widget> _admob() {
    final s = services;
    final out = <Widget>[
      const Heading('AdMob', note: 'Estimated earnings in your AdMob account currency; the last 30 days.'),
    ];
    final st = _state(s, 'admob');
    if (st != null) return out..add(st);
    final perDay = _emptyDays(_from);
    final byApp = <String, List<num>>{};
    for (final r in s.admobRows) {
      final d = _ymd('${r['date']}');
      if (d == null || d.isBefore(_from)) continue;
      final b = byApp.putIfAbsent('${r['app']}', () => [0, 0, 0]);
      b[0] += r['earnings'] as double;
      b[1] += r['impressions'] as int;
      b[2] += r['clicks'] as int;
      perDay[d] = (perDay[d] ?? 0) + (r['earnings'] as double);
    }
    num sum(int i) => byApp.values.fold<num>(0, (a, b) => a + b[i]);
    final at = s.state['admob']!.loadedAt!;
    const src = 'AdMob · network report';
    out.addAll([
      Wrap(spacing: 14, runSpacing: 14, children: [
        NumberCard(label: 'Ad earnings', value: sum(0).toStringAsFixed(2), source: src, loadedAt: at),
        NumberCard(label: 'Impressions', value: fmtNum(sum(1)), sub: 'clicks: ${fmtNum(sum(2))}', source: src, loadedAt: at),
      ]),
      const SizedBox(height: 14),
      Text('Ad earnings per day', style: jost(13, weight: 500, color: HqColors.muted)),
      const SizedBox(height: 6),
      Bars(items: [for (final e in perDay.entries) (fmtDay(e.key), e.value)], height: 90),
      const SizedBox(height: 12),
      SimpleTable(
        header: const ['App', 'Earnings', 'Impressions', 'Clicks'],
        rows: [
          for (final e in byApp.entries) [e.key, e.value[0].toStringAsFixed(2), fmtNum(e.value[1]), fmtNum(e.value[2])],
        ],
      ),
    ]);
    return out;
  }
}

/// Websites: visits per site from Cloudflare (last 30 days).
class WebsiteTraffic extends StatelessWidget {
  const WebsiteTraffic({super.key, required this.services});
  final ServicesData services;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: services,
        builder: (context, _) {
          final st = _state(services, 'cloudflare');
          final out = <Widget>[
            Text('Cloudflare, last 30 days. Visitors = unique visitors per day, summed.',
                style: jost(12, color: HqColors.muted)),
            const SizedBox(height: 10),
          ];
          if (st != null) {
            out.add(st);
          } else {
            final at = services.state['cloudflare']!.loadedAt!;
            final rows = <List<String>>[];
            for (final e in services.cfDaily.entries) {
              num req = 0, pv = 0, un = 0, th = 0;
              for (final d in e.value) {
                req += d['requests'] as num;
                pv += d['pageViews'] as num;
                un += d['uniques'] as num;
                th += d['threats'] as num;
              }
              rows.add([e.key, fmtNum(un), fmtNum(pv), fmtNum(req), fmtNum(th)]);
            }
            out.add(SimpleTable(
                header: const ['Site', 'Visitors', 'Page views', 'Requests', 'Threats blocked'], rows: rows));
            for (final e in services.cfDaily.entries) {
              if (e.value.isEmpty) continue;
              out.add(const SizedBox(height: 12));
              out.add(Text('${e.key} · visitors per day', style: jost(13, weight: 500, color: HqColors.muted)));
              out.add(const SizedBox(height: 6));
              out.add(Bars(items: [
                for (final d in e.value)
                  (fmtDay(_ymd('${d['date']}') ?? todayDay()), (d['uniques'] as num).toDouble()),
              ], height: 70));
            }
            out.add(const SizedBox(height: 6));
            out.add(SourceLine(source: 'Cloudflare · zone analytics', loadedAt: at));
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
        },
      );
}

/// Page frame for screens fed by the outside services (Downloads, Websites): title, note, Refresh.
class ServicesFrame extends StatelessWidget {
  const ServicesFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.services,
    required this.ids,
    required this.children,
  });
  final String title;
  final String subtitle;
  final ServicesData services;
  final List<String> ids; // which services this page shows (for Refresh)
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: services,
        builder: (context, _) {
          final loading = ids.any((id) => services.state[id]!.loading);
          return ListView(padding: const EdgeInsets.all(32), children: [
            Row(children: [
              Expanded(child: Text(title, style: jost(26, weight: 600))),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('refreshes every hour', style: jost(12, color: HqColors.muted)),
              ),
              OutlinedButton(
                onPressed: loading
                    ? null
                    : () async {
                        for (final id in ids) {
                          await services.refresh(id);
                        }
                      },
                child: Text(loading ? 'Loading…' : 'Refresh'),
              ),
            ]),
            const SizedBox(height: 4),
            Text(subtitle, style: jost(14, color: HqColors.muted)),
            const SizedBox(height: 8),
            ...children,
          ]);
        },
      );
}
