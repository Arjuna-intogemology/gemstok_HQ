import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../widgets/charts.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';

/// Using: who opens each app.  Staying (staying: true): whether new people come back in their first week.
class UsingScreen extends StatelessWidget {
  const UsingScreen({super.key, required this.data, this.staying = false});
  final HqData data;
  final bool staying;

  static const _appNames = {
    'manikvault': 'ManiKVault',
    'gem_broker': 'Gem Broker',
    'quvlet': 'Quvlet',
    'gemmit': 'Gemmit',
    'gemstok': 'Gemstok',
    'all apps': 'All apps (each person once)',
  };

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: staying ? 'Staying' : 'Using',
      subtitle: staying
          ? 'Of the people who joined in a week: how many opened an app again on day 1–7 after joining.'
          : 'Active = opened the app. Rolling windows: last 24 hours, 7 days, 30 days.',
      data: data,
      queries: staying ? const [Q.retention] : const [Q.active],
      body: () {
        final active = staying ? null : data.rows(Q.active);
        final ret = staying ? data.rows(Q.retention) : null;
        return [
          if (active != null) ...[
            SimpleTable(
              header: const ['App', '24 hours', '7 days', '30 days'],
              rows: [
                for (final r in active)
                  [
                    _appNames[r['app']] ?? '${r['app']}',
                    fmtNum(r['d1']),
                    fmtNum(r['d7']),
                    fmtNum(r['d30']),
                  ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
                'Counts an app open when ManiKVault\'s Browse tab, Gem Broker\'s Market or Quvlet opens. '
                'Vault-only use isn\'t counted yet (app change planned).',
                style: jost(12, color: HqColors.muted)),
          ],
          if (ret != null) ...[
            Text('Weeks marked "still counting" aren\'t finished yet.', style: jost(12, color: HqColors.muted)),
            const SizedBox(height: 8),
            SimpleTable(
              header: const ['Joined week of', 'Joined', 'Came back', 'Return rate'],
              rows: [
                for (final r in ret)
                  [
                    '${fmtDay(asDay(r['week']))}${(r['complete'] as bool) ? '' : ' · still counting'}',
                    fmtNum(r['joined']),
                    fmtNum(r['returned']),
                    fmtPct(r['returned'] as int, r['joined'] as int),
                  ],
              ],
            ),
          ],
          const SizedBox(height: 20),
          Text('Source: ${(staying ? Q.retention : Q.active).source}', style: jost(11, color: HqColors.muted)),
        ];
      },
    );
  }
}
