import 'package:flutter/material.dart';

import '../actions/maintenance_section.dart';
import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/projects.dart';
import '../db/queries.dart';
import '../keepalive/keep_alive.dart';
import '../servers/servers_data.dart';
import '../servers/supabase_api.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';

/// Servers: per Supabase project — status from Supabase (Active / PAUSED), Keep alive countdown + Ping,
/// edge functions (version, Verify JWT, last update) with their logs and call stats.
/// Everything here only READS (see servers/supabase_api.dart).
class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key, required this.keepAlive, required this.servers, required this.data});
  final HqKeepAlive keepAlive;
  final ServersData servers;
  final HqData data; // cron jobs (hq.cron_jobs) per project

  @override
  Widget build(BuildContext context) {
    return UseQueries(
      data: data,
      queries: Q.cronJobs,
      child: ListenableBuilder(
      listenable: Listenable.merge([keepAlive, servers, data]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Row(children: [
            Expanded(child: Text('Servers', style: jost(26, weight: 600))),
            if (servers.loadedAt != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('Supabase loaded ${fmtTime(servers.loadedAt!)} · every 10 min',
                    style: jost(12, color: HqColors.muted)),
              ),
            OutlinedButton(
              onPressed: servers.loading ? null : servers.refresh,
              child: Text(servers.loading ? 'Loading…' : 'Refresh'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: keepAlive.pingAll, child: const Text('Ping all now')),
          ]),
          const SizedBox(height: 4),
          Text(
              'Status and functions come from Supabase (read-only). Keep alive: free projects pause after about '
              '7 days without use; HQ does a real read of each connected project at least once a day while the Mac is awake.',
              style: jost(14, color: HqColors.muted)),
          const SizedBox(height: 16),
          if (!servers.anyToken && !servers.loading)
            const NoteBox(
              color: HqColors.warn,
              text: 'Add a Supabase access token in Settings → Supabase access tokens to see each project\'s '
                  'status, edge functions and logs here. HQ only reads with it.',
            ),
          for (final e in servers.tokenErrors.entries) NoteBox(color: HqColors.bad, text: 'Token ${e.key}: ${e.value}'),
          MaintenanceSection(data: data),
          for (final p in hqProjects)
            _ProjectCard(
              project: p,
              keepAlive: keepAlive,
              servers: servers,
              cron: data.rows(Q.cronJobs.firstWhere((q) => q.projectId == p.id)),
            ),
          const SizedBox(height: 8),
          const NoteBox(
            color: HqColors.warn,
            text: 'Free plan: Supabase keeps about 1 day of logs. Cron jobs show for projects where '
                'all-projects/sql/2026-11-14_hq_cron was run. "Run now" for cron jobs comes next.',
          ),
        ],
      ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.keepAlive, required this.servers, this.cron});
  final HqProject project;
  final HqKeepAlive keepAlive;
  final ServersData servers;
  final List<Map<String, dynamic>>? cron; // null = not available for this project

  @override
  Widget build(BuildContext context) {
    final p = project;
    final info = servers.projects[p.ref];
    final (status, ok) = ServersData.statusText(info?['status'] as String?);
    final fns = servers.functions[p.ref];
    final fnErr = servers.functionErrors[p.ref];

    // keep alive
    final left = keepAlive.left(p.id);
    final Color kaColour;
    final String countdown;
    if (left == null) {
      kaColour = HqColors.muted;
      countdown = 'never read by HQ';
    } else if (left.isNegative) {
      kaColour = HqColors.bad;
      countdown = 'overdue — may be paused';
    } else {
      kaColour = left.inHours < 24 ? HqColors.bad : (left.inDays < 3 ? HqColors.warn : HqColors.good);
      countdown = left.inDays >= 1 ? '${left.inDays} days left' : '${left.inHours} h left';
    }
    final rows = keepAlive.rows(p.id);
    final kaErr = keepAlive.error(p.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: info != null && !ok ? HqColors.bad : HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(p.name, style: jost(16, weight: 600)),
              Text(p.ref, style: jost(12, color: HqColors.muted)),
              if (info != null)
                Text(status, style: jost(13, weight: 600, color: ok ? HqColors.good : HqColors.bad)),
              if (info != null) Text('${info['region'] ?? ''}', style: jost(12, color: HqColors.muted)),
              if (info == null && servers.anyToken && !servers.loading)
                Text('not seen by your tokens', style: jost(12, color: HqColors.muted)),
            ]),
          ),
          OutlinedButton(
            onPressed: keepAlive.busy(p.id) ? null : () => keepAlive.ping(p),
            child: Text(keepAlive.busy(p.id) ? 'Pinging…' : 'Ping now'),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: kaColour, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Keep alive: $countdown · last real read ${fmtAgo(keepAlive.last(p.id))}'
              '${rows == null ? '' : ' · ${Q.pingTable[p.id]}: $rows rows'}',
              style: jost(13),
            ),
          ),
        ]),
        if (kaErr != null) Text(kaErr, style: jost(12, color: HqColors.bad)),
        if (cron != null && cron!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Cron jobs', style: jost(13, weight: 600)),
          for (final j in cron!) _CronRow(j: j),
        ],
        if (fnErr != null) Text('Functions: $fnErr', style: jost(12, color: HqColors.bad)),
        if (fns != null) ...[
          const SizedBox(height: 10),
          if (fns.isEmpty) Text('No edge functions.', style: jost(13, color: HqColors.muted)),
          for (final f in fns) _FunctionRow(ref: p.ref, f: f, servers: servers),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _LogsDialog(project: p, servers: servers),
              ),
              child: const Text('Logs (last 24 h)…'),
            ),
          ),
        ],
      ]),
    );
  }
}

