import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'web.dart';

/// App Store Connect (read-only): daily sales reports (downloads, updates, in-app purchases,
/// proceeds) and the latest customer reviews.
/// Keys (App Store Connect → Users and Access → Integrations → App Store Connect API → Team key,
/// role "Sales" or "Finance"): Issuer ID, Key ID, the .p8 file's text, and your Vendor number
/// (Payments and Financial Reports, top left).
class AppStore {
  static const _host = 'api.appstoreconnect.apple.com';

  /// A token valid 19 minutes, signed here on the Mac with your key.
  static String token(Map<String, String> k) {
    final jwt = JWT(
      {'aud': 'appstoreconnect-v1'},
      issuer: k['issuer_id'],
      header: {'kid': k['key_id'], 'typ': 'JWT'},
    );
    return jwt.sign(ECPrivateKey(k['private_key']!.trim()), algorithm: JWTAlgorithm.ES256,
        expiresIn: const Duration(minutes: 19));
  }

  static Map<String, String> _auth(String t) => {'Authorization': 'Bearer $t'};

  /// [(appId, name)]
  static Future<List<(String, String)>> apps(String t) async {
    final j = await Web.getJson('App Store Connect',
        Uri.https(_host, '/v1/apps', {'fields[apps]': 'name,bundleId', 'limit': '50'}), headers: _auth(t)) as Map;
    return [for (final a in j['data'] as List) ('${a['id']}', '${a['attributes']['name']}')];
  }

  /// Newest reviews of one app: rating, title, body, date, territory.
  static Future<List<Map<String, dynamic>>> reviews(String t, String appId) async {
    final j = await Web.getJson(
        'App Store Connect',
        Uri.https(_host, '/v1/apps/$appId/customerReviews', {
          'sort': '-createdDate',
          'limit': '20',
          'fields[customerReviews]': 'rating,title,body,createdDate,territory',
        }),
        headers: _auth(t)) as Map;
    return [for (final r in j['data'] as List) Map<String, dynamic>.from(r['attributes'] as Map)];
  }

  /// One day's sales summary, summed per app title: downloads, re-downloads, updates, in-app units,
  /// proceeds per currency. Apple publishes a day about 1 day later; no sales that day → empty.
  static Future<Map<String, Map<String, dynamic>>> daySales(String t, String vendor, DateTime day) async {
    final date = day.toIso8601String().substring(0, 10);
    List<int> gz;
    try {
      gz = await Web.getBytes(
          'App Store sales',
          Uri.https(_host, '/v1/salesReports', {
            'filter[frequency]': 'DAILY',
            'filter[reportType]': 'SALES',
            'filter[reportSubType]': 'SUMMARY',
            'filter[vendorNumber]': vendor,
            'filter[reportDate]': date,
            'filter[version]': '1_0',
          }),
          headers: {..._auth(t), 'Accept': 'application/a-gzip'});
    } on WebError catch (e) {
      if (e.message.contains('404')) return {}; // no sales that day (or not published yet)
      rethrow;
    }
    final lines = const LineSplitter().convert(utf8.decode(gzip.decode(gz)));
    if (lines.isEmpty) return {};
    final head = lines.first.split('\t');
    int col(String name) => head.indexOf(name);
    final cTitle = col('Title'), cType = col('Product Type Identifier'), cUnits = col('Units');
    final cProceeds = col('Developer Proceeds'), cCur = col('Currency of Proceeds'), cParent = col('Parent Identifier');
    final out = <String, Map<String, dynamic>>{};
    for (final line in lines.skip(1)) {
      final f = line.split('\t');
      if (f.length < head.length) continue;
      final type = f[cType];
      final units = int.tryParse(f[cUnits]) ?? 0;
      // in-app purchases carry the app's SKU as parent; group them under the app title
      final title = f[cTitle];
      final app = out.putIfAbsent(f[cParent].isNotEmpty ? 'in-app · ${f[cParent]}' : title,
          () => {'downloads': 0, 'redownloads': 0, 'updates': 0, 'iap': 0, 'proceeds': <String, double>{}});
      if (const {'1', '1F', '1T', 'F1'}.contains(type)) app['downloads'] = (app['downloads'] as int) + units;
      if (const {'3', '3F', '3T', 'F3'}.contains(type)) app['redownloads'] = (app['redownloads'] as int) + units;
      if (const {'7', '7F', '7T', 'F7'}.contains(type)) app['updates'] = (app['updates'] as int) + units;
      if (type.startsWith('IA') || type == 'FI1') app['iap'] = (app['iap'] as int) + units;
      final p = (double.tryParse(f[cProceeds]) ?? 0) * units;
      if (p != 0) {
        final m = app['proceeds'] as Map<String, double>;
        m[f[cCur]] = (m[f[cCur]] ?? 0) + p;
      }
    }
    return out;
  }
}
