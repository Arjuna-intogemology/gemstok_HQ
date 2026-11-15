import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'web.dart';

/// Google Play (read-only): daily installs from Play's report files, and the last week's reviews.
/// Keys:
///   · a Google Cloud service account's JSON key (project gemstok-490000 → IAM → Service accounts →
///     new "gemstok-hq-reader" → Keys → Add key → JSON), invited in Play Console → Users and permissions
///     with only "View app information and download bulk reports"
///   · the reports bucket: Play Console → Download reports → Statistics → "Copy Cloud Storage URI"
///     (gs://pubsite_prod_rev_…)
///   · package names (default: ManiKVault + Gem Broker)
class GooglePlay {
  static Future<String> accessToken(Map<String, String> k) async {
    final sa = jsonDecode(k['service_account_json']!) as Map<String, dynamic>;
    final tokenUri = (sa['token_uri'] as String?) ?? 'https://oauth2.googleapis.com/token';
    final assertion = JWT(
      {
        'scope': 'https://www.googleapis.com/auth/devstorage.read_only '
            'https://www.googleapis.com/auth/androidpublisher',
        'aud': tokenUri,
      },
      issuer: sa['client_email'] as String,
    ).sign(RSAPrivateKey(sa['private_key'] as String), algorithm: JWTAlgorithm.RS256,
        expiresIn: const Duration(minutes: 50));
    final j = await Web.postForm('Google sign-in', Uri.parse(tokenUri), {
      'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      'assertion': assertion,
    }) as Map;
    return j['access_token'] as String;
  }

  static String bucketOf(String uriOrName) =>
      uriOrName.trim().replaceFirst('gs://', '').split('/').first;

  /// Play's install report rows for one app and one month (YYYYMM). Empty if the file isn't there yet.
  static Future<List<Map<String, String>>> installs(String token, String bucket, String pkg, String yyyymm) async {
    final object = 'stats/installs/installs_${pkg}_${yyyymm}_overview.csv';
    List<int> bytes;
    try {
      bytes = await Web.getBytes(
          'Google Play reports',
          Uri.https('storage.googleapis.com', '/storage/v1/b/$bucket/o/${Uri.encodeComponent(object)}',
              {'alt': 'media'}),
          headers: {'Authorization': 'Bearer $token'});
    } on WebError catch (e) {
      if (e.message.contains('404')) return [];
      rethrow;
    }
    final text = _decode(bytes);
    final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return [];
    final head = lines.first.split(',').map((h) => h.trim()).toList();
    return [
      for (final l in lines.skip(1))
        {for (var i = 0; i < head.length; i++) head[i]: (l.split(',').elementAtOrNull(i) ?? '').trim()},
    ];
  }

  /// Play's CSV files are UTF-16 (little-endian, with a BOM).
  static String _decode(List<int> b) {
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
      final units = <int>[for (var i = 2; i + 1 < b.length; i += 2) b[i] | (b[i + 1] << 8)];
      return String.fromCharCodes(units);
    }
    return utf8.decode(b, allowMalformed: true);
  }

  /// Reviews with text from the last 7 days (that's all the Play API gives).
  static Future<List<Map<String, dynamic>>> reviews(String token, String pkg) async {
    final j = await Web.getJson(
        'Google Play reviews',
        Uri.https('androidpublisher.googleapis.com', '/androidpublisher/v3/applications/$pkg/reviews',
            {'maxResults': '20'}),
        headers: {'Authorization': 'Bearer $token'}) as Map;
    return [
      for (final r in (j['reviews'] as List? ?? const []))
        {
          'rating': r['comments']?[0]?['userComment']?['starRating'],
          'text': '${r['comments']?[0]?['userComment']?['text'] ?? ''}'.trim(),
          'seconds': int.tryParse('${r['comments']?[0]?['userComment']?['lastModified']?['seconds'] ?? ''}'),
        },
    ];
  }
}
