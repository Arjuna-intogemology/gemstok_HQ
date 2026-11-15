import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../widgets/charts.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';

/// Reports: every report people send, from every app, in one place.
/// Now: reports about PEOPLE (Gemstok). Stone reports (ManiKVault data) and post reports (Gemmit)
/// join when those databases are connected.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.data});
  final HqData data;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _status = 'all';

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return ScreenFrame(
      title: 'Reports',
      subtitle: 'Reports people send from the apps — newest first.',
      data: data,
      queries: const [
        Q.traderReports, Q.mkvStoneReports, Q.gemmitPostReports,
        Q.traderReportDetails, Q.stoneReportDetails, Q.postReportDetails, Q.memberNames,
      ],
      body: () {
        final all = data.rows(Q.traderReports);
        if (all == null) return [];
        final openStones = (data.rows(Q.mkvStoneReports) ?? const []).where((r) => r['status'] == 'open').length;
        final open = all.where((r) => r['status'] == 'open').length + openStones;

        final byStatus = <String, int>{};
        final byReason = <String, int>{};
        for (final r in all) {
          byStatus['${r['status']}'] = (byStatus['${r['status']}'] ?? 0) + 1;
          byReason['${r['reason']}'] = (byReason['${r['reason']}'] ?? 0) + 1;
        }
        final reasons = byReason.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final shown = all.where((r) => _status == 'all' || r['status'] == _status).take(50).toList();

        return [
          NoteBox(
            color: open == 0 ? HqColors.good : HqColors.warn,
            text: open == 0
                ? 'No open reports.'
                : '$open open report(s) waiting for a look (people + stones).',
          ),
          const Heading('Reports about people',
              note: 'From profiles and chats (Gemstok · trader_reports). HQ can\'t see who reported whom or the '
                  'written details yet — see the note at the bottom.'),
          Wrap(spacing: 24, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.start, children: [
            SizedBox(
              width: 300,
              child: SimpleTable(
                header: const ['Status', 'Reports'],
                rows: [for (final e in byStatus.entries) [e.key, '${e.value}']],
              ),
            ),
            SizedBox(
              width: 420,
              child: SimpleTable(
                header: const ['Reason', 'Reports'],
                rows: [for (final e in reasons) [e.key, '${e.value}']],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Choice<String>(
            options: {'all': 'All', for (final s in byStatus.keys) s: s},
            value: _status,
            onChanged: (v) => setState(() => _status = v),
          ),
          const SizedBox(height: 10),
          _peopleTable(shown, _byId(data.rows(Q.traderReportDetails))),
          ..._stoneReports(data),
          ..._postReports(data),
          const SizedBox(height: 24),
          Text(
              'Who reported whom and the written details show once each project\'s '
              'sql/2026-11-14_hq_report_details is run. Until then the tables show reasons and status only.',
              style: jost(12, color: HqColors.muted)),
        ];
      },
    );
  }

  List<Widget> _stoneReports(HqData data) {
    final rows = data.rows(Q.mkvStoneReports);
    final det = _byId(data.rows(Q.stoneReportDetails));
    return [
      const Heading('Reports about Market stones',
          note: 'ManiKVault data · stone_reports. 3+ open reports hide a stone from the Market automatically.'),
      if (rows == null)
        const NotConnectedCard(label: 'Stone reports', project: 'ManiKVault data')
      else
        SimpleTable(
          header: det.isEmpty
              ? const ['Stone', 'Reason', 'App', 'Status', 'Sent']
              : const ['Stone', 'Reason', 'Reporter', 'Seller', 'Details', 'Status', 'Sent'],
          rows: [
            for (final r in rows.take(50))
              if (det.isNotEmpty)
                [
                  '${r['stone_mkv_id'] ?? '–'}',
                  '${r['reason']}',
                  _who(data, det[r['id']]?['reporter_id']),
                  _who(data, det[r['id']]?['seller_id']),
                  _text(det[r['id']]?['details'], det[r['id']]?['admin_note']),
                  '${r['status']}',
                  fmtDateTime(r['created_at'] as DateTime?),
                ]
              else
              [
                '${r['stone_mkv_id'] ?? '–'}',
                '${r['reason']}',
                '${r['app']}',
                '${r['status']}',
                fmtDateTime(r['created_at'] as DateTime?),
              ],
          ],
        ),
    ];
  }

  List<Widget> _postReports(HqData data) {
    final rows = data.rows(Q.gemmitPostReports);
    final det = _byId(data.rows(Q.postReportDetails));
    return [
      const Heading('Reports about Gemmit posts', note: 'Gemmit · post_reports'),
      if (rows == null)
        const NotConnectedCard(label: 'Post reports', project: 'Gemmit')
      else
        SimpleTable(
          header: det.isEmpty ? const ['Reason', 'Sent'] : const ['Reason', 'Reporter', 'Details', 'Sent'],
          rows: [
            for (final r in rows.take(50))
              if (det.isNotEmpty)
                [
                  '${r['reason']}',
                  _who(data, det[r['id']]?['reporter_id']),
                  _text(det[r['id']]?['details'], null),
                  fmtDateTime(r['created_at'] as DateTime?),
                ]
              else
                ['${r['reason']}', fmtDateTime(r['created_at'] as DateTime?)],
          ],
        ),
    ];
  }

  /// id → details row ({} when the details SQL isn't run yet)
  static Map<String, Map<String, dynamic>> _byId(List<Map<String, dynamic>>? rows) =>
      {for (final r in rows ?? const <Map<String, dynamic>>[]) '${r['id']}': r};

  /// member id → "Name (GSM-000123)" from Gemstok's names (kept in memory only)
  static String _who(HqData data, Object? memberId) {
    if (memberId == null) return '–';
    final m = data.rows(Q.memberNames)?.where((r) => r['id'] == '$memberId').firstOrNull;
    return m == null ? '${'$memberId'.substring(0, 8)}…' : '${m['name']} (${m['gemstok_id']})';
  }

  static String _text(Object? details, Object? note) {
    final d = (details ?? '').toString().trim();
    final n = (note ?? '').toString().trim();
    return [if (d.isNotEmpty) d, if (n.isNotEmpty) 'note: $n'].join(' · ').ifEmpty('–');
  }

  Widget _peopleTable(List<Map<String, dynamic>> shown, Map<String, Map<String, dynamic>> det) {
    if (det.isEmpty) {
      return SimpleTable(
        header: const ['Reason', 'From', 'Status', 'Sent', 'Reviewed'],
        rows: [
          for (final r in shown)
            [
              '${r['reason']}',
              '${r['source']}',
              '${r['status']}',
              fmtDateTime(r['created_at'] as DateTime?),
              fmtDate(r['reviewed_at'] as DateTime?),
            ],
        ],
      );
    }
    String person(Object? name, Object? gsm) => name == null ? '–' : '$name ($gsm)';
    return SimpleTable(
      header: const ['Reason', 'Reporter', 'Reported', 'Details', 'From', 'Status', 'Sent'],
      rows: [
        for (final r in shown)
          [
            '${r['reason']}',
            person(det[r['id']]?['reporter_name'], det[r['id']]?['reporter_gsm']),
            person(det[r['id']]?['reported_name'], det[r['id']]?['reported_gsm']),
            _text(det[r['id']]?['details'], det[r['id']]?['admin_note']),
            '${r['source']}',
            '${r['status']}',
            fmtDateTime(r['created_at'] as DateTime?),
          ],
      ],
    );
  }
}

extension _IfEmpty on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
