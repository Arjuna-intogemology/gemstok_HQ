import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/services_data.dart';
import 'key_store.dart';
import '../widgets/dispose_later.dart';

/// Settings → Other services: Cloudflare, App Store Connect, Google Play, AdMob.
/// Keys go straight into the Keychain. HQ shows only "set / not set" per field — never the key.
class ServicesSection extends StatefulWidget {
  const ServicesSection({super.key, required this.services});
  final ServicesData services;

  @override
  State<ServicesSection> createState() => _ServicesSectionState();
}

class _ServicesSectionState extends State<ServicesSection> {
  final _fields = <String, Map<String, String>>{};
  String? _signingIn;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final s in hqServices) {
      _fields[s.id] = await KeyStore.serviceFields(s.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _edit(ServiceInfo s) async {
    final have = _fields[s.id] ?? const {};
    final c = {for (final f in s.fields) f.key: TextEditingController()};
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.name} — keys', style: jost(18, weight: 600)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.how, style: jost(13, color: HqColors.muted)),
              const SizedBox(height: 6),
              Text('Leave a box empty to keep what is already saved.', style: jost(12, color: HqColors.muted)),
              for (final f in s.fields) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: c[f.key],
                  obscureText: f.secret && !f.multiline, // long keys stay readable while you paste them
                  minLines: f.multiline ? 4 : 1,
                  maxLines: f.multiline ? 6 : 1,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  decoration: InputDecoration(
                    labelText: f.label,
                    helperText: (have[f.key] ?? '').isNotEmpty ? 'saved — paste only to replace' : null,
                  ),
                ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save to Keychain')),
        ],
      ),
    );
    if (saved == true) {
      await KeyStore.saveServiceFields(s.id, {for (final e in c.entries) e.key: e.value.text});
      await _load();
      await widget.services.refresh(s.id);
    }
    disposeLater(c.values);
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = 'Your browser opened — choose your AdMob Google account and allow access.');
    try {
      await widget.services.admobSignIn();
      _signingIn = null;
    } catch (e) {
      _signingIn = 'Sign-in failed: $e';
    }
    await _load();
  }

  Future<void> _remove(ServiceInfo s) async {
    await KeyStore.removeService(s.id);
    await _load();
    await widget.services.refresh(s.id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.services,
        builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 18),
          Text('Other services', style: jost(18, weight: 600)),
          Text('Read-only keys for store numbers, ads and website visits. Loaded every hour while HQ is open.',
              style: jost(13, color: HqColors.muted)),
          const SizedBox(height: 10),
          for (final s in hqServices) _row(s),
        ]),
      );

  Widget _row(ServiceInfo s) {
    final f = _fields[s.id] ?? const {};
    final st = widget.services.state[s.id]!;
    final anySet = f.isNotEmpty;
    final status = <String>[
      for (final x in s.fields) '${x.label.split(' (').first}: ${(f[x.key] ?? '').isNotEmpty ? 'set' : (x.optional ? 'default' : 'not set')}',
      if (s.id == 'admob') 'Google sign-in: ${(f['refresh_token'] ?? '').isNotEmpty ? 'done' : 'not yet'}',
    ];
    final (String text, Color color) = st.loading
        ? ('Loading…', HqColors.muted)
        : st.error != null
            ? (st.error!, HqColors.bad)
            : st.loadedAt != null
                ? ('Working — loaded ${TimeOfDay.fromDateTime(st.loadedAt!).format(context)}', HqColors.good)
                : ('', HqColors.muted);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: jost(15, weight: 600)),
            Text(s.shows, style: jost(12, color: HqColors.muted)),
            const SizedBox(height: 4),
            Text(status.join(' · '), style: jost(13, weight: 500)),
            if (text.isNotEmpty) Text(text, style: jost(13, color: color)),
            if (s.id == 'admob' && _signingIn != null) Text(_signingIn!, style: jost(13, color: HqColors.warn)),
          ]),
        ),
        const SizedBox(width: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (s.id == 'admob' && (f['client_id'] ?? '').isNotEmpty && (f['client_secret'] ?? '').isNotEmpty)
            OutlinedButton(onPressed: _signIn, child: const Text('Sign in with Google')),
          if (ServicesData.ready(s.id, f))
            OutlinedButton(onPressed: () => widget.services.refresh(s.id), child: const Text('Check')),
          OutlinedButton(onPressed: () => _edit(s), child: Text(anySet ? 'Replace' : 'Add')),
          if (anySet) TextButton(onPressed: () => _remove(s), child: const Text('Remove')),
        ]),
      ]),
    );
  }
}
