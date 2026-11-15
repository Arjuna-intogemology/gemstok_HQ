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
