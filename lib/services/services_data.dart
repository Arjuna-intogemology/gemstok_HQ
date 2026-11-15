import 'dart:async';

import 'package:flutter/foundation.dart';

import '../blogs/blog_api.dart';
import '../settings/key_store.dart';
import 'admob.dart';
import 'app_store.dart';
import 'cloudflare.dart';
import 'google_play.dart';

/// One key field a service needs (typed into Settings → Other services, kept in the Keychain).
class ServiceField {
  const ServiceField(this.key, this.label, {this.secret = false, this.multiline = false, this.optional = false});
  final String key;
  final String label;
  final bool secret;
  final bool multiline;
  final bool optional;
}

class ServiceInfo {
  const ServiceInfo(this.id, this.name, this.shows, this.how, this.fields);
  final String id;
  final String name;
  final String shows; // what HQ shows with it
  final String how; // where to make the key
  final List<ServiceField> fields;
}

const hqServices = [
  ServiceInfo(
    'blogadmin',
    'Blog admin (5 blogs)',
    'Lets HQ → Blogs write posts — the same login as internal.gemstok.com/blog.html.',
    'The e-mail + password of the Supabase account that is a blog admin in the IntoGemology database '
        '(the one you sign in with on the blog admin page). Every change in HQ still asks for Touch ID.',
    [ServiceField('email', 'Admin e-mail'), ServiceField('password', 'Admin password', secret: true)],
  ),
  ServiceInfo(
    'cloudflare',
    'Cloudflare',
    'Visits per day for each website (Websites).',
    'dash.cloudflare.com → My Profile → API Tokens → Create Token → template "Read analytics and logs" '
        '→ Zone resources: All zones. Read-only.',
    [ServiceField('api_token', 'API token', secret: true)],
  ),
  ServiceInfo(
    'appstore',
    'App Store Connect',
    'iPhone downloads, updates and reviews (Downloads); in-app purchases and proceeds (Money).',
    'appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API → Team Keys → '
        '"+" → name "Gemstok HQ", access "Sales". Download the .p8 once (open it in TextEdit and copy all of it). '
        'Vendor number: Payments and Financial Reports, top left.',
    [
      ServiceField('issuer_id', 'Issuer ID'),
      ServiceField('key_id', 'Key ID'),
      ServiceField('private_key', 'Private key (.p8 text, incl. BEGIN/END lines)', secret: true, multiline: true),
      ServiceField('vendor_number', 'Vendor number'),
    ],
  ),
  ServiceInfo(
    'googleplay',
    'Google Play',
    'Android installs, uninstalls, active devices and reviews (Downloads).',
    'console.cloud.google.com (project of the apps) → IAM → Service Accounts → Create "gemstok-hq-reader" '
        '(no roles) → Keys → Add key → JSON. Then Play Console → Users and permissions → Invite that e-mail with ONLY '
        '"View app information and download bulk reports". Bucket: Play Console → Download reports → Statistics → '
        'Copy Cloud Storage URI. Also enable "Google Play Android Developer API" in Cloud.',
    [
      ServiceField('service_account_json', 'Service account JSON (all of the file)', secret: true, multiline: true),
      ServiceField('bucket_uri', 'Reports bucket (gs://pubsite_prod_rev_…)'),
      ServiceField('packages', 'Package names, comma-separated (empty = ManiKVault, Gem Broker, Quvlet, GemsGo)', optional: true),
    ],
  ),
  ServiceInfo(
    'admob',
    'AdMob',
    'Ad earnings, impressions and clicks per app per day (Money).',
    'console.cloud.google.com → enable "AdMob API" → consent screen: External, Testing, add yourself as Test user → '
        'Clients → Create client → "Desktop app". Copy client ID + secret. '
        'Publisher ID: AdMob → Settings → Account information (pub-…). Then press "Sign in with Google".',
    [
      ServiceField('client_id', 'OAuth client ID'),
      ServiceField('client_secret', 'OAuth client secret', secret: true),
      ServiceField('publisher_id', 'Publisher ID (pub-…)'),
    ],
  ),
];

/// What one service gave back, plus its state.
class ServiceState {
  bool keysSet = false;
  bool loading = false;
  String? error;
  DateTime? loadedAt;
}

/// The outside services, read-only, kept in memory while HQ is unlocked. Refreshes every hour
/// (these numbers move once a day at most).
class ServicesData extends ChangeNotifier {
  ServicesData() {
    _timer = Timer.periodic(const Duration(hours: 1), (_) => refreshAll());
    Future.microtask(refreshAll);
  }

  static const defaultPackages = ['com.gemstok.manikvault', 'com.gemstok.gembroker', 'com.gemstok.quvlet', 'com.gemstok.origin'];