class _FunctionRow extends StatelessWidget {
  const _FunctionRow({required this.ref, required this.f, required this.servers});
  final String ref;
  final Map<String, dynamic> f;
  final ServersData servers;

  @override
  Widget build(BuildContext context) {
    final updated = f['updated_at'] is int ? DateTime.fromMillisecondsSinceEpoch(f['updated_at'] as int) : null;
    final active = f['status'] == 'ACTIVE';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 230, child: Text('${f['slug'] ?? f['name']}', style: jost(14, weight: 500))),
        SizedBox(width: 60, child: Text('v${f['version'] ?? '?'}', style: jost(13, color: HqColors.muted))),
        SizedBox(
          width: 130,
          child: Text(f['verify_jwt'] == true ? 'Verify JWT on' : 'Verify JWT off', style: jost(13)),
        ),
        SizedBox(width: 160, child: Text('updated ${fmtDate(updated)}', style: jost(13, color: HqColors.muted))),
        if (!active) Text('${f['status']}', style: jost(12, weight: 600, color: HqColors.bad)),
        const Spacer(),
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _StatsDialog(ref: ref, f: f, servers: servers),
          ),
          child: const Text('Calls'),
        ),
      ]),
    );
  }
}

/// Calls / errors for one function (Supabase's combined stats, last day). Shown as Supabase returns them.
class _StatsDialog extends StatefulWidget {
  const _StatsDialog({required this.ref, required this.f, required this.servers});
  final String ref;
  final Map<String, dynamic> f;
  final ServersData servers;

  @override
  State<_StatsDialog> createState() => _StatsDialogState();
}

class _StatsDialogState extends State<_StatsDialog> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await widget.servers.tokenFor(widget.ref);
      if (token == null) throw const SupabaseApiError(0, 'No token sees this project.');
      _rows = await SupabaseApi.functionStats(token, widget.ref, '${widget.f['id']}');
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final keys = <String>{for (final r in rows ?? const <Map<String, dynamic>>[]) ...r.keys}.toList();
    return AlertDialog(
      title: Text('${widget.f['slug']} — calls, last day', style: jost(18, weight: 600)),
      content: SizedBox(
        width: 640,
        height: 380,
        child: _error != null
            ? Text(_error!, style: jost(13, color: HqColors.bad))
            : rows == null
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Text('No calls in the last day.', style: jost(14, color: HqColors.muted))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: [for (final k in keys) DataColumn(label: Text(k, style: jost(12, weight: 600)))],
                            rows: [
                              for (final r in rows)
                                DataRow(cells: [for (final k in keys) DataCell(Text('${r[k] ?? ''}', style: jost(13)))]),
                            ],
                          ),
                        ),
                      ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

/// Logs of the last 24 h. Preset queries + an editable one (Supabase's logs use ClickHouse SQL).
class _LogsDialog extends StatefulWidget {
  const _LogsDialog({required this.project, required this.servers});
  final HqProject project;
  final ServersData servers;

