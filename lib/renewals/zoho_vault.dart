import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Zoho mailbox passwords — ONE item in the macOS Keychain ("hq.zoho"), same rules as KeyStore:
/// this Mac only, never iCloud, never shown, never logged. You type them in HQ → Renewals → Email.
/// Only ZohoLogin reads them back (to fill Zoho's sign-in page). Screens only ask "set or not".
class ZohoVault {
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'gemstok_hq',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
      useDataProtectionKeyChain: false,
    ),
  );
  static const _itemKey = 'hq.zoho';
  static Map<String, String>? _cache; // wiped by forget() when HQ locks

  static Future<Map<String, String>> _all() async {
    if (_cache != null) return _cache!;
    final raw = await _storage.read(key: _itemKey);
    _cache = raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
    return _cache!;
  }

  static Future<void> _write(Map<String, String> m) async {
    await _storage.write(key: _itemKey, value: jsonEncode(m));
    _cache = m;
  }

  static String _k(String address) => address.trim().toLowerCase();

  static Future<Set<String>> addressesSet() async => (await _all()).keys.toSet();

  static Future<void> set(String address, String password) async {
    final m = Map<String, String>.from(await _all());
    m[_k(address)] = password;
    await _write(m);
  }

  static Future<void> remove(String address) async {
    final m = Map<String, String>.from(await _all())..remove(_k(address));
    await _write(m);
  }

  /// Only for ZohoLogin.
  static Future<String?> passwordFor(String address) async => (await _all())[_k(address)];

  static void forget() => _cache = null;
}
