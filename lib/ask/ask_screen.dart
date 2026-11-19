import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';
import 'ask_store.dart';

/// Type a question → saved with a snapshot of the numbers → say "answer" in the Claude chat →
/// the answer appears here (HQ checks every 10 seconds).
class AskScreen extends StatefulWidget {
  const AskScreen({super.key, required this.data});
  final HqData data;

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _question = TextEditingController();
  List<AskItem> _items = [];
  bool _saving = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _question.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await AskStore.list();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    if (_question.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AskStore.save(_question.text, widget.data);
      _question.clear();
      await _load();
    } catch (e) {
      _error = 'Couldn\'t save: $e';
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _items.where((i) => i.answer == null).length;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text('ASK', style: jost(26, weight: 600, color: HqColors.claude)),
        const SizedBox(height: 4),
        Text(
            'Save a question here, then say "answer" in the Claude chat. Each question is saved with a snapshot '
            'of the numbers (counts only — no names). Answers appear below within 10 seconds.',
            style: jost(14, color: HqColors.muted)),
        const SizedBox(height: 20),
        TextField(
          controller: _question,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Your question, e.g. "Why did sign-ups drop this week?"'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HqColors.claude),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving with fresh numbers…' : 'Save question'),
          ),
          const SizedBox(width: 14),
          if (waiting > 0)
            Text('$waiting waiting — say "answer" in the Claude chat', style: jost(13, color: HqColors.warn)),
        ]),
        const SizedBox(height: 10),
        if (_error != null) NoteBox(color: HqColors.bad, text: _error!),
        const SizedBox(height: 10),
        for (final i in _items) _AskCard(item: i),
        if (_items.isEmpty) Text('No questions yet.', style: jost(13, color: HqColors.muted)),
      ],
    );
  }
}

class _AskCard extends StatelessWidget {
  const _AskCard({required this.item});
  final AskItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: HqColors.surface,
        border: Border(
            left: BorderSide(color: HqColors.claude, width: 3),
            top: BorderSide(color: HqColors.line),
            right: BorderSide(color: HqColors.line),
            bottom: BorderSide(color: HqColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(item.question, style: jost(15, weight: 600))),
            Text(fmtDateTime(item.askedAt), style: jost(12, color: HqColors.muted)),
          ]),
          const SizedBox(height: 10),
          item.answer == null
              ? Text('Waiting for Claude…', style: jost(13, color: HqColors.warn))
              : SelectableText(item.answer!, style: jost(14).copyWith(height: 1.45)),
        ],
      ),
    );
  }
}
