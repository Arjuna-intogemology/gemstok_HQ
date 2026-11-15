import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

import '../settings/key_store.dart';
import 'hq_db.dart';
import 'queries.dart';

/// HQ's memory of loaded numbers (the cache).
///
/// · A screen says which queries it needs (use). Already loaded → shown at once, no DB call.
/// · Everything that has been used reloads every [refreshEvery] while HQ is unlocked.
/// · Refresh buttons reload a screen's queries now.
/// · Lives inside the unlocked shell: when HQ locks, this object (and every number) is thrown away.
class HqData extends ChangeNotifier {
  HqData({this.onRead}) {
    _timer = Timer.periodic(refreshEvery, (_) => refreshAll());
  }

  /// Called with a project id after a successful read (Keep alive uses it).
  final void Function(String projectId)? onRead;

  static const refreshEvery = Duration(minutes: 5);

  final _used = <String, HqQuery>{};
  final _rows = <String, List<Map<String, dynamic>>>{};
  final _loadedAt = <String, DateTime>{};
  final _errors = <String, String>{};
  final _loading = <String>{};
  final _notSet = <String>{}; // database has no key in Settings yet → shown as "not connected", not an error
  Timer? _timer;
  bool _disposed = false;

  List<Map<String, dynamic>>? rows(HqQuery q) => _rows[q.key];
  DateTime? loadedAt(HqQuery q) => _loadedAt[q.key];
  String? error(HqQuery q) => _errors[q.key];
  bool isLoading(HqQuery q) => _loading.contains(q.key);
  bool isNotSet(HqQuery q) => _notSet.contains(q.key);

  /// A screen needs these. Loads only the ones not in memory yet.
  void use(List<HqQuery> queries) {
    final missing = <HqQuery>[];
    for (final q in queries) {
      _used[q.key] = q;
      // Not loaded yet (or failed last time) → load. Already loaded → use memory.
      if (!_rows.containsKey(q.key) && !_notSet.contains(q.key) && !_loading.contains(q.key)) {
        missing.add(q);
      }
    }
    // After the current build — never change state in the middle of one.
    if (missing.isNotEmpty) Future.microtask(() => refresh(missing));
  }

  Future<void> refreshAll() => refresh(_used.values.toList());

  /// Reload [queries] now. One connection per database, closed straight after.
  Future<void> refresh(List<HqQuery> queries) async {
    final todo = queries.where((q) => !_loading.contains(q.key)).toList();
    if (todo.isEmpty || _disposed) return;
    _loading.addAll(todo.map((q) => q.key));
    _notify();

    final byProject = <String, List<HqQuery>>{};
    for (final q in todo) {
      byProject.putIfAbsent(q.projectId, () => []).add(q);
    }

    for (final group in byProject.values) {
      if (!await KeyStore.isSet(group.first.projectId)) {
        for (final q in group) {
          _notSet.add(q.key);
          _errors.remove(q.key);
        }
        continue;
      }
      for (final q in group) {
        _notSet.remove(q.key);
      }
      Connection? conn;
      try {
        conn = await HqDb.open(group.first.project);
        for (final q in group) {
          try {
            final result = await conn.execute(q.sql);
            _rows[q.key] = result.map((r) => r.toColumnMap()).toList();
            _loadedAt[q.key] = DateTime.now();
            _errors.remove(q.key);
            onRead?.call(q.projectId);
          } catch (e) {
            _errors[q.key] = '$e';
          }
        }
      } catch (e) {
        for (final q in group) {
          _errors[q.key] = '$e';
        }
      } finally {
        await conn?.close();
      }
    }

    _loading.removeAll(todo.map((q) => q.key));
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
