import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../renewals/renewals_screen.dart';
import '../shell/sections.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import '../widgets/source_line.dart';

/// Today: sign-ups, active people, credits bought (today / last 7 days) + one health check.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.data, this.onOpenRenewals, this.onOpenSection});
  final HqData data;
  final VoidCallback? onOpenRenewals;
  final ValueChanged<HqSection>? onOpenSection;

  /// Inbox: open reports (people + stones) and open restore requests. Click → that page.
  List<Widget> _inbox() {
    final people = data.rows(Q.traderReports);
    final stones = data.rows(Q.mkvStoneReports);
    final restores = data.rows(Q.restoreRequests);
    final openReports = (people ?? const []).where((r) => r['status'] == 'open').length +
        (stones ?? const []).where((r) => r['status'] == 'open').length;
    final pending = (restores ?? const []).where((r) => r['status'] == 'pending').toList();
    DateTime? oldest;
    for (final r in pending) {
      final c = r['created_at'] as DateTime?;
      if (c != null && (oldest == null || c.isBefore(oldest))) oldest = c;
    }
    Widget click(HqSection s, Widget child) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(onTap: () => onOpenSection?.call(s), child: child),
        );
    return [
      const Heading('Inbox'),
      Wrap(spacing: 14, runSpacing: 14, children: [
        if (people != null)
          click(
              HqSection.reports,
              NumberCard(
                label: 'Unreviewed reports',
                value: fmtNum(openReports),
                sub: stones == null ? 'people' : 'people + stones',
                source: 'Gemstok · trader_reports${stones == null ? '' : ' + ManiKVault data · stone_reports'}',
                loadedAt: data.loadedAt(Q.traderReports) ?? DateTime.now(),
              )),
        if (restores == null)
          const NotConnectedCard(label: 'Open restore requests', project: 'Gemstok restore access')
        else
          click(
              HqSection.restores,
              NumberCard(
                label: 'Open restore requests',
                value: fmtNum(pending.length),
                sub: oldest == null ? 'none waiting' : 'oldest waiting: ${fmtAgo(oldest).replaceAll(' ago', '')}',
                source: 'Gemstok · restore_requests',
                loadedAt: data.loadedAt(Q.restoreRequests) ?? DateTime.now(),
              )),
      ]),
    ];
  }

  /// Market listings from ManiKVault data — or a grey card until that database is connected.
  Widget _stonesCard() {
    final m = data.rows(Q.mkvStones)?.firstOrNull;
    if (m == null) return const NotConnectedCard(label: 'Stones listed', project: 'ManiKVault data');
    return NumberCard(
      label: 'Stones listed today',
      value: fmtNum(m['listed_today']),
      sub: '7 days: ${fmtNum(m['listed_7d'])} · on the market now: ${fmtNum(m['market_active'])}',
      source: 'ManiKVault data · stones',
      loadedAt: data.loadedAt(Q.mkvStones) ?? DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Today',
      subtitle: 'Since midnight Sri Lanka time · "7 days" = today + the 6 days before.',
      data: data,
      queries: const [Q.today, Q.mkvStones, Q.traderReports, Q.mkvStoneReports, Q.restoreRequests],
      body: () {
        final row = data.rows(Q.today)?.firstOrNull;
        final at = data.loadedAt(Q.today) ?? DateTime.now();
        final renewals = RenewalsBanner(onOpen: onOpenRenewals ?? () {});
        if (row == null) return [renewals];
        final orphans = (row['logins_without_member'] as int?) ?? 0;
        return [
          renewals,
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              NumberCard(
                label: 'Sign-ups today',
                value: fmtNum(row['signups_today']),
                sub: '7 days: ${fmtNum(row['signups_7d'])}',
                source: 'Gemstok · members',
                loadedAt: at,
              ),
              NumberCard(
                label: 'Active people today',
                value: fmtNum(row['active_today']),
                sub: '7 days: ${fmtNum(row['active_7d'])}',
                source: 'Gemstok · login_history',
                loadedAt: at,
              ),
              NumberCard(
                label: 'Credits bought today',
                value: fmtNum(row['credits_today']),
                sub: '7 days: ${fmtNum(row['credits_7d'])} (${fmtNum(row['purchases_7d'])} purchases)',
                source: 'Gemstok · credit_transactions · no test buys',
                loadedAt: at,
              ),
              _stonesCard(),
            ],
          ),
          ..._inbox(),
          const Heading('Health'),
          Row(children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: orphans == 0 ? HqColors.good : HqColors.warn,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                orphans == 0
                    ? 'Every login has a member row.'
                    : '$orphans login(s) have NO member row — the sign-up step failed for them.',
                style: jost(14),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          SourceLine(source: 'Gemstok · auth identities vs members', loadedAt: at),
          const SizedBox(height: 28),
          Text(
              '"Active" = opened ManiKVault\'s Browse tab, Gem Broker\'s Market or Quvlet. '
              'People who only use the Vault aren\'t counted yet (app change planned).',
              style: jost(12, color: HqColors.muted)),
        ];
      },
    );
  }
}
