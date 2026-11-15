import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The ONLY place HQ keeps connection details: ONE item in the macOS Keychain.
///
/// That item holds, per project:  host (pooler address — not secret, shown in Settings)
///                                password (hq_reader's — secret, never shown, never logged)
/// One item = macOS asks "allow?" once per build, however many databases there are.
/// Screens can ask "is it set?" but can't read a password back; only db/hq_db.dart does.
class KeyStore {
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'gemstok_hq',
      accessibility: KeychainAccessibility.unlocked_this_device, // never leaves this Mac
      synchronizable: false, // not copied to iCloud Keychain
      // The normal login Keychain (encrypted, unlocked with your Mac login, items open
      // only for this app). The newer "data protection" Keychain needs a signed app with
      // the Keychain Sharing capability — without it macOS answers error -34018.
      useDataProtectionKeyChain: false,
    ),
  );

  static const _itemKey = 'hq.connections';

  /// Only Supabase pooler hosts are accepted, e.g. aws-0-ap-south-1.pooler.supabase.com
  static final poolerHost = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)*\.pooler\.supabase\.com$');

  // Kept in memory after the first read so macOS isn't asked again and again.
  // Wiped by forget() when HQ locks.
  static Map<String, Map<String, String>>? _cache;

  static Future<Map<String, Map<String, String>>> _all() async {
    if (_cache != null) return _cache!;
    final raw = await _storage.read(key: _itemKey);
    final map = <String, Map<String, String>>{};
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((id, v) => map[id] = Map<String, String>.from(v as Map));
    }
    _cache = map;
    return map;
  }

  static Future<void> _write(Map<String, Map<String, String>> map) async {
    await _storage.write(key: _itemKey, value: jsonEncode(map));
    _cache = map;
  }

  /// Moves entries saved by the first version (two items per project) into the one item.
  /// Runs once; afterwards the old items are gone.
  static Future<void> migrateOldItems(Iterable<String> projectIds) async {
    final map = Map<String, Map<String, String>>.from(await _all());
    var changed = false;
    for (final id in projectIds) {
      final oldHost = 'hq.$id.host', oldPw = 'hq.$id.password';
      if (await _storage.containsKey(key: oldPw)) {
        final host = await _storage.read(key: oldHost);
        final pw = await _storage.read(key: oldPw);
        if (host != null && pw != null && !map.containsKey(id)) {
          map[id] = {'host': host, 'password': pw};
          changed = true;
        }
        await _storage.delete(key: oldHost);
        await _storage.delete(key: oldPw);
      }
    }
    if (changed) await _write(map);
  }

  static Future<bool> isSet(String projectId) async {
    final e = (await _all())[projectId];
    return e != null && (e['host'] ?? '').isNotEmpty && (e['password'] ?? '').isNotEmpty;
  }

  static Future<String?> host(String projectId) async => (await _all())[projectId]?['host'];

  static Future<void> save(String projectId, {required String host, required String password}) async {
    final map = Map<String, Map<String, String>>.from(await _all());
    map[projectId] = {'host': host.trim().toLowerCase(), 'password': password};
    await _write(map);
  }

  static Future<void> remove(String projectId) async {
    final map = Map<String, Map<String, String>>.from(await _all());
    map.remove(projectId);
    await _write(map);
  }

  // ---- Supabase access tokens (Management API, used READ-ONLY by servers/supabase_api.dart) ----
  // Two slots, because the projects live in two Supabase accounts.
  static String _tokenId(int slot) => 'token:$slot';

  static Future<bool> hasToken(int slot) async => ((await _all())[_tokenId(slot)]?['token'] ?? '').isNotEmpty;

  static Future<void> saveToken(int slot, String token) async {
    final map = Map<String, Map<String, String>>.from(await _all());
    map[_tokenId(slot)] = {'token': token.trim()};
    await _write(map);
  }

  static Future<void> removeToken(int slot) => remove(_tokenId(slot));

  /// For servers/ only (and the Settings "Show" after Touch ID).
  static Future<String?> tokenForApi(int slot) async => (await _all())[_tokenId(slot)]?['token'];

  // ---- other services (Cloudflare, App Store Connect, Google Play, AdMob): fields per service ----
  static String _svcId(String service) => 'svc:$service';

  static Future<Map<String, String>> serviceFields(String service) async =>
      Map<String, String>.from((await _all())[_svcId(service)] ?? const {});

  static Future<void> saveServiceFields(String service, Map<String, String> fields) async {
    final map = Map<String, Map<String, String>>.from(await _all());
    final old = Map<String, String>.from(map[_svcId(service)] ?? const {});
    fields.forEach((k, v) {
      if (v.trim().isNotEmpty) old[k] = v.trim(); // empty field = keep what was there
    });
    map[_svcId(service)] = old;
    await _write(map);
  }

  static Future<void> removeService(String service) => remove(_svcId(service));

  /// Drop the in-memory copy (called when HQ locks).
  static void forget() => _cache = null;

  /// Only for the "Show" button in Settings, after a fresh Touch ID.
  static Future<String?> passwordToShow(String projectId) async => (await _all())[projectId]?['password'];

  /// For db/hq_db.dart only. Don't call this from a screen.
  static Future<String?> passwordForConnection(String projectId) async =>
      (await _all())[projectId]?['password'];
}
