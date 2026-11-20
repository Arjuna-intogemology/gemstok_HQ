import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/dispose_later.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import 'renewals_store.dart';
import 'zoho_login.dart';
import 'zoho_vault.dart';

Color renewalColor(int? daysLeft) => daysLeft == null
    ? HqColors.muted
    : daysLeft < 0
        ? HqColors.bad
        : daysLeft <= 14
            ? HqColors.bad
            : daysLeft <= RenewalStore.warnDays
                ? HqColors.warn
                : HqColors.good;

String renewalText(Renewal r) {
  final d = r.daysLeft;
  if (d == null) return 'date not set';
  if (d < 0) return 'EXPIRED ${-d} days ago';
  if (d == 0) return 'expires TODAY';
  return 'expires in $d days · ${fmtDate(r.expires)}';
}

/// Renewals: everything that expires and has to be renewed by hand, with a countdown.
/// Today shows a warning 30 days before.
class RenewalsScreen extends StatefulWidget {
  const RenewalsScreen({super.key});

  @override
  State<RenewalsScreen> createState() => _RenewalsScreenState();
}

class _RenewalsScreenState extends State<RenewalsScreen> {
  List<Renewal> _list = [];
  String? _error;
  String? _info;

  /// Mailboxes that have a Zoho password saved in the Keychain (addresses only — never the passwords).
  Set<String> _pwSet = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadPw();
  }

  Future<void> _loadPw() async {
    try {
      final s = await ZohoVault.addressesSet();
      if (mounted) setState(() => _pwSet = s);
    } catch (_) {}
  }

  /// Type the password here yourself (never in a chat). Saved to the Keychain; shown only as "set".
  Future<void> _setPassword(String address) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Zoho password — $address', style: jost(18, weight: 600)),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: c,
              obscureText: true,
              autofocus: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
            Text('Kept in this Mac\'s Keychain only (not iCloud). HQ uses it only to fill Zoho\'s sign-in page.',
                style: jost(12, color: HqColors.muted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final pw = c.text;
    disposeLater([c]);
    if (ok != true || pw.isEmpty) return;
    try {
      await ZohoVault.set(address, pw);
      if (mounted) setState(() => _info = 'Password saved for $address (Keychain).');
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t save to the Keychain: $e');
    }
    await _loadPw();
  }

  Future<void> _removePassword(String address) async {
    await ZohoVault.remove(address);
    if (mounted) setState(() => _info = 'Password removed for $address.');
    await _loadPw();
  }

  Future<void> _load() async {
    try {
      final l = await RenewalStore.load();
      l.sort((a, b) => (a.daysLeft ?? 99999).compareTo(b.daysLeft ?? 99999));
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t read renewals.json: $e');
    }
  }

  Future<void> _save() async {
    try {
      await RenewalStore.save(_list);
    } catch (e) {
      _error = 'Couldn\'t save: $e';
    }
    await _load();
  }

  Future<void> _renewedToday(Renewal r) async {
    r.made = DateTime.now();
    r.expiresOverride = null;
    _info = '${r.name}: renewed today — next ${fmtDate(r.expires)}.';
    await _save();
  }

  Future<void> _pickMade(Renewal r) async {
    final d = await showDatePicker(
      context: context,
      initialDate: r.made ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: 'When was it last made / renewed?',
    );
    if (d == null) return;
    r.made = d;
    r.expiresOverride = null;
    await _save();
  }

  /// Apple client secret: read its real dates from the secret itself. Decoded here only — never saved or sent.
  Future<void> _readSecret(Renewal r) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Read the date from the secret', style: jost(18, weight: 600)),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Paste the Apple client secret (the long text starting "eyJ…"). HQ only reads the dates inside it — '
                'it is not saved anywhere and never leaves this Mac.',
                style: jost(13, color: HqColors.muted)),
            const SizedBox(height: 10),
            TextField(controller: c, obscureText: true, decoration: const InputDecoration(labelText: 'Client secret')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Read dates')),
        ],
      ),
    );
    final text = c.text.trim();
    disposeLater([c]);
    if (ok != true || text.isEmpty) return;
    try {
      final parts = text.split('.');
      if (parts.length != 3) throw const FormatException('not a JWT');
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
      DateTime? at(String k) =>
          payload[k] is num ? DateTime.fromMillisecondsSinceEpoch((payload[k] as num).toInt() * 1000) : null;
      final exp = at('exp');
      if (exp == null) throw const FormatException('no expiry inside');
      r.made = at('iat') ?? r.made;
      r.expiresOverride = exp;
      _info = 'Read from the secret: made ${fmtDate(r.made)}, expires ${fmtDate(exp)}.';
      await _save();
    } catch (e) {
      setState(() => _error = 'That doesn\'t look like the Apple client secret ($e).');
    }
  }

  Future<void> _edit(Renewal? r) async {
    final name = TextEditingController(text: r?.name ?? '');
    final what = TextEditingController(text: r?.what ?? '');
    final days = TextEditingController(text: r == null ? '365' : '${r.lifetimeDays}');
    final how = TextEditingController(text: r?.howTo ?? '');
    final notes = TextEditingController(text: r?.notes ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r == null ? 'Add something that expires' : 'Edit', style: jost(18, weight: 600)),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name, e.g. gemstok.com domain')),
            const SizedBox(height: 8),
            TextField(controller: what, decoration: const InputDecoration(labelText: 'What breaks when it expires')),
            const SizedBox(height: 8),
            TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Lasts how many days (180 = 6 months, 365 = 1 year)')),
            const SizedBox(height: 8),
            TextField(controller: how, decoration: const InputDecoration(labelText: 'How to renew (where the steps are)')),
            const SizedBox(height: 8),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
          ]),
        ),
        actions: [
          if (r != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: HqColors.bad),
              onPressed: () {
                _list.remove(r);
                Navigator.pop(ctx, true);
              },
              child: const Text('Remove'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && (r == null || _list.contains(r))) {
      final x = r ??
          Renewal(
              id: '${switch (_group) { 'domains' => 'domain-', 'nipo' => 'nipo-', 'email' => 'email-', _ => '' }}${RenewalStore.newId()}',
              name: switch (_group) { 'domains' => 'Domain — ', 'nipo' => 'NIPO trademark — ', 'email' => 'Email — ', _ => '' },
              what: _group == 'email' ? 'Zoho clears a free mailbox after 120 days without a login.' : '',
              howTo: _group == 'email' ? 'Press "Log in to Zoho" here (or sign in on the Zoho Mail phone app).' : '',
              lifetimeDays: switch (_group) { 'nipo' => 0, 'email' => 120, _ => 365 });
      x
        ..name = name.text.trim()
        ..what = what.text.trim()
        ..lifetimeDays = int.tryParse(days.text.trim()) ?? x.lifetimeDays
        ..howTo = how.text.trim()
        ..notes = notes.text.trim();
      if (r == null && x.name.isNotEmpty) _list.add(x);
    }
    disposeLater([name, what, days, how, notes]);
    if (ok == true) await _save();
  }

  /// Sub-pages: keys & memberships · domains · NIPO trademarks (from the id or name).
  String _group = 'keys';
  static const _groups = {
    'keys': 'Keys & memberships',
    'domains': 'Domains',
    'email': 'Email',
    'nipo': 'NIPO trademarks',
  };

  static String groupOf(Renewal r) {
    final id = r.id.toLowerCase(), name = r.name.toLowerCase();
    if (id.startsWith('domain-') || name.startsWith('domain')) return 'domains';
    if (id.startsWith('nipo-') || name.contains('nipo')) return 'nipo';
    if (id.startsWith('email-') || name.startsWith('email')) return 'email';
    return 'keys';
  }

  /// "Email — hello@quvlet.com" → hello@quvlet.com
  static String? addressOf(Renewal r) => RegExp(r'[\w.+-]+@[\w.-]+\.[a-z]{2,}', caseSensitive: false).firstMatch(r.name)?.group(0);

  /// Opens Zoho inside HQ; when the inbox opens, the mailbox is marked "logged in today".
  Future<bool> _zoho(Renewal r) async {
    final address = addressOf(r) ?? r.name;
    final ok = await ZohoLogin.open(context, address);
    if (ok) {
      r.made = DateTime.now();
      await _save();
      if (mounted) setState(() => _info = '✓ $address — logged in today. Next one due in ${r.lifetimeDays} days.');
    }
    return ok;
  }

  /// One after another: every mailbox that is due (or has no date), oldest first. Stops on Cancel.
  Future<void> _zohoAll() async {
    final todo = _list.where((r) => groupOf(r) == 'email' && (r.daysLeft == null || r.daysLeft! <= RenewalStore.warnDays)).toList()
      ..sort((a, b) => (a.daysLeft ?? -99999).compareTo(b.daysLeft ?? -99999));
    var done = 0;
    for (final r in todo) {
      if (!mounted) return;
      if (!await _zoho(r)) break;
      done++;
    }
    if (mounted) setState(() => _info = 'Zoho logins done: $done of ${todo.length}.');
  }

  @override
  Widget build(BuildContext context) {
    final shown = _list.where((r) => groupOf(r) == _group).toList();
    String label(String g) {
      final inG = _list.where((r) => groupOf(r) == g);
      final due = inG.where((r) => r.daysLeft != null && r.daysLeft! <= RenewalStore.warnDays).length;
      return '${_groups[g]} (${inG.length})${due > 0 ? ' · $due due' : ''}';
    }

    return ListView(padding: const EdgeInsets.all(32), children: [
      Row(children: [
        Expanded(child: Text('Renewals', style: jost(26, weight: 600))),
        FilledButton.tonal(onPressed: () => _edit(null), child: const Text('+ Add')),
      ]),
      const SizedBox(height: 4),
      Text('Keys, memberships, domains and NIPO trademarks that expire. Today warns you ${RenewalStore.warnDays} days before. '
          'Only dates are kept here (renewals/renewals.json) — never the keys.',
          style: jost(14, color: HqColors.muted)),
      const SizedBox(height: 16),
      if (_error != null) NoteBox(color: HqColors.bad, text: _error!),
      if (_info != null) NoteBox(color: HqColors.good, text: _info!),
      Choice<String>(
        options: {for (final g in _groups.keys) g: label(g)},
        value: _group,
        onChanged: (v) => setState(() => _group = v),
      ),
      const SizedBox(height: 14),
      if (_group == 'email') ...[
        Row(children: [
          FilledButton.icon(
            onPressed: _zohoAll,
            icon: const Icon(Icons.login, size: 18),
            label: Text('Log in to all that are due '
                '(${_list.where((r) => groupOf(r) == 'email' && (r.daysLeft == null || r.daysLeft! <= RenewalStore.warnDays)).length})'),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text('Opens Zoho inside HQ one mailbox at a time. Sign in; when the inbox opens HQ ticks it and moves on. '
                'Saved passwords (Keychain) are filled in for you; 2-step codes you type.',
                style: jost(12, color: HqColors.muted)),
          ),
        ]),
        const SizedBox(height: 14),
      ],
      if (shown.isEmpty) Text('Nothing here yet — "+ Add".', style: jost(13, color: HqColors.muted)),
      for (final r in shown) _row(r),
    ]);
  }

  Widget _row(Renewal r) {
    final color = renewalColor(r.daysLeft);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: r.daysLeft != null && r.daysLeft! <= RenewalStore.warnDays ? color : HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(r.name, style: jost(16, weight: 600))),
          Text(renewalText(r), style: jost(14, weight: 600, color: color)),
        ]),
        const SizedBox(height: 4),
        Text(r.what, style: jost(13)),
        const SizedBox(height: 4),
        Text(
            [
              r.lifetimeDays > 0 ? 'lasts ${r.lifetimeDays} days' : 'no fixed lifetime',
              r.made == null ? 'last made: not set' : 'last made ${fmtDate(r.made)}',
            ].join(' · '),
            style: jost(12, color: HqColors.muted)),
        if (r.howTo.isNotEmpty) Text('How: ${r.howTo}', style: jost(12, color: HqColors.muted)),
        if (r.notes.isNotEmpty) Text(r.notes, style: jost(12, color: HqColors.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (groupOf(r) == 'email' && addressOf(r) != null)
            FilledButton.icon(
              onPressed: () => _zoho(r),
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Log in to Zoho'),
            ),
          if (groupOf(r) == 'email' && addressOf(r) != null) ...[
            OutlinedButton(
              onPressed: () => _setPassword(addressOf(r)!),
              child: Text(_pwSet.contains(addressOf(r)!.toLowerCase()) ? 'Password: set · change' : 'Password: not set · set'),
            ),
            if (_pwSet.contains(addressOf(r)!.toLowerCase()))
              TextButton(onPressed: () => _removePassword(addressOf(r)!), child: const Text('Remove password')),
          ],
          if (groupOf(r) == 'email')
            OutlinedButton(onPressed: () => _renewedToday(r), child: const Text('Logged in on my phone today'))
          else
            FilledButton(onPressed: () => _renewedToday(r), child: const Text('Renewed today')),
          OutlinedButton(onPressed: () => _pickMade(r), child: const Text('Set the date it was made…')),
          if (r.id == 'apple-signin-secret')
            OutlinedButton(onPressed: () => _readSecret(r), child: const Text('Read the date from the secret…')),
          TextButton(onPressed: () => _edit(r), child: const Text('Edit')),
        ]),
      ]),
    );
  }
}

