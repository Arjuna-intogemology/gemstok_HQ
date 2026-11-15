import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../widgets/charts.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import 'releases_store.dart';
import '../widgets/dispose_later.dart';

/// Releases: per app — the version in the project on this Mac (pubspec.yaml), the versions people
/// actually use (login_history, last 30 days), and the planned updates with their checklists
/// (gemstok_hq/releases/releases.json).
class ReleasesScreen extends StatefulWidget {
  const ReleasesScreen({super.key, required this.data});
  final HqData data;

  @override
  State<ReleasesScreen> createState() => _ReleasesScreenState();
}

class _ReleasesScreenState extends State<ReleasesScreen> {
  List<Release> _list = [];
  final _mac = <String, String?>{}; // app key → pubspec version
  final _newItem = <String, TextEditingController>{}; // release id → "add item" box
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    for (final c in _newItem.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final l = await ReleaseStore.load();
      for (final a in HqApp.all) {
        _mac[a.key] = await a.macVersion();
      }
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t read releases.json: $e');
    }
  }

  Future<void> _save() async {
    try {
      await ReleaseStore.save(_list);
      _error = null;
    } catch (e) {
      _error = 'Couldn\'t save: $e';
    }
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------ edit

  Future<void> _edit(Release? r, HqApp app) async {
    final version = TextEditingController(text: r?.version ?? 'next');
    final target = TextEditingController(text: r?.target ?? '');
    final notes = TextEditingController(text: r?.notes ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r == null ? '${app.name} — plan an update' : '${app.name} ${r.version}', style: jost(18, weight: 600)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: version,
                decoration: const InputDecoration(labelText: 'Version, e.g. 1.2.0 (or "next" until you know)')),
            const SizedBox(height: 10),
            TextField(controller: target, decoration: const InputDecoration(labelText: 'Target, e.g. early Dec')),
            const SizedBox(height: 10),
            TextField(
                controller: notes,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Notes (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      final v = version.text.trim().isEmpty ? 'next' : version.text.trim();
      if (r == null) {
        _list.add(Release(id: ReleaseStore.newId(), app: app.key, version: v, target: target.text.trim(), notes: notes.text.trim()));
      } else {
        r
          ..version = v
          ..target = target.text.trim()
          ..notes = notes.text.trim();
      }
      await _save();
    }
    disposeLater([version, target, notes]);
  }

  Future<void> _remove(Release r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${r.version}?', style: jost(18, weight: 600)),
        content: Text('Removes this plan and its checklist from releases.json.', style: jost(14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      _list.remove(r);
      await _save();
    }
  }

  Future<void> _setStatus(Release r, String s) async {
    r.status = s;
    if (s == 'live') {
      r.releasedAt ??= DateTime.now();
    } else {
      r.releasedAt = null;
    }
    await _save();
  }

  // ------------------------------------------------------------------ page

  @override
  Widget build(BuildContext context) => ScreenFrame(
        title: 'Releases',
        subtitle: 'Per app: the version in its project on this Mac, the versions people really use (last 30 days), '
            'and what\'s planned for the next updates.',
        data: widget.data,
        queries: const [Q.appVersions, Q.appConfig],
        body: () => [
          Row(children: [
            Expanded(
              child: Text('Plans are kept in gemstok_hq/releases/releases.json.',
                  style: jost(12, color: HqColors.muted)),
            ),
            TextButton(onPressed: _reload, child: const Text('Reload file + Mac versions')),
          ]),
          if (_error != null) NoteBox(color: HqColors.bad, text: _error!),
          for (final a in HqApp.all) _appCard(a),
        ],
      );

  Widget _appCard(HqApp app) {
    final rows = widget.data.rows(Q.appVersions)?.where((r) => r['app'] == app.key).toList();
    final config = widget.data.rows(Q.appConfig)?.where((r) => r['app'] == app.key).firstOrNull;
    final mac = _mac[app.key];
    final plans = _list.where((r) => r.app == app.key && r.status != 'live').toList();
    final shipped = _list.where((r) => r.app == app.key && r.status == 'live').toList()
      ..sort((a, b) => (b.releasedAt ?? DateTime(2000)).compareTo(a.releasedAt ?? DateTime(2000)));

    // newest version anyone used, and how many people are on it vs older
    String? newest;
    var onNewest = 0, total = 0;
    for (final r in rows ?? const <Map<String, dynamic>>[]) {
      final v = '${r['version']}';
      if (parseVersion(v) != null && (newest == null || compareVersions(v, newest) > 0)) newest = v;
    }
    for (final r in rows ?? const <Map<String, dynamic>>[]) {
      total += r['people'] as int;
      if (newest != null && compareVersions('${r['version']}', newest) == 0) onNewest += r['people'] as int;
    }

    final (String, Color)? compare = (mac == null || newest == null)
        ? null
        : switch (compareVersions(mac, newest)) {
            > 0 => ('$mac on this Mac is newer than anything in use — not released yet, or nobody has updated.', HqColors.warn),
            0 => ('This Mac has the same version people use.', HqColors.good),
            _ => ('People use $newest, newer than this Mac\'s $mac — pull the latest code before building?', HqColors.bad),
          };

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(app.name, style: jost(20, weight: 600))),
          FilledButton.tonal(onPressed: () => _edit(null, app), child: const Text('+ Plan an update')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 22, runSpacing: 6, children: [
          _fact('On this Mac', mac ?? 'not found (${app.folder}/pubspec.yaml)'),
          _fact('Newest in use', newest == null ? '–' : '$newest · $onNewest of $total people'),
          if (config != null && '${config['min_app_version'] ?? ''}'.isNotEmpty)
            _fact('Minimum allowed', '${config['min_app_version']}'),
        ]),
        if (compare != null) ...[
          const SizedBox(height: 8),
          Text(compare.$1, style: jost(13, weight: 500, color: compare.$2)),
        ],
        if (rows != null && rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          SimpleTable(
            header: const ['Version people use (last app open)', 'Device', 'People', 'Last seen'],
            rows: [
              for (final r in rows)
                ['${r['version']}', '${r['device']}', fmtNum(r['people']), fmtAgo(r['last_seen'] as DateTime?)],
            ],
          ),
        ],
        if (rows != null && rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Nobody opened ${app.name} in the last 30 days (or it doesn\'t send app opens yet).',
                style: jost(13, color: HqColors.muted)),
          ),
        const SizedBox(height: 14),
        if (plans.isEmpty) Text('No planned updates.', style: jost(13, color: HqColors.muted)),
        for (final r in plans) _releaseCard(r, app),
        if (shipped.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Shipped (${shipped.length})', style: jost(13, weight: 600, color: HqColors.muted)),
                children: [for (final r in shipped) _releaseCard(r, app)],
              ),
            ),
          ),
      ]),
    );
  }

  Widget _fact(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: jost(11, weight: 500, color: HqColors.muted)),
        Text(value, style: jost(15, weight: 600)),
      ]);

  Widget _releaseCard(Release r, HqApp app) {
    final box = _newItem.putIfAbsent(r.id, TextEditingController.new);
    final live = r.status == 'live';
    final vsMac = _mac[app.key] == null ? null : compareVersions(r.version, _mac[app.key]!);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HqColors.background,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(r.version == 'next' ? 'Next update' : r.version, style: jost(16, weight: 600)),
          DropdownButton<String>(
            value: r.status,
            isDense: true,
            underline: const SizedBox(),
            items: [
              for (final e in Release.statuses.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value, style: jost(13, weight: 500))),
            ],
            onChanged: (v) => v == null ? null : _setStatus(r, v),
          ),
          if (r.target.isNotEmpty) Text('target ${r.target}', style: jost(12, color: HqColors.muted)),
          if (live && r.releasedAt != null) Text('live since ${fmtDate(r.releasedAt)}', style: jost(12, color: HqColors.good)),
          if (r.items.isNotEmpty) Text('${r.doneCount} of ${r.items.length} done', style: jost(12, weight: 500)),
          if (!live && vsMac != null && parseVersion(r.version) != null)
            Text(
                vsMac == 0
                    ? 'matches this Mac\'s pubspec'
                    : vsMac > 0
                        ? 'pubspec on the Mac is still ${_mac[app.key]}'
                        : 'older than the Mac\'s ${_mac[app.key]}',
                style: jost(12, color: vsMac == 0 ? HqColors.good : HqColors.warn)),
          TextButton(onPressed: () => _edit(r, app), child: const Text('Edit')),
          TextButton(onPressed: () => _remove(r), child: const Text('Remove')),
        ]),
        if (r.notes.isNotEmpty) Text(r.notes, style: jost(13, color: HqColors.muted)),
        for (final i in r.items)
          Row(children: [
            Checkbox(
              value: i.done,
              onChanged: (v) {
                i.done = v ?? false;
                _save();
              },
            ),
            Expanded(
              child: Text(i.text,
                  style: jost(14, color: i.done ? HqColors.muted : HqColors.ink)
                      .copyWith(decoration: i.done ? TextDecoration.lineThrough : null)),
            ),
            IconButton(
              tooltip: 'Remove item',
              icon: const Icon(Icons.close, size: 16, color: HqColors.muted),
              onPressed: () {
                r.items.remove(i);
                _save();
              },
            ),
          ]),
        if (!live)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 8),
            child: TextField(
              controller: box,
              decoration: const InputDecoration(
                  isDense: true, hintText: 'Add a change to this update, then Enter', prefixIcon: Icon(Icons.add, size: 16)),
              onSubmitted: (t) {
                if (t.trim().isEmpty) return;
                r.items.add(ReleaseItem(t.trim()));
                box.clear();
                _save();
              },
            ),
          ),
      ]),
    );
  }
}
