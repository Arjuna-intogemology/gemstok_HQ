import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../widgets/charts.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import '../widgets/source_line.dart';

/// Doing: what people do. Credits (bought / spent on boosts, ad-free, courses) and reports from Gemstok;
/// stones, market, chats, Gemmit and follows once those databases are connected.
class DoingScreen extends StatefulWidget {
  const DoingScreen({super.key, required this.data});
  final HqData data;

  @override
  State<DoingScreen> createState() => _DoingScreenState();
}

class _DoingScreenState extends State<DoingScreen> {
  int _days = 30;

  static const _perkNames = {
    'boost': 'Boosts',
    'ad_free': 'Ad-free time',
    'course': 'Courses',
    '': 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return ScreenFrame(
      title: 'Doing',
      subtitle: 'What people do in the apps. Test purchases (sandbox / App Review) are left out.',
      data: data,
      queries: const [
        Q.credits, Q.traderReports, Q.mkvStones, Q.mkvListingsPerDay, Q.mkvBoostViews,
        Q.socialFollows, Q.chatCounts, Q.gemmitCounts, Q.siteLeads, Q.quvletCounts, Q.traceCounts,
      ],
      body: () {
        final all = data.rows(Q.credits);
        final reports = data.rows(Q.traderReports);
        final at = data.loadedAt(Q.credits) ?? DateTime.now();
        if (all == null) return [];
        final from = todayDay().subtract(Duration(days: _days - 1));
        final rows = all.where((r) => !asDay(r['day']).isBefore(from)).toList();

        double sum(bool Function(Map<String, dynamic>) f) =>
            rows.where(f).fold<double>(0, (a, r) => a + (r['credits'] as double));
        int count(bool Function(Map<String, dynamic>) f) =>
            rows.where(f).fold<int>(0, (a, r) => a + (r['n'] as int));

        final bought = sum((r) => r['type'] == 'purchase');
        final buys = count((r) => r['type'] == 'purchase');
        final spent = sum((r) => r['type'] == 'deduct');
        final bonus = sum((r) => r['type'] == 'bonus');
        final refunds = sum((r) => r['type'] == 'refund');

        // spent, split by what it bought
        final perks = <String, (int, double)>{};
        for (final r in rows.where((r) => r['type'] == 'deduct')) {
          final p = r['perk'] as String;
          final old = perks[p] ?? (0, 0.0);
          perks[p] = (old.$1 + (r['n'] as int), old.$2 + (r['credits'] as double));
        }
        // per app
        final apps = <String, (double, double)>{};
        for (final r in rows) {
          final a = r['app'] as String;
          final old = apps[a] ?? (0.0, 0.0);
          if (r['type'] == 'purchase') apps[a] = (old.$1 + (r['credits'] as double), old.$2);
          if (r['type'] == 'deduct') apps[a] = (old.$1, old.$2 + (r['credits'] as double));
        }
        // bought per day
        final perDay = <DateTime, double>{
          for (var d = from; !d.isAfter(todayDay()); d = d.add(const Duration(days: 1))) d: 0,
        };
        for (final r in rows.where((r) => r['type'] == 'purchase')) {
          final d = asDay(r['day']);
          perDay[d] = (perDay[d] ?? 0) + (r['credits'] as double);
        }
        final reportsInRange = reports
                ?.where((r) => !dayOf(r['created_at'] as DateTime).isBefore(from))
                .length ??
            0;

        return [
          Choice<int>(
            options: const {7: '7 days', 30: '30 days', 90: '90 days'},
            value: _days,
            onChanged: (v) => setState(() => _days = v),
          ),
          const Heading('Credits'),
          Wrap(spacing: 14, runSpacing: 14, children: [
            NumberCard(
                label: 'Credits bought',
                value: fmtNum(bought),
                sub: '$buys purchases',
                source: 'Gemstok · credit_transactions',
                loadedAt: at),
            NumberCard(
                label: 'Credits spent',
                value: fmtNum(spent),
                sub: '${count((r) => r['type'] == 'deduct')} times',
                source: 'Gemstok · credit_transactions',
                loadedAt: at),
            NumberCard(
                label: 'Given free (bonus)',
                value: fmtNum(bonus),
                sub: 'refunded: ${fmtNum(refunds)}',
                source: 'Gemstok · credit_transactions',
                loadedAt: at),
            NumberCard(
                label: 'Reports about people',
                value: '$reportsInRange',
                sub: 'see Reports',
                source: 'Gemstok · trader_reports',
                loadedAt: data.loadedAt(Q.traderReports) ?? at),
          ]),
          const SizedBox(height: 14),
          Text('Credits bought per day', style: jost(13, weight: 500, color: HqColors.muted)),
          const SizedBox(height: 6),
          Bars(items: [for (final e in perDay.entries) (fmtDay(e.key), e.value)], height: 100),
          const Heading('Spent on'),
          SimpleTable(
            header: const ['What', 'Times', 'Credits'],
            rows: [
              for (final e in perks.entries)
                [_perkNames[e.key] ?? e.key, '${e.value.$1}', fmtNum(e.value.$2)],
            ],
          ),
          const Heading('By app'),
          SimpleTable(
            header: const ['App', 'Bought', 'Spent'],
            rows: [
              for (final e in apps.entries) [e.key, fmtNum(e.value.$1), fmtNum(e.value.$2)],
            ],
          ),
          ..._otherDatabases(data, from),
        ];
      },
    );
  }

