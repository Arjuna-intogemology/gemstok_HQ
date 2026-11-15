import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

import '../db/hq_db.dart';
import '../db/projects.dart';
import '../db/queries.dart';
import '../settings/key_store.dart';

/// Keeps free-plan Supabase projects from pausing by doing REAL reads (counting each project's
/// main table — members, stones, follows, conversations, posts…), and counts down the days.
///
/// · Every successful HQ read of a project counts (screens, refreshes, pings).
/// · While HQ is open: any connected project not read for 20 hours gets a real read automatically.
/// · The "last real read" times are kept in  ~/Library/Application Support/gemstok_hq/keep_alive.json
///   (dates + row counts only, no keys), so the countdown survives restarts.
/// Supabase decides when a project pauses (about 7 days without use); this is the best signal HQ can send.
class HqKeepAlive extends ChangeNotifier {
  HqKeepAlive() {
    _load();
    _timer = Timer.periodic(const Duration(hours: 1), (_) => pingDue());
    _first = Timer(const Duration(seconds: 20), pingDue);
  }

  static const pauseAfter = Duration(days: 7);
  static const pingEvery = Duration(hours: 20);

  final _last = <String, DateTime>{}; // project id → last successful real read
  final _rows = <String, int>{}; // project id → row count seen by the last ping
  final _errors = <String, String>{};
  final _busy = <String>{};
  Timer? _timer;
  Timer? _first;
  bool _disposed = false;

  DateTime? last(String projectId) => _last[projectId];
  int? rows(String projectId) => _rows[projectId];
  String? error(String projectId) => _errors[projectId];
  bool busy(String projectId) => _busy.contains(projectId);

  /// Time left before the pause risk (negative = overdue). null = never read by HQ.
  Duration? left(String projectId) {
    final l = _last[projectId];
    return l == null ? null : pauseAfter - DateTime.now().difference(l);
  }

  static File get _file =>
      File('${Platform.environment['HOME']}/Library/Application Support/gemstok_hq/keep_alive.json');

  Future<void> _load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      (j['last'] as Map<String, dynamic>? ?? {}).forEach((k, v) => _last[k] = DateTime.parse(v as String));
      (j['rows'] as Map<String, dynamic>? ?? {}).forEach((k, v) => _rows[k] = v as int);
      _notify();
    } catch (_) {
      // unreadable file → start fresh
    }
  }

  Future<void> _save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode({
        'last': _last.map((k, v) => MapEntry(k, v.toIso8601String())),
        'rows': _rows,
      }));
    } catch (_) {}
  }

  /// Called by HqData after any successful read of a project.
  void markRead(String projectId) {
    _last[projectId] = DateTime.now();
    _errors.remove(projectId);
    _save();
    _notify();
  }

  /// A real read now: count the project's main table.
  Future<void> ping(HqProject project) async {
    if (_busy.contains(project.id)) return;
    final sql = Q.pingSql[project.id];
    if (sql == null) return;
    if (!await KeyStore.isSet(project.id)) {
      _errors[project.id] = 'not connected — add its key in Settings';
      _notify();
      return;
    }
    _busy.add(project.id);
    _notify();
    Connection? conn;
    try {
      conn = await HqDb.open(project);
      final r = await conn.execute(sql);
      _rows[project.id] = r.first[0] as int;
      markRead(project.id);
    } catch (e) {
      _errors[project.id] = '$e';
    } finally {
      await conn?.close();
      _busy.remove(project.id);
      _notify();
    }
  }

  /// Every connected project not read for [pingEvery] gets a real read.
  Future<void> pingDue() async {
    for (final p in hqProjects) {
      if (_disposed) return;
      final l = _last[p.id];
      if (l != null && DateTime.now().difference(l) < pingEvery) continue;
      if (!await KeyStore.isSet(p.id)) continue;
      await ping(p);
    }
    // These may run while HQ is locked: don't leave passwords in memory afterwards.
    KeyStore.forget();
  }

  Future<void> pingAll() async {
    for (final p in hqProjects) {
      if (await KeyStore.isSet(p.id)) await ping(p);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _first?.cancel();
    super.dispose();
  }
}
