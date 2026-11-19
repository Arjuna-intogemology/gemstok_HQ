import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../app_theme.dart';
import '../db/hq_db.dart';
import '../db/projects.dart';
import '../services/services_data.dart';
import '../help/help_view.dart';
import '../help/recovery_view.dart';
import '../widgets/screen_frame.dart';
import 'key_store.dart';
import 'services_section.dart';
import 'tokens_section.dart';

/// Keys screen. Shows only "set / not set" and the (non-secret) pooler host.
/// Passwords are typed here, saved to the Keychain, and never shown again.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});
  final ServicesData services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _isSet = <String, bool>{};
  final _hosts = <String, String?>{};
  final _checks = <String, CheckResult>{};
  final _checking = <String>{};
  bool? _sslVerified;
  String? _keychainError;
  String _tab = 'keys'; // keys · help · recovery

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await KeyStore.migrateOldItems(hqProjects.map((p) => p.id));
      for (final p in [...hqProjects, hqOperatorProject]) {
        _isSet[p.id] = await KeyStore.isSet(p.id);
        _hosts[p.id] = await KeyStore.host(p.id);
      }
      _keychainError = null;
    } catch (e) {
      _keychainError = 'Keychain not available: $e';
    }
    _sslVerified = (await HqDb.sslSetup()).verified;
    if (mounted) setState(() {});
  }

  Future<void> _check(HqProject p) async {
    setState(() => _checking.add(p.id));
    final r = await HqDb.check(p);
    if (!mounted) return;
    setState(() {
      _checks[p.id] = r;
      _checking.remove(p.id);
    });
  }

  Future<void> _edit(HqProject p) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _KeyDialog(project: p, currentHost: _hosts[p.id]),
    );
    if (saved == true) {
      _checks.remove(p.id);
      await _load();
      await _check(p);
    }
  }

  /// Show the saved password: asks Touch ID again, hides after 30 s.
  Future<void> _show(HqProject p) async {
    bool ok = false;
    try {
      ok = await LocalAuthentication().authenticate(localizedReason: 'show the ${p.name} ${p.role} password');
    } catch (_) {}
    if (!ok || !mounted) return;
    final pw = await KeyStore.passwordToShow(p.id);
    if (pw == null || !mounted) return;
    await showDialog<void>(context: context, builder: (_) => _ShowPasswordDialog(project: p, password: pw));
  }

  Future<void> _remove(HqProject p) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.name} key?', style: jost(18, weight: 600)),
        content: Text('HQ forgets the host and password for ${p.name} on this Mac. '
            'The database is not changed.', style: jost(14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (sure == true) {
      await KeyStore.remove(p.id);
      _checks.remove(p.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text('Settings', style: jost(26, weight: 600)),
        const SizedBox(height: 10),
        Choice<String>(
          options: const {'keys': 'Keys & logins', 'help': 'How to use HQ', 'recovery': 'Recovery'},
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
        const SizedBox(height: 16),
        if (_tab == 'help') const HelpView(),
        if (_tab == 'recovery') const RecoveryView(),
        if (_tab == 'keys') ..._keys(),
      ],
    );
  }

  List<Widget> _keys() {
    return [
        Text('Each project needs its hq_reader pooler host + password. Stored only in this Mac\'s Keychain.',
            style: jost(14, color: HqColors.muted)),
        const SizedBox(height: 12),
        if (_sslVerified != null)
          _Note(
            color: _sslVerified! ? HqColors.good : HqColors.warn,
            text: _sslVerified!
                ? 'SSL: encrypted and verified against the Supabase CA certificate.'
                : 'SSL: encrypted. The server certificate isn\'t verified yet — macOS won\'t accept Supabase\'s root '
                    'certificate added by an app (tried 13 Nov), so verification needs "pinning" (in TODO-VIP).',
          ),
        if (_keychainError != null) _Note(color: HqColors.bad, text: _keychainError!),
        const SizedBox(height: 20),
        for (final p in hqProjects) _row(p),
        const TokensSection(),
        ServicesSection(services: widget.services),
        const SizedBox(height: 18),
        Text('Actions login', style: jost(18, weight: 600)),
        Text('Only for changes HQ is allowed to make (app switches, agent codes). Gemstok\'s pooler host + the hq_operator '
            'password from the app_config SQL.', style: jost(13, color: HqColors.muted)),
        const SizedBox(height: 10),
        _row(hqOperatorProject),
    ];
  }

  Widget _row(HqProject p) {
    final set = _isSet[p.id] ?? false;
    final check = _checks[p.id];
    final checking = _checking.contains(p.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(p.name, style: jost(16, weight: 600)),
                    Text(p.ref, style: jost(12, color: HqColors.muted)),
                    if (!p.inStep1) Text('later', style: jost(12, color: HqColors.muted, weight: 500)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(p.holds, style: jost(13, color: HqColors.muted)),
                const SizedBox(height: 8),
                Text(
                  set ? 'Key: set · ${_hosts[p.id] ?? ''}' : 'Key: not set',
                  style: jost(13, weight: 500, color: set ? HqColors.ink : HqColors.muted),
                ),
                if (checking) Text('Checking…', style: jost(13, color: HqColors.muted)),
                if (!checking && check != null && !check.notSet)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: check.ok ? HqColors.good : HqColors.bad,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(check.text, style: jost(13))),
                    ]),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (set)
            OutlinedButton(onPressed: checking ? null : () => _check(p), child: const Text('Check')),
          const SizedBox(width: 8),
          if (set) ...[
            OutlinedButton(onPressed: () => _show(p), child: const Text('Show')),
            const SizedBox(width: 8),
          ],
          OutlinedButton(onPressed: () => _edit(p), child: Text(set ? 'Replace' : 'Add')),
          if (set) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: () => _remove(p), child: const Text('Remove')),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: jost(13)),
      );
}

