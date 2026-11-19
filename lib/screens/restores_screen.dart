import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:postgres/postgres.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/hq_db.dart';
import '../db/projects.dart';
import '../restores/restore_seen_store.dart';
import '../settings/key_store.dart';
import '../db/queries.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import '../widgets/source_line.dart';

/// Restore requests (READ ONLY): a deleted member signed in again with the same email, got a new
/// TEMP- id, typed their rejoin PIN, and asked for their old GSM id back.
/// HQ never approves or rejects. It only shows the line to paste into the Supabase SQL Editor.
class RestoresScreen extends StatefulWidget {
  const RestoresScreen({super.key, required this.data});
  final HqData data;

  @override
  State<RestoresScreen> createState() => _RestoresScreenState();
}

class _RestoresScreenState extends State<RestoresScreen> {
  String _status = 'pending';

  /// old member id → "12 stones · 3 on the Market · 1 sold" (ManiKVault data), loaded once per id.
  final Map<String, String> _stones = {};
  bool _loadingStones = false;

  /// request id → {old_trust, new_trust}; empty until 2026-11-18_hq_trust_score is run.
  Map<String, Map<String, dynamic>> _trust = {};

  String _trustText(Map<String, dynamic> r, String key) {
    if (_trust.isEmpty) return 'Trust score: not readable yet (run 2026-11-18_hq_trust_score)';
    final v = _trust['${r['id']}']?[key];
    return 'Trust score: ${v ?? 'none'}';
  }

  Future<void> _loadStones(List<String> ids) async {
    final todo = ids.where((id) => !_stones.containsKey(id)).toList();
    if (todo.isEmpty || _loadingStones) return;
    _loadingStones = true;
    final mkv = hqProjects.firstWhere((p) => p.id == 'mkv');
    if (!await KeyStore.isSet(mkv.id)) {
      for (final id in todo) {
        _stones[id] = 'ManiKVault data not connected';
      }
    } else {
      Connection? conn;
      try {
        conn = await HqDb.open(mkv);
        for (final id in todo) {
          final r = (await conn.execute(Q.personStonesSql, parameters: [id])).first.toColumnMap();
          _stones[id] = '${r['stones']} stones · ${r['on_market']} on the Market · ${r['sold']} sold';
        }
      } catch (e) {
        for (final id in todo) {
          _stones[id] = 'couldn\'t load stones';
        }
      } finally {
        await conn?.close();
      }
    }
    _loadingStones = false;
    if (mounted) setState(() {});
  }

  static String approveLine(String gsm) => "select public.approve_restore('$gsm');";
  static String rejectLine(String gsm) => "select public.reject_restore('$gsm', 'reason here');";

