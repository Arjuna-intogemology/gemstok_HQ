import 'web.dart';

/// Cloudflare (read-only): your zones (sites) and per-day traffic for the last 30 days.
/// Key: an API token with "Zone · Analytics · Read" and "Zone · Zone · Read" (Cloudflare →
/// My Profile → API Tokens → Create token → "Read analytics and logs" template).
class Cloudflare {
  static final _api = Uri.https('api.cloudflare.com', '/client/v4');

  static Map<String, String> _auth(String token) => {'Authorization': 'Bearer $token'};

  /// [(zoneId, name)]
  static Future<List<(String, String)>> zones(String token) async {
    final j = await Web.getJson('Cloudflare', _api.replace(path: '/client/v4/zones', queryParameters: {'per_page': '50'}),
        headers: _auth(token)) as Map;
    if (j['success'] != true) throw WebError('Cloudflare: ${j['errors']}');
    return [for (final z in j['result'] as List) ('${z['id']}', '${z['name']}')];
  }

  /// The account IDs behind your zones (R2 belongs to the account, not to a site).
  static Future<Set<String>> accountIds(String token) async {
    final j = await Web.getJson('Cloudflare', _api.replace(path: '/client/v4/zones', queryParameters: {'per_page': '50'}),
        headers: _auth(token)) as Map;
    if (j['success'] != true) throw WebError('Cloudflare: ${j['errors']}');
    return {for (final z in j['result'] as List) if (z['account']?['id'] != null) '${z['account']['id']}'};
  }

  /// R2 buckets (photos): latest size + file count per bucket, from Cloudflare's R2 storage analytics
  /// (needs "Account Analytics: Read" on the token). Bytes = payload + metadata.
  static Future<List<Map<String, dynamic>>> r2Buckets(String token, String accountId) async {
    final end = DateTime.now().toUtc();
    final start = end.subtract(const Duration(days: 2));
    const query = r'''
query ($acc: string!, $start: Time, $end: Time) {
  viewer {
    accounts(filter: { accountTag: $acc }) {
      r2StorageAdaptiveGroups(limit: 1000, filter: { datetime_geq: $start, datetime_leq: $end }, orderBy: [datetime_DESC]) {
        max { objectCount payloadSize metadataSize }
        dimensions { bucketName datetime }
      }
    }
  }
}''';
    final j = await Web.postJson('Cloudflare R2', Uri.https('api.cloudflare.com', '/client/v4/graphql'),
        {'query': query, 'variables': {'acc': accountId, 'start': start.toIso8601String(), 'end': end.toIso8601String()}},
        headers: _auth(token)) as Map;
    if (j['errors'] != null && (j['errors'] as List).isNotEmpty) throw WebError('Cloudflare R2: ${j['errors']}');
    final accounts = (j['data']?['viewer']?['accounts'] as List?) ?? const [];
    if (accounts.isEmpty) return [];
    final latest = <String, Map<String, dynamic>>{}; // newest row per bucket (rows come newest first)
    for (final g in (accounts.first['r2StorageAdaptiveGroups'] as List? ?? const [])) {
      final name = '${g['dimensions']?['bucketName'] ?? '?'}';
      if (latest.containsKey(name)) continue;
      final m = g['max'] as Map? ?? const {};
      latest[name] = {
        'bucket': name,
        'bytes': ((m['payloadSize'] as num?) ?? 0) + ((m['metadataSize'] as num?) ?? 0),
        'objects': (m['objectCount'] as num?) ?? 0,
      };
    }
    return latest.values.toList()..sort((a, b) => (b['bytes'] as num).compareTo(a['bytes'] as num));
  }

  /// One row per day: date, requests, pageViews, uniques, bytes, threats.
  static Future<List<Map<String, dynamic>>> daily(String token, String zoneId, {int days = 30}) async {
    final until = DateTime.now().toUtc();
    final since = until.subtract(Duration(days: days - 1));
    String d(DateTime t) => t.toIso8601String().substring(0, 10);
    const query = r'''
query ($zone: String!, $since: Date!, $until: Date!) {
  viewer {
    zones(filter: { zoneTag: $zone }) {
      httpRequests1dGroups(limit: 31, filter: { date_geq: $since, date_leq: $until }, orderBy: [date_ASC]) {
        dimensions { date }
        sum { requests pageViews bytes threats }
        uniq { uniques }
      }
    }
  }
}''';
    final j = await Web.postJson('Cloudflare', Uri.https('api.cloudflare.com', '/client/v4/graphql'),
        {'query': query, 'variables': {'zone': zoneId, 'since': d(since), 'until': d(until)}},
        headers: _auth(token)) as Map;
    if (j['errors'] != null && (j['errors'] as List).isNotEmpty) throw WebError('Cloudflare: ${j['errors']}');
    final zones = (j['data']?['viewer']?['zones'] as List?) ?? const [];
    if (zones.isEmpty) return [];
    return [
      for (final g in (zones.first['httpRequests1dGroups'] as List? ?? const []))
        {
          'date': '${g['dimensions']['date']}',
          'requests': g['sum']['requests'] ?? 0,
          'pageViews': g['sum']['pageViews'] ?? 0,
          'bytes': g['sum']['bytes'] ?? 0,
          'threats': g['sum']['threats'] ?? 0,
          'uniques': g['uniq']['uniques'] ?? 0,
        },
    ];
  }
}