/// Type host + password. The password field is hidden, has no autocorrect/suggestions,
/// and is wiped from memory as soon as it is saved.
class _KeyDialog extends StatefulWidget {
  const _KeyDialog({required this.project, this.currentHost});
  final HqProject project;
  final String? currentHost;

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  late final _host = TextEditingController(text: widget.currentHost ?? '');
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    _host.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final host = _host.text.trim().toLowerCase();
    if (!KeyStore.poolerHost.hasMatch(host)) {
      setState(() => _error = 'Use the pooler host, e.g. aws-0-ap-south-1.pooler.supabase.com');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Type ${widget.project.role}\'s password.');
      return;
    }
    try {
      await KeyStore.save(widget.project.id, host: host, password: _password.text);
    } catch (e) {
      setState(() => _error = 'Keychain refused: $e');
      return;
    }
    _password.clear();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    return AlertDialog(
      title: Text('${p.name} — read-only key', style: jost(18, weight: 600)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Only after ${p.name}\'s ${p.role} SQL has been run.',
                style: jost(13, weight: 600, color: HqColors.warn)),
            const SizedBox(height: 6),
            Text('Host: Supabase → ${p.name} → Connect → Session pooler → the address ending in '
                'pooler.supabase.com.\n'
                'Password: the ${p.role} password you chose when running that SQL — '
                'NEVER the database (postgres) password. HQ logs in as ${p.readerUser}.',
                style: jost(13, color: HqColors.muted)),
            const SizedBox(height: 14),
            TextField(
              controller: _host,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Pooler host'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(labelText: '${p.role} password (not the postgres one)'),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: jost(13, color: HqColors.bad)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save to Keychain')),
      ],
    );
  }
}

/// The password, visible for 30 seconds. Copy puts it on the clipboard and clears it again after 30 s.
class _ShowPasswordDialog extends StatefulWidget {
  const _ShowPasswordDialog({required this.project, required this.password});
  final HqProject project;
  final String password;

  @override
  State<_ShowPasswordDialog> createState() => _ShowPasswordDialogState();
}

class _ShowPasswordDialogState extends State<_ShowPasswordDialog> {
  int _left = 30;
  Timer? _tick;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 1) {
        _close();
      } else {
        setState(() => _left--);
      }
    });
  }

  Future<void> _close() async {
    _tick?.cancel();
    if (_copied) {
      final now = await Clipboard.getData(Clipboard.kTextPlain);
      if (now?.text == widget.password) await Clipboard.setData(const ClipboardData(text: ''));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.project.name} · ${widget.project.role} password', style: jost(18, weight: 600)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(widget.password, style: jost(18, weight: 500)),
          const SizedBox(height: 10),
          Text('Hides in $_left s${_copied ? ' · copied (clipboard clears when this closes)' : ''}',
              style: jost(12, color: HqColors.muted)),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.password));
              setState(() => _copied = true);
            },
            child: const Text('Copy'),
          ),
          FilledButton(onPressed: _close, child: const Text('Hide')),
        ],
      );
}
