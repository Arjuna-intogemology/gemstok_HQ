import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/projects.dart';
import '../services/services_data.dart';
import '../settings/key_store.dart';

/// Settings → Recovery. HQ has no account to recover — what matters is:
///   1. getting back in (Touch ID / Mac password),
///   2. the keys (only in this Mac's Keychain) — which are set, and where each one comes from again,
///   3. the code and the files that live only on this Mac,
///   4. what to do if this Mac is lost or stolen (switch every key off).
/// Shows live status; never shows a key.
class RecoveryView extends StatefulWidget {
  const RecoveryView({super.key});

  @override
  State<RecoveryView> createState() => _RecoveryViewState();
}

class _RecoveryViewState extends State<RecoveryView> {
  final _set = <String, bool>{};
  String? _git; // "last commit 2 days ago · 3 files not committed"
  bool _gitOk = false;

  static String get _root => '${Platform.environment['HOME']}/Development/Gemstok/gemstok_hq';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final p in [...hqProjects, hqOperatorProject]) {
      _set['db:${p.id}'] = await KeyStore.isSet(p.id);
    }
    for (final slot in [1, 2]) {
      _set['token:$slot'] = await KeyStore.hasToken(slot);
    }
    for (final s in hqServices) {
      _set['svc:${s.id}'] = ServicesData.ready(s.id, await KeyStore.serviceFields(s.id));
    }
    try {
      final log = await Process.run('git', ['-C', _root, 'log', '-1', '--format=%cr']);
      final status = await Process.run('git', ['-C', _root, 'status', '--porcelain']);
      final ahead = await Process.run('git', ['-C', _root, 'rev-list', '--count', '@{u}..HEAD']);
      final changed = '${status.stdout}'.trim().isEmpty ? 0 : '${status.stdout}'.trim().split('\n').length;
      final notPushed = int.tryParse('${ahead.stdout}'.trim()) ?? 0;
      if (log.exitCode != 0) {
        _git = 'This folder is not in git — the code is NOT backed up.';
      } else {
        _gitOk = changed == 0 && notPushed == 0;
        _git = [
          'last commit ${'${log.stdout}'.trim()}',
          changed == 0 ? 'nothing uncommitted' : '$changed file${changed == 1 ? '' : 's'} not committed',
          if (ahead.exitCode == 0) notPushed == 0 ? 'everything pushed to GitHub' : '$notPushed commit${notPushed == 1 ? '' : 's'} not pushed',
          if (ahead.exitCode != 0) 'no GitHub copy linked',
        ].join(' · ');
      }
    } catch (e) {
      _git = 'Couldn\'t check git: $e';
    }
    if (mounted) setState(() {});
  }

  Widget _status(String key) {
    final ok = _set[key];
    return Text(ok == null ? '…' : (ok ? 'set' : 'not set'),
        style: jost(13, weight: 600, color: ok == true ? HqColors.good : HqColors.muted));
  }

  Widget _section(String title, String intro, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HqColors.surface,
          border: Border.all(color: HqColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: jost(17, weight: 600)),
          if (intro.isNotEmpty) ...[const SizedBox(height: 4), Text(intro, style: jost(13, color: HqColors.muted))],
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  Widget _keyRow(String key, String name, String getAgain) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 70, child: _status(key)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: jost(14, weight: 500)),
              Text(getAgain, style: jost(12, color: HqColors.muted)),
            ]),
          ),
        ]),
      );

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 26, child: Text(n, style: jost(13, weight: 600, color: HqColors.accent))),
          Expanded(child: Text(text, style: jost(13))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('HQ has no online account. Everything needed to get back in is listed here — with what is set '
              'right now. No key is ever shown on this page.', style: jost(14, color: HqColors.muted)),
        ),
        TextButton(onPressed: _load, child: const Text('Check again')),
      ]),
      const SizedBox(height: 12),

      _section('1 · Can\'t get in', '', [
        _step('•', 'Touch ID doesn\'t read your finger → choose "Use Password" and type your Mac login password.'),
        _step('•', 'macOS asks for the Keychain password → that is also your Mac login password. Choose "Always Allow".'),
        _step('•', 'HQ won\'t open at all → Terminal: cd ~/Development/Gemstok/gemstok_hq  then  ./tool/install.sh'),
      ]),

      _section('2 · Code and files', 'The code is safe only when it is committed AND pushed to GitHub.', [
        Row(children: [
          Icon(_gitOk ? Icons.check_circle : Icons.warning_amber_rounded,
              size: 18, color: _gitOk ? HqColors.good : HqColors.warn),
          const SizedBox(width: 8),
          Expanded(child: Text(_git ?? 'Checking…', style: jost(14, weight: 500))),
        ]),
        const SizedBox(height: 8),
        _step('•', 'Back up now:  git add -A  →  git commit -m "…"  →  git push   (in ~/Development/Gemstok/gemstok_hq)'),
        _step('•', 'On a new Mac:  git clone https://github.com/<your-account>/gemstok_hq.git  into ~/Development/Gemstok/'),
        _step('•', 'NOT in git, only on this Mac (Time Machine keeps them): ask/ (your questions), ideas/ (users\' ideas), '
            'leads/campaigns.json (campaigns, people), the action log (~/Library/Application Support/gemstok_hq/).'),
        _step('•', 'The project must stay at ~/Development/Gemstok/gemstok_hq — HQ saves its files there. '
            'If it moves (e.g. to the Desktop), HQ starts empty folders in the old place.'),
      ]),

      _section('3 · Keys (only in this Mac\'s Keychain)',
          'On a new Mac or after the Keychain is lost, add each one again in Settings. Where to get it back:', [
        for (final p in hqProjects)
          _keyRow('db:${p.id}', '${p.name} — hq_reader',
              'Pooler host: Supabase → ${p.name} → Connect → Session pooler. Password: Passwords app → "Gemstok HQ · hq_reader · ${p.name}". '
                  'Lost it? Make a new one: SQL Editor → alter role hq_reader with password \'…\'  (20+ characters).'),
        _keyRow('db:${hqOperatorProject.id}', 'Actions login — hq_operator (Gemstok)',
            'Passwords app → "Gemstok HQ · hq_operator · Gemstok". Lost it? alter role hq_operator with password \'…\' in Gemstok.'),
        _keyRow('token:1', 'Supabase access token 1 (Gemstok account)', 'supabase.com/dashboard/account/tokens → Generate new token.'),
        _keyRow('token:2', 'Supabase access token 2 (IntoGemology account)', 'Same, signed in with the other Supabase account.'),
        for (final s in hqServices) _keyRow('svc:${s.id}', s.name, s.how),
      ]),

      _section('4 · If this Mac is lost or stolen',
          'HQ is locked behind Touch ID and the Mac password, but switch every key off anyway — from another computer:', [
        _step('1', 'Each Supabase database → SQL Editor:  alter role hq_reader with password \'<new long password>\';  '
            'and in Gemstok also  alter role hq_operator with password \'<new>\';'),
        _step('2', 'supabase.com → Account → Access Tokens → delete "Gemstok HQ" (both Supabase accounts).'),
        _step('3', 'Cloudflare → My Profile → API Tokens → Gemstok HQ → Delete.'),
        _step('4', 'App Store Connect → Users and Access → Integrations → revoke the "Gemstok HQ" key.'),
        _step('5', 'Google Cloud → IAM → Service Accounts → gemstok-hq-reader → Keys → delete the key.'),
        _step('6', 'myaccount.google.com → Security → Third-party access → remove "Gemstok HQ" (AdMob).'),
        _step('7', 'Change the blog-admin password (it signs in to all 5 blogs).'),
        _step('8', 'Then on the new Mac: clone from GitHub (section 2) and add new keys (section 3).'),
      ]),
    ]);
  }
}