  @override
  State<_LogsDialog> createState() => _LogsDialogState();
}

class _LogsDialogState extends State<_LogsDialog> {
  static const presets = <String, String>{
    'Edge function requests':
        'select timestamp, event_message from function_edge_logs order by timestamp desc limit 100',
    'Edge function console': 'select timestamp, event_message from function_logs order by timestamp desc limit 100',
    'API requests': 'select timestamp, event_message from edge_logs order by timestamp desc limit 100',
    'Postgres': 'select timestamp, event_message from postgres_logs order by timestamp desc limit 100',
  };

  late final _sql = TextEditingController(text: presets.values.first);
  final _filter = TextEditingController();
  List<Map<String, dynamic>>? _rows;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _sql.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await widget.servers.tokenFor(widget.project.ref);
      if (token == null) throw const SupabaseApiError(0, 'No token sees this project.');
      _rows = await SupabaseApi.logs(token, widget.project.ref, _sql.text);
    } catch (e) {
      _error = '$e';
      _rows = null;
    }
    if (mounted) setState(() => _busy = false);
  }

  String _ts(Object? t) {
    // Supabase log timestamps are microseconds since 1970 (or text)
    if (t is int) return fmtDateTime(DateTime.fromMicrosecondsSinceEpoch(t, isUtc: true));
    return '$t';
  }

  @override
  Widget build(BuildContext context) {
    final f = _filter.text.trim().toLowerCase();
    final rows = (_rows ?? const <Map<String, dynamic>>[])
        .where((r) => f.isEmpty || '${r['event_message'] ?? r}'.toLowerCase().contains(f))
        .toList();
    return AlertDialog(
      title: Text('${widget.project.name} — logs, last 24 h', style: jost(18, weight: 600)),
      content: SizedBox(
        width: 900,
        height: 560,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in presets.entries)
              OutlinedButton(
                onPressed: () {
                  _sql.text = e.value;
                  _run();
                },
                child: Text(e.key),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _sql,
            maxLines: 2,
            style: jost(12),
            decoration: const InputDecoration(labelText: 'Log query (ClickHouse SQL — Supabase docs: "logs explorer")'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _filter,
                decoration: const InputDecoration(labelText: 'Filter lines'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(onPressed: _busy ? null : _run, child: Text(_busy ? 'Loading…' : 'Run')),
            const SizedBox(width: 10),
            if (_rows != null) Text('${rows.length} lines', style: jost(12, color: HqColors.muted)),
          ]),
          const SizedBox(height: 8),
          if (_error != null) Text(_error!, style: jost(13, color: HqColors.bad)),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 150, child: Text(_ts(r['timestamp']), style: jost(11, color: HqColors.muted))),
                    Expanded(
                      child: SelectableText('${r['event_message'] ?? r}',
                          style: const TextStyle(fontFamily: 'Menlo', fontSize: 11.5)),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

class _CronRow extends StatelessWidget {
  const _CronRow({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final failed = (j['failed_24h'] as int?) ?? 0;
    final last = j['last_status'] as String?;
    final start = j['last_start'] as DateTime?;
    final end = j['last_end'] as DateTime?;
    final took = start != null && end != null ? ' · ${end.difference(start).inMilliseconds} ms' : '';
    final bad = failed > 0 || last == 'failed' || j['active'] != true;
    return Tooltip(
      message: '${j['last_message'] ?? ''}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 230, child: Text('${j['jobname'] ?? 'job ${j['jobid']}'}', style: jost(14, weight: 500))),
          SizedBox(width: 130, child: Text('${j['schedule']}', style: jost(13, color: HqColors.muted))),
          SizedBox(
            width: 80,
            child: Text(j['active'] == true ? 'on' : 'OFF',
                style: jost(13, weight: 600, color: j['active'] == true ? HqColors.good : HqColors.bad)),
          ),
          Expanded(
            child: Text(
              'last: ${last ?? '—'} ${fmtAgo(start)}$took · 24 h: ${j['runs_24h']} runs, $failed failed',
              style: jost(13, color: bad ? HqColors.bad : HqColors.ink),
            ),
          ),
        ]),
      ),
    );
  }
}
