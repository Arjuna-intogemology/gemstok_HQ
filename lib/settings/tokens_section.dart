import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../app_theme.dart';
import '../servers/supabase_api.dart';
import 'key_store.dart';
import '../widgets/dispose_later.dart';

/// Settings → Supabase access tokens (two slots: your projects live in two Supabase accounts).
/// Make one at supabase.com → Account → Access Tokens. It can change projects, so HQ only ever
/// uses it for GET requests to five read-only addresses (servers/supabase_api.dart).
class TokensSection extends StatefulWidget {
  const TokensSection({super.key});

  @override
  State<TokensSection> createState() => _TokensSectionState();
}

class _TokensSectionState extends State<TokensSection> {
  static const _labels = {1: 'Account 1 (Gemstok account)', 2: 'Account 2 (IntoGemology account)'};
  final _set = <int, bool>{};
  final _check = <int, (bool, String)>{};
  final _checking = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final s in _labels.keys) {
      _set[s] = await KeyStore.hasToken(s);
    }
    if (mounted) setState(() {});
  }

  Future<void> _checkSlot(int slot) async {
    setState(() => _checking.add(slot));
    try {
      final token = await KeyStore.tokenForApi(slot);
      final list = await SupabaseApi.projects(token!);
      _check[slot] = (true, 'sees ${list.length} projects: ${list.map((p) => p['name']).join(', ')}');
    } catch (e) {
      _check[slot] = (false, '$e');
    }
    if (mounted) setState(() => _checking.remove(slot));
  }

  Future<void> _edit(int slot) async {
    final c = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_labels[slot]} — access token', style: jost(18, weight: 600)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'supabase.com → your account (top right) → Access Tokens → Generate new token, '
                'named "Gemstok HQ". HQ only reads with it.',
                style: jost(13, color: HqColors.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: const InputDecoration(labelText: 'Access token (starts with sbp_)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save to Keychain')),
        ],
      ),
    );
    if (saved == true && c.text.trim().isNotEmpty) {
      await KeyStore.saveToken(slot, c.text);
      await _load();
      await _checkSlot(slot);
    }
    disposeLater([c]);
  }

  Future<void> _show(int slot) async {
    bool ok = false;
    try {
      ok = await LocalAuthentication().authenticate(localizedReason: 'show the Supabase access token');
    } catch (_) {}
    if (!ok || !mounted) return;
    final t = await KeyStore.tokenForApi(slot);
    if (t == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        Timer(const Duration(seconds: 30), () {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        });
        return AlertDialog(
          title: Text('${_labels[slot]} — token', style: jost(18, weight: 600)),
          content: SelectableText(t, style: jost(14)),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: t)),
              child: const Text('Copy'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hide (auto in 30 s)')),
          ],
        );
      },
    );
  }

  Future<void> _remove(int slot) async {
    await KeyStore.removeToken(slot);
    _check.remove(slot);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      Text('Supabase access tokens', style: jost(18, weight: 600)),
      Text('For Servers: project status (Active / Paused), edge functions and logs. HQ only reads with them.',
          style: jost(13, color: HqColors.muted)),
      const SizedBox(height: 10),
      for (final slot in _labels.keys) _row(slot),
    ]);
  }

  Widget _row(int slot) {
    final set = _set[slot] ?? false;
    final check = _check[slot];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_labels[slot]!, style: jost(15, weight: 600)),
            Text(set ? 'Token: set' : 'Token: not set', style: jost(13, weight: 500)),
            if (_checking.contains(slot)) Text('Checking…', style: jost(13, color: HqColors.muted)),
            if (check != null && !_checking.contains(slot))
              Text(check.$2, style: jost(13, color: check.$1 ? HqColors.good : HqColors.bad)),
          ]),
        ),
        if (set) ...[
          OutlinedButton(onPressed: () => _checkSlot(slot), child: const Text('Check')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => _show(slot), child: const Text('Show')),
          const SizedBox(width: 8),
        ],
        OutlinedButton(onPressed: () => _edit(slot), child: Text(set ? 'Replace' : 'Add')),
        if (set) ...[
          const SizedBox(width: 8),
          TextButton(onPressed: () => _remove(slot), child: const Text('Remove')),
        ],
      ]),
    );
  }
}