  final state = {for (final s in hqServices) s.id: ServiceState()};

  // Cloudflare: site name → days (date, requests, pageViews, uniques, bytes, threats)
  final cfDaily = <String, List<Map<String, dynamic>>>{};
  // App Store: day → title → {downloads, redownloads, updates, iap, proceeds{cur: amount}}
  final asSales = <DateTime, Map<String, Map<String, dynamic>>>{};
  final asReviews = <String, List<Map<String, dynamic>>>{}; // app name → newest reviews
  // Google Play: package → rows of Play's install report (this + last month)
  final playInstalls = <String, List<Map<String, String>>>{};
  final playReviews = <String, List<Map<String, dynamic>>>{};
  // AdMob: rows (date, app, earnings, impressions, clicks)
  var admobRows = <Map<String, dynamic>>[];

  Timer? _timer;
  bool _disposed = false;

  static ServiceInfo info(String id) => hqServices.firstWhere((s) => s.id == id);

  /// All the needed fields are filled (AdMob also needs the Google sign-in).
  static bool ready(String id, Map<String, String> k) =>
      info(id).fields.every((f) => f.optional || (k[f.key] ?? '').isNotEmpty) &&
      (id != 'admob' || (k['refresh_token'] ?? '').isNotEmpty);

  Future<void> refreshAll() async {
    for (final s in hqServices) {
      await refresh(s.id);
    }
  }

  Future<void> refresh(String id) async {
    final st = state[id]!;
    if (st.loading || _disposed) return;
    final k = await KeyStore.serviceFields(id);
    st.keysSet = ready(id, k);
    if (!st.keysSet) {
      st.error = null;
      _notify();
      return;
    }
    st.loading = true;
    _notify();
    try {
      switch (id) {
        case 'cloudflare':
          await _cloudflare(k);
        case 'appstore':
          await _appStore(k);
        case 'googleplay':
          await _googlePlay(k);
        case 'admob':
          await _admob(k);
        case 'blogadmin':
          await BlogApi.check();
      }
      st.error = null;
      st.loadedAt = DateTime.now();
    } catch (e) {
      st.error = '$e';
    }
    st.loading = false;
    _notify();
  }

  Future<void> _cloudflare(Map<String, String> k) async {
    final t = k['api_token']!;
    final zones = await Cloudflare.zones(t);
    final next = <String, List<Map<String, dynamic>>>{};
    for (final (id, name) in zones) {
      next[name] = await Cloudflare.daily(t, id);
    }
    cfDaily
      ..clear()
      ..addAll(next);
  }

  Future<void> _appStore(Map<String, String> k) async {
    final t = AppStore.token(k);
    final today = DateTime.now();
    final day0 = DateTime.utc(today.year, today.month, today.day);
    // last 30 days; days older than 3 days don't change any more, so they're loaded once per unlock
    for (var i = 1; i <= 30; i++) {
      final d = day0.subtract(Duration(days: i));
      if (i > 3 && asSales.containsKey(d)) continue;
      asSales[d] = await AppStore.daySales(t, k['vendor_number']!.trim(), d);
    }
    asReviews.clear();
    for (final (appId, name) in await AppStore.apps(t)) {
      asReviews[name] = await AppStore.reviews(t, appId);
    }
  }

  Future<void> _googlePlay(Map<String, String> k) async {
    final t = await GooglePlay.accessToken(k);
    final bucket = GooglePlay.bucketOf(k['bucket_uri']!);
    final pk = (k['packages'] ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final now = DateTime.now();
    String ym(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}';
    final months = [ym(DateTime(now.year, now.month - 1)), ym(now)];
    playInstalls.clear();
    playReviews.clear();
    for (final p in pk.isEmpty ? defaultPackages : pk) {
      playInstalls[p] = [for (final m in months) ...await GooglePlay.installs(t, bucket, p, m)];
      try {
        playReviews[p] = await GooglePlay.reviews(t, p);
      } catch (_) {
        playReviews[p] = const []; // reviews need the Android Developer API; installs still show
      }
    }
  }

  Future<void> _admob(Map<String, String> k) async {
    final t = await AdMob.accessToken(k);
    admobRows = await AdMob.earnings(t, k['publisher_id']!.trim());
  }

  /// One-time Google sign-in for AdMob; keeps the refresh token in the Keychain.
  Future<void> admobSignIn() async {
    final k = await KeyStore.serviceFields('admob');
    final token = await AdMob.signIn(k);
    await KeyStore.saveServiceFields('admob', {'refresh_token': token});
    await refresh('admob');
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
