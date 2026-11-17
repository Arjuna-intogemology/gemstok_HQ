import 'dart:convert';
import 'dart:io';

/// Things that EXPIRE and must be renewed by hand (keys, secrets, sign-ins, memberships).
/// Kept in  gemstok_hq/renewals/renewals.json  — dates only, never the keys themselves. Fine in git.
class Renewal {
  Renewal({
    required this.id,
    required this.name,
    required this.what,
    required this.lifetimeDays,
    this.made,
    this.howTo = '',
    this.notes = '',
  });

  final String id;
  String name;
  String what; // what breaks when it expires
  int lifetimeDays; // 0 = no fixed lifetime (set the expiry date by hand)
  DateTime? made; // when it was last made / renewed
  DateTime? expiresOverride; // an exact expiry, when known (e.g. read from the secret itself)
  String howTo; // where the steps are
  String notes;

  DateTime? get expires => expiresOverride ?? (made == null || lifetimeDays == 0 ? null : made!.add(Duration(days: lifetimeDays)));

  /// Days left (negative = expired); null when no date is known.
  int? get daysLeft {
    final e = expires;
    if (e == null) return null;
    final now = DateTime.now();
    return DateTime(e.year, e.month, e.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'what': what,
        'lifetime_days': lifetimeDays,
        if (made != null) 'made': made!.toIso8601String().substring(0, 10),
        if (expiresOverride != null) 'expires': expiresOverride!.toIso8601String().substring(0, 10),
        'how_to': howTo,
        'notes': notes,
      };

  static Renewal fromJson(Map<String, dynamic> j) => Renewal(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        what: j['what'] as String? ?? '',
        lifetimeDays: (j['lifetime_days'] as num?)?.toInt() ?? 0,
        made: DateTime.tryParse(j['made'] as String? ?? ''),
        howTo: j['how_to'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
      )..expiresOverride = DateTime.tryParse(j['expires'] as String? ?? '');
}

class RenewalStore {
  static String get folder => '${Platform.environment['HOME']}/Development/Gemstok/gemstok_hq/renewals';
  static File get file => File('$folder/renewals.json');

  /// Warn this many days before.
  static const warnDays = 30;

  static Future<List<Renewal>> load() async {
    if (!await file.exists()) {
      final seed = _seed();
      await save(seed);
      return seed;
    }
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return [for (final r in (j['renewals'] as List? ?? const [])) Renewal.fromJson(r as Map<String, dynamic>)];
  }

  static Future<void> save(List<Renewal> list) async {
    await Directory(folder).create(recursive: true);
    final tmp = File('${file.path}.saving');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'about': 'Gemstok HQ renewals — dates only, never keys. Edit in HQ → Renewals (or here; HQ re-reads it).',
      'renewals': [for (final r in list) r.toJson()],
    }));
    await tmp.rename(file.path);
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// The things known to expire (dates unknown until you set them).
  static List<Renewal> _seed() => [
        Renewal(
          id: 'apple-signin-secret',
          name: 'Sign in with Apple — client secret',
          what: 'Apple sign-in on the websites and Android stops working for everyone (iPhone apps keep working).',
          lifetimeDays: 180,
          howTo: 'gemstok-backend/docs/runbooks/apple-client-secret.md → paste into Supabase → Gemstok → '
              'Authentication → Providers → Apple → Secret Key',
        ),
        Renewal(
          id: 'apple-developer',
          name: 'Apple Developer Program membership',
          what: 'Apps leave the App Store, TestFlight and Sign in with Apple stop.',
          lifetimeDays: 365,
          howTo: 'developer.apple.com → Account → Membership (turn on auto-renew)',
        ),
        Renewal(
          id: 'cloudflare-token',
          name: 'Cloudflare API token (Gemstok HQ)',
          what: 'HQ → Websites and the R2 pie stop loading.',
          lifetimeDays: 365,
          howTo: 'dash.cloudflare.com → My Profile → API Tokens → Gemstok HQ → Roll, then HQ → Settings → Replace',
          notes: 'Only if you chose "1 year" when making it. No expiry → set no date.',
        ),
        Renewal(
          id: 'admob-signin',
          name: 'AdMob sign-in in HQ (Google, Testing mode)',
          what: 'HQ → Money: AdMob turns red.',
          lifetimeDays: 7,
          howTo: 'HQ → Settings → Other services → AdMob → Sign in with Google',
          notes: 'Only while the consent screen is in Testing. "In production" → it doesn\'t expire; remove this.',
        ),
      ];
}
