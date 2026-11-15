import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import 'campaign_store.dart';
import 'qr_export.dart';
import '../widgets/dispose_later.dart';

/// Leads → campaign links and printable QR codes.
/// Each place — or each PERSON — that hands out a link gets its own tag, so HQ can show
/// clicks → sign-ups per place / per person.
class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key, required this.data});
  final HqData data; // clicks (Websites) + sign-ups (Gemstok) per tag

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  final _name = TextEditingController();
  final _tag = TextEditingController();
  final _where = TextEditingController();
  bool _tagTouched = false; // stop auto-filling the tag once you type in it yourself
  String _site = 'manikvault';
  String _kind = 'place'; // new campaign: 'place' or 'person'
  String _memberGsm = ''; // person picked from the member search
  final _nameFocus = FocusNode();
  final _search = TextEditingController();
  String _show = 'all'; // list filter: all / place / person
  List<Campaign> _list = [];
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    widget.data.use(const [Q.campaignVisits, Q.campaignSignups, Q.memberNames]);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    _where.dispose();
    _nameFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await CampaignStore.load();
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t read campaigns: $e');
    }
  }

  Future<void> _save() async {
    try {
      await CampaignStore.save(_list);
    } catch (e) {
      _error = 'Couldn\'t save: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final tag = _tag.text.trim();
    setState(() {
      _error = null;
      _info = null;
    });
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the campaign a name.');
      return;
    }
    if (!CampaignStore.tagRule.hasMatch(tag)) {
      setState(() => _error = 'Tag: 2–40 characters, only a–z, 0–9, - and _.');
      return;
    }
    if (_list.any((c) => c.tag == tag)) {
      setState(() => _error = 'That tag is already used — tags must be unique so the numbers stay clean.');
      return;
    }
    _list.insert(
      0,
      Campaign(
        tag: tag,
        name: _name.text.trim(),
        site: _site,
        createdAt: DateTime.now(),
        where: _where.text.trim(),
        kind: _kind,
        memberGsm: _kind == 'person' ? _memberGsm : '',
      ),
    );
    _memberGsm = '';
    _name.clear();
    _tag.clear();
    _where.clear();
    _tagTouched = false;
    await _save();
  }

  /// Several people at once: one name per line → one person campaign each.
  Future<void> _addMany() async {
    final box = TextEditingController();
    final where = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Links for several people', style: jost(18, weight: 600)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('One name per line. Each person gets their own link and QR (tag p-<name>).',
                style: jost(13, color: HqColors.muted)),
            const SizedBox(height: 10),
            TextField(
              controller: box,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(labelText: 'Names', hintText: 'Sunil Perera\nNimal\nKasun (broker)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: where,
              decoration: const InputDecoration(labelText: 'For all of them (optional), e.g. Ratnapura agents'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create links')),
        ],
      ),
    );
    final names = box.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final note = where.text.trim();
    disposeLater([box, where]);
    if (ok != true || names.isEmpty) return;
    var made = 0;
    for (final n in names) {
      final base = CampaignStore.suggestPersonTag(n);
      if (base.length < 2) continue;
      final tag = CampaignStore.uniqueTag(base, _list.map((c) => c.tag));
      // a name that matches exactly one member gets linked to them
      final hits = (widget.data.rows(Q.memberNames) ?? const [])
          .where((m) => '${m['name']}'.trim().toLowerCase() == n.toLowerCase())
          .toList();
      _list.insert(
        0,
        Campaign(
          tag: tag,
          name: n,
          site: _site,
          createdAt: DateTime.now(),
          where: note,
          kind: 'person',
          memberGsm: hits.length == 1 ? '${hits.first['gemstok_id']}' : '',
        ),
      );
      made++;
    }
    await _save();
    if (mounted) setState(() => _info = '$made person links made.');
  }

  /// Delete: hidden from HQ, tag kept reserved; its print QR moves to leads/qr/_removed/.
  Future<void> _delete(Campaign c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${c.name}"?', style: jost(18, weight: 600)),
        content: SizedBox(
          width: 420,
          child: Text(
              'It disappears from Leads. Its link and QR stop being tracked here (they still open the Get page if '
              'someone has them). The tag "${c.tag}" stays reserved, so a new campaign never mixes with its old clicks.\n\n'
              'Only want to stop it for a while? Use Pause instead.',
              style: jost(14)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HqColors.bad),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    c.removed = true;
    c.active = false;
    try {
      final png = File('${CampaignStore.folder}/qr/${c.tag}.png');
      if (await png.exists()) {
        final dir = Directory('${CampaignStore.folder}/qr/_removed');
        await dir.create(recursive: true);
        await png.rename('${dir.path}/${c.tag}.png');
      }
    } catch (_) {}
    await _save();
    if (mounted) setState(() => _info = '"${c.name}" deleted.');
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _info = '$what copied.');
  }

  Future<void> _savePng(Campaign c) async {
    try {
      final f = await QrExport.savePng(c,
          title: 'Get ${CampaignStore.sites[c.site]!.$1}', byLine: c.isPerson ? 'shared by ${c.name}' : null);
      await QrExport.showInFinder(f);
      if (mounted) setState(() => _info = 'QR saved: leads/qr/${c.tag}.png (opened in Finder).');
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t save the QR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: widget.data, builder: (context, _) => _page());
  }

  /// "Clicks 12 (7 days: 3) · Sign-ups 2" — or what's still missing.
  String _numbers(Campaign c) {
    final d = widget.data;
    final v = d.rows(Q.campaignVisits)?.where((r) => r['tag'] == c.tag).firstOrNull;
    final s = d.rows(Q.campaignSignups)?.where((r) => r['tag'] == c.tag).firstOrNull;
    final clicks = d.rows(Q.campaignVisits) == null
        ? 'Clicks: waiting for the Get-page counter'
        : 'Clicks: ${v?['visits'] ?? 0} (7 days: ${v?['visits_7d'] ?? 0})';
    final signups = d.rows(Q.campaignSignups) == null
        ? 'sign-ups: Gemstok not loaded'
        : 'sign-ups: ${s?['signups'] ?? 0}${s == null ? ' (apps start sending the tag after their update)' : ''}';
    return '$clicks · $signups';
  }

  Widget _page() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(children: [
          Expanded(child: Text('Leads', style: jost(26, weight: 600))),
          OutlinedButton(
            onPressed: () => widget.data.refresh(const [Q.campaignVisits, Q.campaignSignups]),
            child: const Text('Refresh'),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
            'One tag per place you hand out a link — a flyer, a WhatsApp group, a gem fair — or per person who '
            'shares it for you (an agent, a broker). Links open the Get page; QR codes send the phone straight to its store.',
            style: jost(14, color: HqColors.muted)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HqColors.surface,
            border: Border.all(color: HqColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: double.infinity,
              child: Row(children: [
                Choice<String>(
                  options: const {'place': 'For a place', 'person': 'For a person'},
                  value: _kind,
                  onChanged: (v) => setState(() {
                    _kind = v;
                    _memberGsm = '';
                    if (!_tagTouched) _tag.text = _suggest(_name.text);
                  }),
                ),
                const Spacer(),
                if (_kind == 'person')
                  TextButton(onPressed: _addMany, child: const Text('Several people at once…')),
              ]),
            ),
            SizedBox(width: 280, child: _kind == 'person' ? _personField() : _placeField()),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _tag,
                decoration: const InputDecoration(labelText: 'Tag (in the link)'),
                onChanged: (_) => _tagTouched = true,
              ),
            ),
            SizedBox(
              width: 280,
              child: TextField(
                controller: _where,
                decoration: InputDecoration(
                    labelText: _kind == 'person' ? 'Who they are (optional), e.g. agent, Ratnapura' : 'Where it\'s used (optional)'),
              ),
            ),
            DropdownButton<String>(
              value: _site,
              items: [
                for (final e in CampaignStore.sites.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
              ],
              onChanged: (v) => setState(() => _site = v ?? _site),
            ),
            FilledButton(onPressed: _add, child: const Text('Create link')),
          ]),
        ),
        const SizedBox(height: 12),
        if (_error != null) NoteBox(color: HqColors.bad, text: _error!),
        if (_info != null) NoteBox(color: HqColors.good, text: _info!),
        const NoteBox(
          color: HqColors.warn,
          text: 'Clicks start counting once the Websites SQL "2026-11-14_campaign_visits" is run and manikvault.com '
              'is deployed (the Get page then counts each tag — no personal data). Android installs carry the tag '
              'into the app; sign-ups per campaign show once the apps send it (planned app update).',
        ),
        const SizedBox(height: 8),
        if (_live.isEmpty) Text('No campaigns yet.', style: jost(13, color: HqColors.muted)),
        if (_live.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Choice<String>(
                options: {
                  'all': 'All (${_live.length})',
                  'place': 'Places (${_live.where((c) => !c.isPerson).length})',
                  'person': 'People (${_live.where((c) => c.isPerson).length})',
                },
                value: _show,
                onChanged: (v) => setState(() => _show = v),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Search name or tag', prefixIcon: Icon(Icons.search, size: 18), isDense: true),
                ),
              ),
            ]),
          ),
        for (final c in _shown()) _card(c),
      ],
    );
  }

  Widget _card(Campaign c) {
    return Opacity(
      opacity: c.active ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HqColors.surface,
          border: Border.all(color: HqColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(6),
            child: QrImageView(data: c.qrLink, size: 120, backgroundColor: Colors.white),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(c.name, style: jost(17, weight: 600)),
                Text(c.tag, style: jost(13, color: HqColors.muted)),
                if (c.isPerson)
                  Text(c.memberGsm.isEmpty ? 'person' : 'person · ${c.memberGsm}',
                      style: jost(12, weight: 600, color: HqColors.accent)),
                if (!c.active) Text('paused', style: jost(12, weight: 600, color: HqColors.warn)),
              ]),
              const SizedBox(height: 4),
              Text(
                [
                  CampaignStore.sites[c.site]!.$1,
                  if (c.where.isNotEmpty) c.where,
                  'made ${fmtDate(c.createdAt)}',
                ].join(' · '),
                style: jost(12, color: HqColors.muted),
              ),
              const SizedBox(height: 8),
              SelectableText(c.link, style: jost(14)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                OutlinedButton(onPressed: () => _copy(c.link, 'Link'), child: const Text('Copy link')),
                OutlinedButton(onPressed: () => _copy(c.qrLink, 'QR link'), child: const Text('Copy QR link')),
                FilledButton(onPressed: () => _savePng(c), child: const Text('Save QR for print')),
                TextButton(
                  onPressed: () async {
                    c.active = !c.active;
                    await _save();
                  },
                  child: Text(c.active ? 'Pause' : 'Resume'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: HqColors.bad),
                  onPressed: () => _delete(c),
                  child: const Text('Delete'),
                ),
              ]),
              const SizedBox(height: 6),
              Text(_numbers(c), style: jost(13, weight: 500)),
            ]),
          ),
        ]),
      ),
    );
  }

  String _suggest(String name) =>
      _kind == 'person' ? CampaignStore.suggestPersonTag(name) : CampaignStore.suggestTag(name);

  List<Campaign> get _live => _list.where((c) => !c.removed).toList();

  List<Campaign> _shown() {
    final q = _search.text.trim().toLowerCase();
    return _list.where((c) {
      if (c.removed) return false;
      if (_show == 'place' && c.isPerson) return false;
      if (_show == 'person' && !c.isPerson) return false;
      return q.isEmpty || '${c.name} ${c.tag} ${c.where} ${c.memberGsm}'.toLowerCase().contains(q);
    }).toList();
  }

  Widget _placeField() => TextField(
        controller: _name,
        focusNode: _nameFocus,
        decoration: const InputDecoration(labelText: 'Campaign name, e.g. Ratnapura gem fair'),
        onChanged: (v) {
          if (!_tagTouched) setState(() => _tag.text = _suggest(v));
        },
      );

  /// Person: search members (links the campaign to their Gemstok ID), or just type any name.
  Widget _personField() => RawAutocomplete<Map<String, dynamic>>(
        textEditingController: _name,
        focusNode: _nameFocus,
        displayStringForOption: (m) => '${m['name']}',
        optionsBuilder: (value) {
          final q = value.text.trim().toLowerCase();
          final all = widget.data.rows(Q.memberNames);
          if (q.length < 2 || all == null) return const <Map<String, dynamic>>[];
          return all
              .where((m) => '${m['name']} ${m['username'] ?? ''} ${m['gemstok_id']}'.toLowerCase().contains(q))
              .take(8);
        },
        onSelected: (m) => setState(() {
          _memberGsm = '${m['gemstok_id']}';
          if (!_tagTouched) _tag.text = _suggest('${m['name']}');
        }),
        fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
          controller: controller,
          focusNode: focus,
          onChanged: (v) => setState(() {
            _memberGsm = ''; // typed over a picked member
            if (!_tagTouched) _tag.text = _suggest(v);
          }),
          decoration: InputDecoration(
            labelText: 'Person — search members, or type a name',
            helperText: _memberGsm.isEmpty ? null : 'member $_memberGsm',
            prefixIcon: const Icon(Icons.person_search, size: 18),
          ),
        ),
        optionsViewBuilder: (context, onSelect, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360, maxHeight: 300),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final m in options)
                    InkWell(
                      onTap: () => onSelect(m),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        child: Row(children: [
                          Expanded(child: Text('${m['name']}', style: jost(14, weight: 500))),
                          Text('${m['gemstok_id']}', style: jost(12, color: HqColors.muted)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
