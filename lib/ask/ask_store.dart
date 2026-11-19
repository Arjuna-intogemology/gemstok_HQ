import 'dart:convert';
import 'dart:io';

import '../db/hq_data.dart';
import '../db/queries.dart';
import '../ideas/ideas_store.dart';

/// "Ask Claude" without an API key:
///   HQ saves each question + a snapshot of the numbers as a file in  gemstok_hq/ask/questions/
///   In the Claude chat Arjuna says "answer"; Claude reads the waiting questions and writes
///   gemstok_hq/ask/answers/<id>.md  → HQ shows it.
/// The snapshot holds COUNTS and tables only — never names, usernames, email or phone.
/// The ask/ folder is in .gitignore (snapshots are business data, not code).
class AskStore {
  static String get folder =>
      '${Platform.environment['HOME']}/Development/Gemstok/gemstok_hq/ask';

  /// Queries whose results may go into a snapshot. Never newest_members / people lookups (names).
  static const shareable = [
    Q.today, Q.joining, Q.active, Q.retention, Q.credits, Q.traderReports,
    Q.mkvStones, Q.mkvListingsPerDay, Q.mkvBoostViews, Q.mkvStoneReports,
    Q.socialFollows, Q.chatCounts, Q.gemmitCounts, Q.gemmitPostReports, Q.siteLeads, Q.quvletCounts, Q.traceCounts,
  ];

  static Directory get _questions => Directory('$folder/questions');
  static Directory get _answers => Directory('$folder/answers');

  /// Reloads the shareable numbers, then saves the question with them.
  static Future<void> save(String question, HqData data) async {
    await data.refresh(shareable);
    final now = DateTime.now();
    final id = '${now.year}-${_two(now.month)}-${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final snapshot = <String, dynamic>{};
    for (final q in shareable) {
      final rows = data.rows(q);
      if (rows == null) continue;
      snapshot[q.key] = {
        'source': q.source,
        'loaded_at': data.loadedAt(q)?.toIso8601String(),
        'rows': rows,
      };
    }
    try {
      snapshot['ideas'] = {
        'source': 'HQ → Ideas (who suggested it is left out)',
        'rows': [
          for (final i in await IdeasStore.load())
            {'idea': i.text, 'app': i.app, 'status': i.status, 'notes': i.notes, 'noted': i.createdAt.toIso8601String()},
        ],
      };
    } catch (_) {}
    await _questions.create(recursive: true);
    await _answers.create(recursive: true);
    final file = File('${_questions.path}/$id.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ', _toJson).convert({
      'id': id,
      'asked_at': now.toIso8601String(),
      'question': question.trim(),
      'notes': 'Days are Sri Lanka days. Test purchases left out of credits. '
          '"Active" = opened ManiKVault Browse / Gem Broker Market / Quvlet. '
          'A query missing from the snapshot = that database is not connected in HQ yet.',
      'snapshot': snapshot,
    }));
  }

  /// All questions, newest first, with their answer if Claude has written one.
  static Future<List<AskItem>> list() async {
    if (!await _questions.exists()) return [];
    final items = <AskItem>[];
    await for (final f in _questions.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final id = j['id'] as String;
        final answer = File('${_answers.path}/$id.md');
        items.add(AskItem(
          id: id,
          askedAt: DateTime.parse(j['asked_at'] as String),
          question: j['question'] as String,
          answer: await answer.exists() ? await answer.readAsString() : null,
        ));
      } catch (_) {
        // a half-written file — skip it this time
      }
    }
    items.sort((a, b) => b.askedAt.compareTo(a.askedAt));
    return items;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Dates → text; anything else the JSON encoder doesn't know → text.
  static Object? _toJson(Object? v) => v is DateTime ? v.toIso8601String() : '$v';
}

class AskItem {
  const AskItem({required this.id, required this.askedAt, required this.question, this.answer});
  final String id;
  final DateTime askedAt;
  final String question;
  final String? answer;
}
