import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/hq_db.dart';
import '../db/projects.dart';
import '../db/queries.dart';
import '../settings/key_store.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';

/// People: look up one member by GSM ID or username. Never email, phone, chat or costs.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.data});
  final HqData data;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _found;
  final _stones = <String, String>{}; // member id → "12 stones · 3 on the Market · 1 sold" (ManiKVault data)
  String? _error;
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// "123", "GSM-123", "gsm000123" → GSM-000123 · anything else → username (a leading @ is dropped).
  static (String gsm, String username) _parse(String input) {
    final t = input.trim();
    final digits = RegExp(r'^(?:gsm[- ]?)?0*(\d{1,6})$', caseSensitive: false).firstMatch(t);
    if (digits != null) return ('GSM-${digits.group(1)!.padLeft(6, '0')}', '');
    return ('', t.startsWith('@') ? t.substring(1) : t);
  }

  Future<void> _find([String? value]) async {
    if (value != null) _search.text = value;
    final (gsm, user) = _parse(_search.text);
    if (gsm.isEmpty && user.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    Connection? conn;
    try {
      conn = await HqDb.open(Q.newestMembers.project);
      final r = await conn.execute(Q.personSql, parameters: [gsm, user]);
      _found = r.map((row) => row.toColumnMap()).toList();
    } catch (e) {
      _error = '$e';
    } finally {
      await conn?.close();
    }
    await _loadStones();
    if (mounted) setState(() => _searching = false);
  }

  /// Stone counts for the people found — only if ManiKVault data is connected.
  Future<void> _loadStones() async {
    _stones.clear();
    final ids = [for (final p in _found ?? const <Map<String, dynamic>>[]) '${p['member_id']}'];
    if (ids.isEmpty) return;
    final mkv = hqProjects.firstWhere((p) => p.id == 'mkv');
    if (!await KeyStore.isSet(mkv.id)) {
      for (final id in ids) {
        _stones[id] = 'ManiKVault data not connected yet';
      }
      return;
    }
    Connection? conn;
    try {
      conn = await HqDb.open(mkv);
      for (final id in ids) {
        final r = (await conn.execute(Q.personStonesSql, parameters: [id])).first.toColumnMap();
        _stones[id] = '${r['stones']} stones · ${r['on_market']} on the Market · ${r['sold']} sold '
            '(cloud only — vault stones on the phone aren\'t counted)';
      }
    } catch (e) {
      for (final id in ids) {
        _stones[id] = 'couldn\'t load: $e';
      }
    } finally {
      await conn?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'People',
      subtitle: 'Search by GSM ID (GSM-000123 or just 123) or username. No email, phone, chats or costs.',
      data: widget.data,
      queries: const [Q.newestMembers],
      body: () {
        final newest = widget.data.rows(Q.newestMembers);
        return [
          Row(children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _search,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'GSM ID or username'),
                onSubmitted: (_) => _find(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(onPressed: _searching ? null : _find, child: Text(_searching ? 'Searching…' : 'Search')),
          ]),
          const SizedBox(height: 16),
          if (_error != null) NoteBox(color: HqColors.bad, text: _error!),
          if (_found != null && _found!.isEmpty)
            Text('Nobody with that GSM ID or username.', style: jost(14, color: HqColors.muted)),
          if (_found != null) for (final p in _found!) _PersonCard(p: p, stones: _stones['${p['member_id']}']),
          if (newest != null) ...[
            const Heading('Newest members', note: 'Click a row to open that person.'),
            _NewestList(rows: newest, onOpen: (gsm) => _find(gsm)),
          ],
        ];
      },
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.p, this.stones});
  final Map<String, dynamic> p;
  final String? stones;

  @override
  Widget build(BuildContext context) {
    String s(String k) => p[k] == null || '${p[k]}'.isEmpty ? '–' : '${p[k]}';
    final adFree = p['ad_free_until'] as DateTime?;
    final signin = p['signin_type'] ?? p['provider'];
    final lines = <(String, String)>[
      ('Joined', fmtDateTime(p['created_at'] as DateTime?)),
      ('Signed up in',
          p['signup_app'] == null ? 'not recorded (older member)' : '${p['signup_app']} ${p['signup_version'] ?? ''}'),
      ('Signs in with', signin == null ? '–' : '$signin'),
      ('Apps opened', s('apps')),
      ('First app open', fmtDateTime(p['first_open'] as DateTime?)),
      ('Last seen',
          '${fmtAgo(p['last_seen_at'] as DateTime?)} · ${s('last_seen_app')} · ${s('last_seen_device')} · v${s('last_app_version')}'),
      ('App opens', s('login_count')),
      ('Tier', '${s('tier')}${p['verified'] == true ? ' · verified' : ''}'),
      ('Roles', s('roles')),
      ('Country', s('country')),
      ('Credits', '${fmtNum(p['balance'])} now · ${s('purchases')} purchases · ${s('spends')} spends'),
      ('Ad-free until', adFree == null || adFree.isBefore(DateTime.now()) ? '–' : fmtDateTime(adFree)),
      ('Vault plan', s('private_vault_plan')),
      ('Subscription', s('subscription_status')),
      ('Stones', stones ?? '…'),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(s('name'), style: jost(22, weight: 600)),
            Text(s('gemstok_id'), style: jost(14, color: HqColors.muted)),
            if (p['username'] != null) Text('@${p['username']}', style: jost(14, color: HqColors.muted)),
            if (p['is_deleted'] == true)
              Text('DELETED ${fmtDate(p['deleted_at'] as DateTime?)}', style: jost(13, weight: 600, color: HqColors.bad)),
          ]),
          const SizedBox(height: 14),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 150, child: Text(l.$1, style: jost(13, color: HqColors.muted))),
                Expanded(child: Text(l.$2, style: jost(14))),
              ]),
            ),
        ],
      ),
    );
  }
}

class _NewestList extends StatelessWidget {
  const _NewestList({required this.rows, required this.onOpen});
  final List<Map<String, dynamic>> rows;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        for (final r in rows)
          InkWell(
            onTap: () => onOpen('${r['gemstok_id']}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(children: [
                // fixed columns stay small; name + app share what's left, so a narrow window never overflows
                SizedBox(width: 100, child: Text('${r['gemstok_id']}', style: jost(13, color: HqColors.muted))),
                Expanded(flex: 3, child: Text('${r['name']}', style: jost(14), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Expanded(
                    flex: 2,
                    child: Text(
                        r['app'] == null ? '–' : '${r['app']}${(r['guessed'] as bool? ?? false) ? ' (guessed)' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: jost(13, color: HqColors.muted))),
                SizedBox(width: 100, child: Text(fmtDate(r['created_at'] as DateTime?), style: jost(13))),
                SizedBox(
                    width: 100,
                    child: Text('seen ${fmtAgo(r['last_seen_at'] as DateTime?)}',
                        textAlign: TextAlign.right, style: jost(13, color: HqColors.muted))),
              ]),
            ),
          ),
      ]),
    );
  }
}