  /// One block per other database: real numbers once connected, a grey card until then.
  List<Widget> _otherDatabases(HqData data, DateTime from) {
    Widget card(HqQuery q, String label, String Function(Map<String, dynamic>) value,
        String Function(Map<String, dynamic>) sub) {
      final r = data.rows(q)?.firstOrNull;
      if (r == null) return NotConnectedCard(label: label, project: q.project.name);
      return NumberCard(
          label: label, value: value(r), sub: sub(r), source: q.source, loadedAt: data.loadedAt(q) ?? DateTime.now());
    }

    final perDay = <DateTime, double>{
      for (var d = from; !d.isAfter(todayDay()); d = d.add(const Duration(days: 1))) d: 0,
    };
    for (final r in data.rows(Q.mkvListingsPerDay) ?? const <Map<String, dynamic>>[]) {
      final d = asDay(r['day']);
      if (!d.isBefore(from)) perDay[d] = (perDay[d] ?? 0) + (r['n'] as int);
    }
    var views = 0, taps = 0;
    for (final r in data.rows(Q.mkvBoostViews) ?? const <Map<String, dynamic>>[]) {
      if (asDay(r['day']).isBefore(from)) continue;
      views += r['views'] as int;
      taps += r['taps'] as int;
    }

    return [
      const Heading('Stones', note: 'ManiKVault data. Vault stones that stay on phones (v1) aren\'t counted.'),
      Wrap(spacing: 14, runSpacing: 14, children: [
        card(Q.mkvStones, 'On the market now', (r) => fmtNum(r['market_active']),
            (r) => '${fmtNum(r['sellers'])} sellers · ${fmtNum(r['boosted_now'])} boosted now'),
        card(Q.mkvStones, 'Listed (last 7 days)', (r) => fmtNum(r['listed_7d']),
            (r) => 'sold so far: ${fmtNum(r['sold'])}'),
        card(Q.mkvStones, 'Cloud vault · TraceGems layer', (r) => fmtNum(r['vault_cloud']),
            (r) => 'trace layer: ${fmtNum(r['trace'])}'),
        card(Q.mkvBoostViews, 'Boost views · taps', (_) => '$views', (_) => '$taps taps in this range'),
      ]),
      if (data.rows(Q.mkvListingsPerDay) != null) ...[
        const SizedBox(height: 14),
        Text('Market listings per day', style: jost(13, weight: 500, color: HqColors.muted)),
        const SizedBox(height: 6),
        Bars(items: [for (final e in perDay.entries) (fmtDay(e.key), e.value)], height: 100),
      ],
      const Heading('Chats', note: 'Counts only — HQ can never read messages or see who talks to whom.'),
      Wrap(spacing: 14, runSpacing: 14, children: [
        card(Q.chatCounts, 'Chats started (7 days)', (r) => fmtNum(r['started_7d']),
            (r) => '30 days: ${fmtNum(r['started_30d'])} · all: ${fmtNum(r['conversations'])}'),
        card(Q.chatCounts, 'Messages sent (7 days)', (r) => fmtNum(r['messages_7d']),
            (r) => '30 days: ${fmtNum(r['messages_30d'])}'),
      ]),
      const Heading('Gemmit · follows'),
      Wrap(spacing: 14, runSpacing: 14, children: [
        card(Q.gemmitCounts, 'Gemmit posts (7 days)', (r) => fmtNum(r['posts_7d']),
            (r) => '30 days: ${fmtNum(r['posts_30d'])} · all: ${fmtNum(r['posts'])}'),
        card(Q.gemmitCounts, 'Circles', (r) => fmtNum(r['circles']),
            (r) => '${fmtNum(r['memberships'])} memberships · new in 30 days: ${fmtNum(r['circles_30d'])}'),
        card(Q.socialFollows, 'Follows', (r) => fmtNum(r['follows']),
            (r) => '${fmtNum(r['people_following'])} people follow someone'),
      ]),
      const Heading('Websites · Quvlet · TraceGems'),
      Wrap(spacing: 14, runSpacing: 14, children: [
        card(Q.siteLeads, 'Waitlist sign-ups', (r) => fmtNum(r['waitlist']),
            (r) => '7 days: ${fmtNum(r['waitlist_7d'])} · newsletter: ${fmtNum(r['subscribers'])}'),
        card(Q.siteLeads, 'Contact form', (r) => fmtNum(r['contacts']), (_) => 'messages, all time'),
        card(Q.quvletCounts, 'Quvlet videos', (r) => fmtNum(r['videos']),
            (r) => '7 days: ${fmtNum(r['videos_7d'])} · ${fmtNum(r['views'])} views · ${fmtNum(r['likes'])} likes'
                '${(r['reports'] as int) > 0 ? ' · ${r['reports']} reports' : ''}'),
        card(Q.traceCounts, 'TraceGems records', (r) => fmtNum(r['records']),
            (r) => '${fmtNum(r['minted'])} minted · ${fmtNum(r['last_30d'])} in 30 days'),
      ]),
    ];
  }
}
