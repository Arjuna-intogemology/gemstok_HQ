import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import 'ideas_store.dart';
import '../widgets/dispose_later.dart';

/// Ideas: the idea pool. Each idea gets a number (IDEA-0001) and is credited to ONE member
/// (by Gemstok member id, so a GSM/TEMP change can't move it). The same idea from someone else
/// is added as "also suggested" — never a second credit. Move along New → Thinking → Planned → Done (or No).
/// Nothing is ever deleted.
class IdeasScreen extends StatefulWidget {
  const IdeasScreen({super.key, required this.data});
  final HqData data; // for the member search (names come from Gemstok, kept in memory only)

  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
  final _text = TextEditingController();
  final _from = TextEditingController();
  final _fromFocus = FocusNode();
  String _fromGsm = ''; // set when a member is picked from the search
  String _fromMemberId = ''; // Gemstok member id of the picked member (the credit goes here)
  final _search = TextEditingController();
  String _app = 'ManiKVault';
  String _filter = 'open'; // open = new + thinking + planned
  String _appFilter = 'All';
  List<Idea> _ideas = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.data.use(const [Q.memberNames]);
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _from.dispose();
    _fromFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await IdeasStore.load();
      if (mounted) setState(() => _ideas = list);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t read the ideas file: $e');
    }
  }

  Future<void> _save() async {
    try {
      await IdeasStore.save(_ideas);
      _error = null;
    } catch (e) {
      _error = 'Couldn\'t save: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    if (_text.text.trim().isEmpty) return;
    // Exactly the same idea already in the pool? Default: add as "also suggested", not a second credit.
    final key = IdeasStore.norm(_text.text);
    final same = _ideas.where((i) => IdeasStore.norm(i.text) == key && i.mergedInto.isEmpty).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    if (same.isNotEmpty) {
      final first = same.first;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${first.label} is already in the pool', style: jost(18, weight: 600)),
          content: Text('"${first.text}" — credit: ${_creditText(first)}.\n\n'
              'The same idea gets ONE credit. Add this person as "also suggested" instead?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'new'), child: const Text('It\'s different — save new')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'also'), child: const Text('Add as also suggested')),
          ],
        ),
      );
      if (choice == 'also') return _addAsAlso(first);
      if (choice != 'new') return;
    }
    final now = DateTime.now();
    _ideas.insert(
      0,
      Idea(
        id: IdeasStore.newId(),
        createdAt: now,
        updatedAt: now,
        text: _text.text.trim(),
        from: _from.text.trim(),
        gsmId: _fromGsm,
        memberId: _fromMemberId,
        app: _app,
        number: IdeasStore.nextNumber(_ideas),
      ),
    );
    _clearForm();
    await _save();
  }

  void _clearForm() {
    _text.clear();
    _from.clear();
    _fromGsm = '';
    _fromMemberId = '';
  }

  /// The idea is already in the pool → this person is added as "also suggested". No new credit.
  Future<void> _addAsAlso(Idea i) async {
    final sameAsCredited = _fromMemberId.isNotEmpty && _fromMemberId == i.memberId;
    final already = _fromMemberId.isNotEmpty && i.also.any((a) => a.memberId == _fromMemberId);
    if (!sameAsCredited && !already && (_from.text.trim().isNotEmpty || _fromMemberId.isNotEmpty)) {
      i.also.add(IdeaVoice(at: DateTime.now(), name: _from.text.trim(), gsmId: _fromGsm, memberId: _fromMemberId));
      i.updatedAt = DateTime.now();
    }
    _clearForm();
    await _save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sameAsCredited
            ? '${i.label} is already credited to this person.'
            : already
                ? 'Already listed on ${i.label}.'
                : 'Added to ${i.label} as "also suggested". The credit stays with the first person.'),
      ));
    }
  }

  String _creditText(Idea i) => i.memberId.isEmpty
      ? (i.from.isEmpty ? 'nobody yet' : '${i.from} (not linked)')
      : '${_nameNow(i.memberId, i.from)} (${_gsmNow(i.memberId, i.gsmId)})';

  /// An older idea in the pool that looks the same as [i] (for "Merge into …").
  Idea? _olderTwin(Idea i) {
    if (i.mergedInto.isNotEmpty || i.creditedAt != null) return null;
    final older = _ideas.where((o) => o != i && o.number < i.number && o.mergedInto.isEmpty).toList();
    final hits = IdeasStore.similar(older, i.text)..sort((a, b) => a.number.compareTo(b.number));
    return hits.isEmpty ? null : hits.first;
  }

  /// Two cards for the same idea → the later one becomes "also suggested" on the first. Nothing is deleted:
  /// the later card stays under "No" with a note. Not allowed once its credit was given.
  Future<void> _merge(Idea later, Idea first) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Merge ${later.label} into ${first.label}?', style: jost(18, weight: 600)),
        content: Text('Credit stays with ${_creditText(first)} (${first.label} came first).\n'
            '${_creditText(later)} is added to ${first.label} as "also suggested" — no credit.\n'
            '${later.label} moves to "No" with a note. Nothing is deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Merge')),
        ],
      ),
    );
    if (ok != true) return;
    final samePerson = later.memberId.isNotEmpty && later.memberId == first.memberId;
    if (!samePerson && !first.also.any((a) => a.memberId.isNotEmpty && a.memberId == later.memberId)) {
      first.also.add(IdeaVoice(at: later.createdAt, name: later.from, gsmId: later.gsmId, memberId: later.memberId));
    }
    first.also.addAll(later.also.where((a) => a.memberId.isEmpty || a.memberId != first.memberId));
    later
      ..also.clear()
      ..mergedInto = first.label
      ..status = 'no'
      ..notes = [later.notes, 'Merged into ${first.label} (same idea).'].where((t) => t.isNotEmpty).join('\n')
      ..updatedAt = DateTime.now();
    first.updatedAt = DateTime.now();
    await _save();
  }

  /// Member id → current GSM id (follows a TEMP → GSM restore); falls back to what was saved.
  String _gsmNow(String memberId, String saved) {
    if (memberId.isEmpty) return saved;
    final m = widget.data.rows(Q.memberNames)?.where((r) => r['id'] == memberId).firstOrNull;
    return m == null ? saved : '${m['gemstok_id']}';
  }

  String _nameNow(String memberId, String saved) {
    if (memberId.isEmpty) return saved;
    final m = widget.data.rows(Q.memberNames)?.where((r) => r['id'] == memberId).firstOrNull;
    final n = m == null ? '' : '${m['name']}'.trim();
    return n.isEmpty ? saved : n;
  }

  /// Link an older idea (free-text "from") to a real member. Only before the credit is given.
  Future<void> _linkMember(Idea i) async {
    final m = await _pickMember(i.from);
    if (m == null) return;
    final id = '${m['id']}';
    final dup = _ideas.where((o) => o != i && o.memberId == id && IdeasStore.similar([o], i.text).isNotEmpty);
    i
      ..memberId = id
      ..gsmId = '${m['gemstok_id']}'
      ..from = '${m['name']}'
      ..updatedAt = DateTime.now();
    await _save();
    if (dup.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Note: ${dup.first.label} looks like the same idea from the same person.')));
    }
  }

  Future<Map<String, dynamic>?> _pickMember(String start) async {
    final c = TextEditingController(text: start);
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final q = c.text.trim().toLowerCase();
        final all = widget.data.rows(Q.memberNames) ?? const <Map<String, dynamic>>[];
        final hits = q.length < 2
            ? const <Map<String, dynamic>>[]
            : all.where((m) => '${m['name']} ${m['username'] ?? ''} ${m['gemstok_id']}'.toLowerCase().contains(q)).take(8).toList();
        return AlertDialog(
          title: Text('Who suggested it?', style: jost(18, weight: 600)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: c,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name, username or GSM ID'),
                onChanged: (_) => setD(() {}),
              ),
              const SizedBox(height: 8),
              for (final m in hits)
                ListTile(
                  dense: true,
                  title: Text('${m['name']}'),
                  trailing: Text('${m['gemstok_id']}', style: jost(12, color: HqColors.muted)),
                  onTap: () => Navigator.pop(ctx, m),
                ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
        );
      }),
    );
    disposeLater([c]);
    return picked;
  }

  /// Remove an idea from the pool. It's moved to ideas/removed_ideas.json (not lost) and its number
  /// is never used again. Not allowed once credit was given, or while other ideas are merged into it.
  Future<void> _delete(Idea i) async {
    final mergedHere = _ideas.where((o) => o.mergedInto == i.label).map((o) => o.label).toList();
    final blocked = i.creditedAt != null
        ? '${i.label} was credited on ${fmtDate(i.creditedAt)} — it stays as the record of that credit.'
        : mergedHere.isNotEmpty
            ? '${mergedHere.join(', ')} ${mergedHere.length == 1 ? 'is' : 'are'} merged into ${i.label} — '
                'it holds their "also suggested" people.'
            : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(blocked == null ? 'Delete ${i.label}?' : 'Can\'t delete ${i.label}', style: jost(18, weight: 600)),
        content: Text(blocked ??
            '"${i.text}"\n\nIt leaves the pool and is kept in ideas/removed_ideas.json, so nothing is lost. '
                '${i.label} won\'t be given to another idea.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(blocked == null ? 'Cancel' : 'OK')),
          if (blocked == null)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: HqColors.bad),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await IdeasStore.remove(i);
      _ideas.remove(i);
      await _save();
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t delete: $e');
    }
  }

  /// Give the credit — once per idea, to the one linked member.
  Future<void> _markCredited(Idea i) async {
    final who = '${_nameNow(i.memberId, i.from)} (${_gsmNow(i.memberId, i.gsmId)})';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Credit ${i.label}?', style: jost(18, weight: 600)),
        content: Text('Marks ${i.label} as credited to $who. This is recorded once and can\'t be moved '
            'to someone else afterwards. (HQ only notes it — give the reward in the usual way.)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Credit given')),
        ],
      ),
    );
    if (ok != true) return;
    i
      ..creditedAt = DateTime.now()
      ..updatedAt = DateTime.now();
    await _save();
  }

  Future<void> _setStatus(Idea i, String status) async {
    i.status = status;
    i.updatedAt = DateTime.now();
    await _save();
  }

  Future<void> _editNotes(Idea i) async {
    final c = TextEditingController(text: i.notes);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Notes', style: jost(18, weight: 600)),
        content: SizedBox(
          width: 460,
          child: TextField(controller: c, minLines: 3, maxLines: 8, autofocus: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      i.notes = c.text.trim();
      i.updatedAt = DateTime.now();
      await _save();
    }
    disposeLater([c]);
  }

  bool _shown(Idea i) {
    final statusOk = switch (_filter) {
      'open' => i.status == 'new' || i.status == 'thinking' || i.status == 'planned',
      'all' => true,
      _ => i.status == _filter,
    };
    final q = _search.text.trim().toLowerCase();
    final searchOk = q.isEmpty ||
        '${i.label} ${i.text} ${i.from} ${i.gsmId} ${_gsmNow(i.memberId, i.gsmId)} ${i.notes} ${i.app} '
                '${i.also.map((a) => '${a.name} ${a.gsmId}').join(' ')}'
            .toLowerCase()
            .contains(q);
    return statusOk && searchOk && (_appFilter == 'All' || i.app == _appFilter);
  }

  @override
  Widget build(BuildContext context) {
    final count = <String, int>{for (final s in IdeasStore.statuses.keys) s: 0};
    for (final i in _ideas) {
      count[i.status] = (count[i.status] ?? 0) + 1;
    }
    final shown = _ideas.where(_shown).toList();
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text('Ideas', style: jost(26, weight: 600)),
        const SizedBox(height: 4),
        Text('The idea pool. Each idea gets a number and ONE credited member (picked from the search). '
            'The same idea from someone else is added as "also suggested" — the credit stays with the first person. '
            'Move it along: New → Thinking → Planned → Done (or No). Deleted ideas go to ideas/removed_ideas.json. '
            'Kept on this Mac in gemstok_hq/ideas/ideas.json.',
            style: jost(14, color: HqColors.muted)),
        const SizedBox(height: 20),
        // ---- new idea
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HqColors.surface,
            border: Border.all(color: HqColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _text,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'The idea'),
              onChanged: (_) => setState(() {}),
            ),
            ..._similarBox(),
            const SizedBox(height: 10),
            Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(width: 320, child: _fromSearch()),
              DropdownButton<String>(
                value: _app,
                items: [for (final a in IdeasStore.apps) DropdownMenuItem(value: a, child: Text(a))],
                onChanged: (v) => setState(() => _app = v ?? _app),
              ),
              FilledButton(onPressed: _add, child: const Text('Save as a new idea')),
            ]),
            if (_from.text.trim().isNotEmpty && _fromMemberId.isEmpty) ...[
              const SizedBox(height: 6),
              Text('Not linked to a member — pick them from the list so the idea can be credited.',
                  style: jost(12, color: HqColors.warn)),
            ],
          ]),
        ),
        if (_error != null) ...[const SizedBox(height: 12), NoteBox(color: HqColors.bad, text: _error!)],
        const SizedBox(height: 20),
        // ---- filters
        Wrap(spacing: 16, runSpacing: 8, children: [
          Choice<String>(
            options: {
              'open': 'Open (${(count['new'] ?? 0) + (count['thinking'] ?? 0) + (count['planned'] ?? 0)})',
              for (final e in IdeasStore.statuses.entries) e.key: '${e.value} (${count[e.key] ?? 0})',
              'all': 'All (${_ideas.length})',
            },
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(labelText: 'Search ideas', prefixIcon: Icon(Icons.search, size: 18)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          DropdownButton<String>(
            value: _appFilter,
            items: [
              for (final a in ['All', ...IdeasStore.apps]) DropdownMenuItem(value: a, child: Text(a == 'All' ? 'All apps' : a)),
            ],
            onChanged: (v) => setState(() => _appFilter = v ?? 'All'),
          ),
        ]),
        const SizedBox(height: 12),
        if (shown.isEmpty) Text('Nothing here.', style: jost(13, color: HqColors.muted)),
        for (final i in shown) _card(i),
      ],
    );
  }

  /// While typing: ideas already in the pool that look the same.
  List<Widget> _similarBox() {
    final hits = IdeasStore.similar(_ideas.where((i) => i.mergedInto.isEmpty).toList(), _text.text);
    if (hits.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: HqColors.warn.withValues(alpha: 0.08),
          border: Border.all(color: HqColors.warn.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Already in the pool?', style: jost(13, weight: 600, color: HqColors.warn)),
          for (final i in hits)
            Row(children: [
              Expanded(
                child: Text(
                  '${i.label} · ${i.text} · credit: ${i.memberId.isEmpty ? (i.from.isEmpty ? 'nobody' : i.from) : _gsmNow(i.memberId, i.gsmId)}',
                  style: jost(13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(onPressed: () => _addAsAlso(i), child: const Text('Same idea → add as also suggested')),
            ]),
        ]),
      ),
    ];
  }

  Widget _card(Idea i) {
    final colour = switch (i.status) {
      'new' => HqColors.accent,
      'thinking' => HqColors.warn,
      'planned' => HqColors.accent,
      'done' => HqColors.good,
      _ => HqColors.muted,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HqColors.surface,
        border: Border.all(color: HqColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: SelectableText(i.text, style: jost(15, weight: 500))),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            tooltip: 'Change status',
            onSelected: (s) => _setStatus(i, s),
            itemBuilder: (_) => [
              for (final e in IdeasStore.statuses.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: colour),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${IdeasStore.statuses[i.status] ?? i.status} ▾',
                  style: jost(12, weight: 600, color: colour)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          [
            i.label,
            i.app,
            if (i.mergedInto.isNotEmpty)
              'merged into ${i.mergedInto}'
            else if (i.memberId.isNotEmpty)
              'credit: ${_nameNow(i.memberId, i.from)} (${_gsmNow(i.memberId, i.gsmId)})'
            else if (i.from.isNotEmpty)
              'from ${i.from} — not linked to a member',
            fmtDate(i.createdAt),
            if (i.updatedAt.difference(i.createdAt).inMinutes > 0) 'updated ${fmtDate(i.updatedAt)}',
          ].join(' · '),
          style: jost(12, color: HqColors.muted),
        ),
        if (i.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(i.notes, style: jost(13).copyWith(height: 1.4)),
        ],
        if (i.also.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Also suggested by: ${i.also.map((a) => '${_nameNow(a.memberId, a.name)}'
                '${a.memberId.isEmpty && a.gsmId.isEmpty ? '' : ' (${_gsmNow(a.memberId, a.gsmId)})'} ${fmtDate(a.at)}').join(' · ')}'
            ' — no credit',
            style: jost(12, color: HqColors.muted),
          ),
        ],
        Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
          if (_olderTwin(i) case final twin?)
            TextButton(
              onPressed: () => _merge(i, twin),
              child: Text('Same as ${twin.label}? Merge', style: const TextStyle(color: HqColors.warn)),
            ),
          if (i.mergedInto.isNotEmpty)
            const SizedBox.shrink()
          else if (i.creditedAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('✓ credit given ${fmtDate(i.creditedAt)}', style: jost(12, weight: 600, color: HqColors.good)),
            )
          else if (i.memberId.isEmpty)
            TextButton(onPressed: () => _linkMember(i), child: const Text('Link member'))
          else if (_olderTwin(i) == null)
            TextButton(onPressed: () => _markCredited(i), child: const Text('Mark credit given')),
          TextButton(onPressed: () => _editNotes(i), child: Text(i.notes.isEmpty ? 'Add notes' : 'Edit notes')),
          IconButton(
            tooltip: 'Delete idea',
            onPressed: () => _delete(i),
            icon: const Icon(Icons.delete_outline, size: 18, color: HqColors.muted),
          ),
        ]),
      ]),
    );
  }

  /// "From": type a name, username or GSM ID → pick a real member. Free text still works.
  Widget _fromSearch() {
    return RawAutocomplete<Map<String, dynamic>>(
      textEditingController: _from,
      focusNode: _fromFocus,
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
        _fromGsm = '${m['gemstok_id']}';
        _fromMemberId = '${m['id']}';
      }),
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        controller: controller,
        focusNode: focus,
        onChanged: (_) {
          if (_fromGsm.isNotEmpty) {
            setState(() {
              _fromGsm = ''; // typed over a picked member
              _fromMemberId = '';
            });
          } else {
            setState(() {});
          }
        },
        decoration: InputDecoration(
          labelText: 'From — search members, or type a name',
          helperText: _fromGsm.isEmpty ? null : 'member $_fromGsm',
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
                        Text(
                          '${m['gemstok_id']}${m['username'] == null ? '' : ' · @${m['username']}'}',
                          style: jost(12, color: HqColors.muted),
                        ),
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
}
