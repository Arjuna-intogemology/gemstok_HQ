import 'dart:convert';
import 'dart:io';

/// How many HQ opens have shown each "restore approved" notice (request id → count).
/// After 5 HQ opens (of the Restore requests page) a notice stops showing there. Kept on this Mac only:
/// ~/Library/Application Support/Gemstok HQ/restore_seen.json (ids + counts, nothing personal).
class RestoreSeenStore {
  static const maxOpens = 5;
  static final _countedThisRun = <String>{};
  static Map<String, int>? _cache;

  static File get _file =>
      File('${Platform.environment['HOME']}/Library/Application Support/Gemstok HQ/restore_seen.json');

  static Map<String, int> _load() {
    if (_cache != null) return _cache!;
    try {
      final j = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      _cache = j.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  static void _save() {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(_cache ?? {}));
    } catch (_) {}
  }

  /// Call when the notice is on screen. Counts once per HQ run (one "open"). Returns the open number (1–5).
  static int seen(String id) {
    final m = _load();
    if (_countedThisRun.add(id)) {
      m[id] = (m[id] ?? 0) + 1;
      _save();
    }
    return m[id] ?? 1;
  }

  /// true = still to show (fewer than 5 HQ opens so far, or this run already counted it).
  static bool show(String id) {
    final n = _load()[id] ?? 0;
    return n < maxOpens || (_countedThisRun.contains(id) && n <= maxOpens);
  }
}
