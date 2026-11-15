import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:postgres/postgres.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/hq_db.dart';
import '../db/projects.dart';
import '../db/queries.dart';
import '../settings/key_store.dart';
import '../widgets/format.dart';
import 'action_log.dart';

/// Servers → App switches: maintenance on/off (+ message) and minimum app version per app.
/// Reading: hq_reader (Q.appConfig). Changing: ONLY through
///   confirm screen that says exactly what happens → Touch ID → hq_operator → hq.set_maintenance /
///   hq.set_min_version → a line in the action log.
class MaintenanceSection extends StatefulWidget {
  const MaintenanceSection({super.key, required this.data});
  final HqData data;

  @override
  State<MaintenanceSection> createState() => _MaintenanceSectionState();
}

class _MaintenanceSectionState extends State<MaintenanceSection> {
  static const _names = {'manikvault': 'ManiKVault', 'gem_broker': 'Gem Broker', 'quvlet': 'Quvlet'};
  List<Map<String, dynamic>> _log = [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.data.use(const [Q.appConfig]);
    _loadLog();
  }

  Future<void> _loadLog() async {
    final l = await ActionLog.recent(limit: 8);
    if (mounted) setState(() => _log = l);
  }

  /// confirm → Touch ID → run as hq_operator → log → reload.
  Future<void> _act({
    required String title,
    required String whatHappens,
    required String action,
    required Map<String, Object?> details,
    required String sql,
    required List<Object?> params,
  }) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: jost(18, weight: 600)),
        content: SizedBox(
          width: 460,
          child: Text('$whatHappens\n\nThe apps don\'t read this switch yet (planned separately), so for now it '
              'changes only the setting. Touch ID is asked next; the change is written to HQ\'s action log.',
              style: jost(14)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, do it')),
        ],
      ),
    );
    if (sure != true) return;
    bool touched = false;
    try {
      touched = await LocalAuthentication().authenticate(localizedReason: title.toLowerCase());
    } catch (_) {}
    if (!touched) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    Connection? conn;
    try {
      if (!await KeyStore.isSet(hqOperatorProject.id)) {
        throw const HqDbError('Add the Actions login (hq_operator) in Settings first.');
      }
      conn = await HqDb.open(hqOperatorProject); // refuses anything but hq_operator
      await conn.execute(sql, parameters: params);
      await ActionLog.write(action, details, ok: true);
    } catch (e) {
      _error = '$e';
      await ActionLog.write(action, details, ok: false, error: '$e');
    } finally {
      await conn?.close();
    }
    await widget.data.refresh(const [Q.appConfig]);
    await _loadLog();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggle(Map<String, dynamic> row) async {
    final app = row['app'] as String;
    final on = !(row['maintenance'] as bool? ?? false);
    String message = (row['message'] as String?) ?? '';
    if (on) {
      final c = TextEditingController(text: message.isEmpty ? 'We\'re improving things — back soon.' : message);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Message people will see', style: jost(18, weight: 600)),
          content: SizedBox(width: 460, child: TextField(controller: c, maxLength: 300, maxLines: 3)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Next')),
          ],
        ),
      );
      message = c.text.trim();
      c.dispose();
      if (ok != true) return;
    }
    await _act(
      title: '${on ? 'Turn ON' : 'Turn OFF'} maintenance for ${_names[app] ?? app}',
      whatHappens: on
          ? 'Sets ${_names[app] ?? app} to MAINTENANCE with the message:\n"$message"'
          : 'Sets ${_names[app] ?? app} back to normal (maintenance off, message cleared).',
      action: 'set_maintenance',
      details: {'app': app, 'on': on, 'message': on ? message : null},
      sql: r'select hq.set_maintenance($1::text, $2::boolean, $3::text)',
      params: [app, on, on ? message : null],
    );
  }

  Future<void> _minVersion(Map<String, dynamic> row) async {
    final app = row['app'] as String;
    final c = TextEditingController(text: (row['min_app_version'] as String?) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Minimum version for ${_names[app] ?? app}', style: jost(18, weight: 600)),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'e.g. 1.0.5 — empty = no minimum'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Next')),
        ],
      ),
    );
    final v = c.text.trim();
    c.dispose();
    if (ok != true) return;
    if (v.isNotEmpty && !RegExp(r'^[0-9]+(\.[0-9]+){0,2}$').hasMatch(v)) {
      setState(() => _error = 'Version must look like 1.2.3');
      return;
    }
    await _act(
      title: 'Set minimum version for ${_names[app] ?? app}',
      whatHappens: v.isEmpty
          ? 'Removes the minimum version for ${_names[app] ?? app}.'
          : 'Sets the minimum ${_names[app] ?? app} version to $v. Older versions would be asked to update '
              '(once the apps read this).',
      action: 'set_min_version',
      details: {'app': app, 'version': v.isEmpty ? null : v},
      sql: r'select hq.set_min_version($1::text, $2::text)',
      params: [app, v.isEmpty ? null : v],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.data,
      builder: (context, _) {
        final rows = widget.data.rows(Q.appConfig);
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HqColors.surface,
            border: Border.all(color: HqColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('App switches', style: jost(16, weight: 600)),
            Text('Maintenance mode and minimum version per app. Changing one = confirm + Touch ID + action log.',
                style: jost(13, color: HqColors.muted)),
            const SizedBox(height: 10),
            if (rows == null)
              Text(
                  widget.data.isNotSet(Q.appConfig)
                      ? 'Gemstok not connected.'
                      : 'Not set up yet — run gemstok/sql/2026-11-14_app_config_operator.',
                  style: jost(13, color: HqColors.muted)),
            if (rows != null)
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 140, child: Text(_names[r['app']] ?? '${r['app']}', style: jost(14, weight: 500))),
                    Switch(
                      value: r['maintenance'] == true,
                      onChanged: _busy ? null : (_) => _toggle(r),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r['maintenance'] == true ? 'MAINTENANCE — "${r['message'] ?? ''}"' : 'normal',
                        style: jost(13, color: r['maintenance'] == true ? HqColors.bad : HqColors.ink),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _minVersion(r),
                      child: Text('min version: ${r['min_app_version'] ?? 'none'}'),
                    ),
                  ]),
                ),
            if (_error != null) Text(_error!, style: jost(13, color: HqColors.bad)),
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Action log (newest first)', style: jost(12, weight: 600, color: HqColors.muted)),
              for (final l in _log)
                Text(
                  '${fmtDateTime(DateTime.tryParse('${l['at']}'))} · ${l['action']} · ${l['details']} · '
                  '${l['ok'] == true ? 'done' : 'FAILED: ${l['error']}'}',
                  style: jost(12, color: l['ok'] == true ? HqColors.muted : HqColors.bad),
                ),
            ],
          ]),
        );
      },
    );
  }
}
