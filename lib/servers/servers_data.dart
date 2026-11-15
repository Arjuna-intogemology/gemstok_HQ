import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/key_store.dart';
import 'supabase_api.dart';

/// What HQ knows from the Supabase Management API (read-only), kept in memory while unlocked.
/// · Which token (account slot 1 or 2) sees which project, found by listing each token's projects.
/// · Each project's status (Active / Paused / …) and its edge functions.
/// Refreshes every 10 minutes (Supabase rate-limits this API, so not more often).
class ServersData extends ChangeNotifier {
  ServersData() {
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => refresh());
    Future.microtask(refresh);
  }

  static const slots = [1, 2];

  final projects = <String, Map<String, dynamic>>{}; // ref → project info from /v1/projects
  final slotOf = <String, int>{}; // ref → which token sees it
  final functions = <String, List<Map<String, dynamic>>>{}; // ref → functions
  final tokenErrors = <int, String>{};
  final functionErrors = <String, String>{};
  final tokenSet = <int, bool>{};
  DateTime? loadedAt;
  bool loading = false;
  Timer? _timer;
  bool _disposed = false;

  bool get anyToken => tokenSet.values.any((v) => v);

  Future<String?> tokenFor(String ref) async {
    final slot = slotOf[ref];
    return slot == null ? null : KeyStore.tokenForApi(slot);
  }

  Future<void> refresh() async {
    if (loading || _disposed) return;
    loading = true;
    _notify();
    projects.clear();
    slotOf.clear();
    for (final slot in slots) {
      tokenSet[slot] = await KeyStore.hasToken(slot);
      if (!tokenSet[slot]!) continue;
      try {
        final token = await KeyStore.tokenForApi(slot);
        for (final p in await SupabaseApi.projects(token!)) {
          final ref = '${p['ref'] ?? p['id']}';
          projects[ref] = p;
          slotOf[ref] = slot;
        }
        tokenErrors.remove(slot);
      } catch (e) {
        tokenErrors[slot] = '$e';
      }
    }
    for (final ref in projects.keys) {
      try {
        functions[ref] = await SupabaseApi.functions((await tokenFor(ref))!, ref);
        functionErrors.remove(ref);
      } catch (e) {
        functionErrors[ref] = '$e';
      }
    }
    loadedAt = DateTime.now();
    loading = false;
    _notify();
  }

  /// "Active", "Paused", … from Supabase's status words.
  static (String, bool ok) statusText(String? s) => switch (s) {
        'ACTIVE_HEALTHY' => ('Active', true),
        'ACTIVE_UNHEALTHY' => ('Active — unhealthy', false),
        'INACTIVE' => ('PAUSED', false),
        'PAUSING' => ('Pausing…', false),
        'RESTORING' || 'COMING_UP' || 'RESTARTING' || 'UPGRADING' => ('Starting…', false),
        'INIT_FAILED' || 'REMOVED' => ('Not available', false),
        null => ('—', false),
        _ => (s, false),
      };

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