  /// "3 h", "2 days" — how long it has waited (pending) or took (decided).
  static String _waited(DateTime? from, DateTime? to) {
    if (from == null) return '–';
    final d = (to ?? DateTime.now()).difference(from.toLocal());
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return '${d.inDays} days';
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $text'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return ScreenFrame(
      title: 'Restore requests',
      subtitle: 'Deleted members who came back and asked for their old GSM id. Read only — '
          'you approve in the Supabase SQL Editor.',
      data: data,
      queries: const [Q.restoreRequests, Q.restoreTrust],
      body: () {
        final all = data.rows(Q.restoreRequests);
        if (all == null) {
          return [
            const NoteBox(
              color: HqColors.warn,
              text: 'HQ can\'t read restore requests yet. Run Gemstok '
                  'sql/2026-11-18_hq_restore_requests/2_change.sql in the SQL Editor, then press Refresh.',
            ),
          ];
        }
        final count = <String, int>{};
        for (final r in all) {
          count['${r['status']}'] = (count['${r['status']}'] ?? 0) + 1;
        }
        final pending = count['pending'] ?? 0;
        final shown = all.where((r) => _status == 'all' || r['status'] == _status).toList();
        _trust = {for (final t in data.rows(Q.restoreTrust) ?? const <Map<String, dynamic>>[]) '${t['id']}': t};
        final ids = {for (final r in shown) if (r['old_id'] != null) '${r['old_id']}'}.toList();
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadStones(ids));

        // "Restore approved" — shown here for the next 5 times this page is opened after each approval
        final justApproved = all
            .where((r) => r['status'] == 'approved' && RestoreSeenStore.show('${r['id']}'))
            .toList();
        return [
          for (final r in justApproved)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NoteBox(
                color: HqColors.good,
                text: 'Restore approved: ${r['old_gemstok_id']} (was ${r['new_gemstok_id'] ?? 'TEMP'}) · '
                    'login moved · they sign in again with the same account · '
                    '${fmtDateTime(r['decided_at'] as DateTime?)} · shown ${RestoreSeenStore.seen('${r['id']}')} '
                    'of ${RestoreSeenStore.maxOpens}',
              ),
            ),
          NoteBox(
            color: pending == 0 ? HqColors.good : HqColors.warn,
            text: pending == 0 ? 'No restore requests waiting.' : '$pending restore request(s) waiting for you.',
          ),
          Choice<String>(
            options: {
              'pending': 'Waiting (${count['pending'] ?? 0})',
              'approved': 'Approved (${count['approved'] ?? 0})',
              'rejected': 'Rejected (${count['rejected'] ?? 0})',
              'all': 'All (${all.length})',
            },
            value: _status,
            onChanged: (v) => setState(() => _status = v),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Text('Nothing here.', style: jost(13, color: HqColors.muted))
          else
            for (final r in shown) _row(r),
          const SizedBox(height: 4),
          SourceLine(source: Q.restoreRequests.source, loadedAt: data.loadedAt(Q.restoreRequests) ?? DateTime.now()),
          const Heading('How to approve'),
          Text(
            '1. Check it\'s really them: the app already checked their rejoin PIN. Names are wiped on delete, '
            'so look at trust score, joined date, apps, stones and the sign-in type.\n'
            '2. Click "Copy approve line", open the Gemstok project → SQL Editor, paste, Run.\n'
            '3. Press Refresh here — the row moves to Approved.\n'
            'To say no: "Copy reject line", change "reason here", Run.\n'
            'Both functions are admin only. HQ can\'t run them, on purpose.',
            style: jost(13, color: HqColors.muted),
          ),
        ];
      },
    );
  }

  /// A small block of facts: title + one line each.
  Widget _facts(String title, List<String> lines) => SizedBox(
        width: 360,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: jost(12, weight: 600, color: HqColors.muted)),
          const SizedBox(height: 4),
          for (final l in lines) Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(l, style: jost(13)),
          ),
        ]),
      );

  Widget _row(Map<String, dynamic> r) {
    final gsm = '${r['old_gemstok_id'] ?? '–'}';
    final temp = r['new_gemstok_id'] == null ? '(new account gone)' : '${r['new_gemstok_id']}';
    final status = '${r['status']}';
    final created = r['created_at'] as DateTime?;
    final decided = r['decided_at'] as DateTime?;
    final isPending = status == 'pending';
    final color = switch (status) {
      'pending' => HqColors.warn,
      'approved' => HqColors.good,
      _ => HqColors.muted,
    };
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
          SelectableText(gsm, style: jost(16, weight: 600)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('→', style: jost(16, color: HqColors.muted)),
          ),
          SelectableText(temp, style: jost(16)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(status, style: jost(12, weight: 600, color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          isPending
              ? 'Asked ${fmtDateTime(created)} · waiting ${_waited(created, null)}'
              : 'Asked ${fmtDateTime(created)} · decided ${fmtDateTime(decided)} (took ${_waited(created, decided)})',
          style: jost(13, color: HqColors.muted),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 28, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.start, children: [
          _facts('Old account · $gsm', r['old_id'] == null
              ? ['Not found in members (gone?) — don\'t approve.']
              : [
                  'Joined ${fmtDate(r['old_joined'] as DateTime?)}',
                  'Deleted ${fmtDateTime(r['old_deleted'] as DateTime?)}'
                      '${r['old_deleted'] == null ? '' : ' · came back after ${_waited(r['old_deleted'] as DateTime?, created)}'}',
                  _trustText(r, 'old_trust'),
                  'Tier: ${r['old_tier'] ?? '–'}${r['old_verified'] == true ? ' · verified' : ''}',
                  'Apps: ${r['old_apps'] ?? 'none'}',
                  '${fmtNum(r['old_logins'] ?? 0)} logins · last: ${r['old_last_app'] ?? '–'} ${fmtDate(r['old_last_seen'] as DateTime?)}',
                  '${fmtNum(r['old_purchases'])} credit purchase(s) · ${fmtNum(r['old_credits_lost'])} credits removed on delete',
                  _stones['${r['old_id']}'] ?? 'stones: loading…',
                ]),
          _facts('New account · $temp', [
            'Signed up ${fmtDateTime(r['new_joined'] as DateTime?)}',
            'Sign-in: ${r['new_signin'] ?? '–'} · app: ${r['new_last_app'] ?? '–'}',
            _trustText(r, 'new_trust'),
            if ((r['other_requests'] as int? ?? 0) > 0)
              '⚠ ${r['other_requests']} other request(s) for this GSM',
          ]),
        ]),
        if (isPending && gsm != '–') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: HqColors.line),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(approveLine(gsm), style: const TextStyle(fontFamily: 'Menlo', fontSize: 13)),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.tonal(onPressed: () => _copy(approveLine(gsm)), child: const Text('Copy approve line')),
            TextButton(onPressed: () => _copy(rejectLine(gsm)), child: const Text('Copy reject line')),
          ]),
        ],
      ]),
    );
  }
}
