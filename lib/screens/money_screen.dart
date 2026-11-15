import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../services/services_data.dart';
import '../services/services_view.dart';
import '../widgets/charts.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import '../widgets/source_line.dart';

/// Money — what Gemstok itself records: store purchases of credit packs
/// (real vs test) and credits bought. App Store / Google Play sales and AdMob come with their keys.
class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key, required this.data, required this.services});
  final HqData data;
  final ServicesData services;

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return ScreenFrame(
      title: 'Money',
      subtitle: 'Credit packs bought in the stores, as Gemstok recorded them (test purchases apart), then '
          'App Store proceeds and AdMob. Downloads have their own page.',
      data: data,
      queries: const [Q.storePurchases, Q.credits],
      body: () {
        final stores = StoresAndAds(services: widget.services, days: _days, downloads: false);
        final all = data.rows(Q.storePurchases);
        if (all == null) return [stores];
        final at = data.loadedAt(Q.storePurchases) ?? DateTime.now();
        final from = todayDay().subtract(Duration(days: _days - 1));
        final rows = all.where((r) => !asDay(r['day']).isBefore(from)).toList();
        bool test(Map<String, dynamic> r) => r['environment'] == 'sandbox';
        int n(Iterable<Map<String, dynamic>> it) => it.fold<int>(0, (a, r) => a + (r['n'] as int));
        double cr(Iterable<Map<String, dynamic>> it) => it.fold<double>(0, (a, r) => a + (r['credits'] as double));
        final real = rows.where((r) => !test(r));
        final tests = rows.where(test);

        final byProduct = <String, (int, double)>{};
        for (final r in real) {
          final k = '${r['app']} · ${r['store']} · ${r['product_id']}';
          final o = byProduct[k] ?? (0, 0.0);
          byProduct[k] = (o.$1 + (r['n'] as int), o.$2 + (r['credits'] as double));
        }
        final perDay = <DateTime, double>{
          for (var d = from; !d.isAfter(todayDay()); d = d.add(const Duration(days: 1))) d: 0,
        };
        for (final r in real) {
          final d = asDay(r['day']);
          perDay[d] = (perDay[d] ?? 0) + (r['n'] as int);
        }

        return [
          Choice<int>(
            options: const {7: '7 days', 30: '30 days', 90: '90 days', 365: '1 year'},
            value: _days,
            onChanged: (v) => setState(() => _days = v),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 14, runSpacing: 14, children: [
            NumberCard(
                label: 'Store purchases (real)',
                value: '${n(real)}',
                sub: '${fmtNum(cr(real))} credits',
                source: 'Gemstok · store_purchases',
                loadedAt: at),
            NumberCard(
                label: 'Test purchases',
                value: '${n(tests)}',
                sub: 'sandbox / App Review — not money',
                source: 'Gemstok · store_purchases',
                loadedAt: at),
          ]),
          const SizedBox(height: 14),
          Text('Real store purchases per day', style: jost(13, weight: 500, color: HqColors.muted)),
          const SizedBox(height: 6),
          Bars(items: [for (final e in perDay.entries) (fmtDay(e.key), e.value)], height: 100),
          const Heading('By product'),
          SimpleTable(
            header: const ['App · store · product', 'Purchases', 'Credits'],
            rows: [
              for (final e in byProduct.entries) [e.key, '${e.value.$1}', fmtNum(e.value.$2)],
            ],
          ),
          const SizedBox(height: 16),
          const NoteBox(
            color: HqColors.warn,
            text: 'ManiKVault\'s Android credit buys (older purchase function) aren\'t in store_purchases yet — '
                'they show under Doing → Credits.',
          ),
          stores,
        ];
      },
    );
  }
}
