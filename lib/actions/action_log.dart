import 'dart:convert';
import 'dart:io';

/// Every change HQ makes is written here first — one JSON line per action:
///   ~/Library/Application Support/gemstok_hq/actions.log
/// what, when, the exact values, and whether it worked. Never keys or passwords.
class ActionLog {
  static File get _file =>
      File('${Platform.environment['HOME']}/Library/Application Support/gemstok_hq/actions.log');

  static Future<void> write(String action, Map<String, Object?> details, {required bool ok, String? error}) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        '${jsonEncode({
              'at': DateTime.now().toIso8601String(),
              'action': action,
              'details': details,
              'ok': ok,
              if (error != null) 'error': error,
            })}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // the action itself already happened or failed; a log write failure must not hide that
    }
  }

  /// Newest first.
  static Future<List<Map<String, dynamic>>> recent({int limit = 20}) async {
    if (!await _file.exists()) return [];
    final lines = await _file.readAsLines();
    final out = <Map<String, dynamic>>[];
    for (final l in lines.reversed) {
      if (l.trim().isEmpty) continue;
      try {
        out.add(jsonDecode(l) as Map<String, dynamic>);
      } catch (_) {}
      if (out.length >= limit) break;
    }
    return out;
  }
}