/// For Today: a warning box listing everything that expires within 30 days (or has expired / has no date).
class RenewalsBanner extends StatefulWidget {
  const RenewalsBanner({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<RenewalsBanner> createState() => _RenewalsBannerState();
}

class _RenewalsBannerState extends State<RenewalsBanner> {
  List<Renewal> _due = [];
  int _noDate = 0;

  @override
  void initState() {
    super.initState();
    RenewalStore.load().then((l) {
      if (!mounted) return;
      setState(() {
        _due = [for (final r in l) if (r.daysLeft != null && r.daysLeft! <= RenewalStore.warnDays) r]
          ..sort((a, b) => a.daysLeft!.compareTo(b.daysLeft!));
        _noDate = l.where((r) => r.daysLeft == null && r.lifetimeDays > 0).length;
      });
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_due.isEmpty && _noDate == 0) return const SizedBox.shrink();
    final urgent = _due.any((r) => r.daysLeft! <= 14);
    return InkWell(
      onTap: widget.onOpen,
      borderRadius: BorderRadius.circular(8),
      child: NoteBox(
        color: _due.isEmpty ? HqColors.muted : (urgent ? HqColors.bad : HqColors.warn),
        text: [
          for (final r in _due) '${r.name} — ${renewalText(r)}',
          if (_noDate > 0) '$_noDate renewal date${_noDate == 1 ? '' : 's'} not set yet',
          'Open Renewals →',
        ].join('\n'),
      ),
    );
  }
}
