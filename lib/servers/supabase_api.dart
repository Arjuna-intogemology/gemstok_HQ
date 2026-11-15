import 'dart:convert';
import 'dart:io';

/// The Supabase Management API — READ ONLY.
///
/// The access token you add in Settings can change or delete projects, so this file:
///   · only ever sends GET (there is no other method in this code)
///   · only to the five addresses in [_allowed] — anything else is refused before it leaves the Mac
///   · never logs or shows the token
class SupabaseApi {
  static const _host = 'api.supabase.com';

  static final _allowed = <RegExp>[
    RegExp(r'^/v1/projects$'), // list projects (status: ACTIVE_HEALTHY, INACTIVE = paused…)
    RegExp(r'^/v1/projects/[a-z]{20}$'), // one project
    RegExp(r'^/v1/projects/[a-z]{20}/functions$'), // edge functions: name, version, verify_jwt, updated
    RegExp(r'^/v1/projects/[a-z]{20}/analytics/endpoints/logs$'), // logs (≤ 24 h, ClickHouse SQL)
    RegExp(r'^/v1/projects/[a-z]{20}/analytics/endpoints/functions\.combined-stats$'), // calls / errors
  ];

  static Future<dynamic> get(String token, String path, [Map<String, String>? query]) async {
    if (!_allowed.any((r) => r.hasMatch(path))) {
      throw const SupabaseApiError(0, 'HQ only calls read-only Supabase addresses.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.https(_host, path, query));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 30));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw SupabaseApiError(res.statusCode, _explain(res.statusCode, body));
      }
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  static String _explain(int code, String body) {
    final short = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    return switch (code) {
      401 => 'Token not accepted (401) — check it in Settings.',
      403 => 'This token can\'t see that (403) — it may belong to the other Supabase account.',
      404 => 'Not found (404).',
      429 => 'Supabase says: too many requests (429). Wait a minute.',
      _ => 'Supabase answered $code: $short',
    };
  }

  // ---------------------------------------------------------------- helpers

  static Future<List<Map<String, dynamic>>> projects(String token) async =>
      [for (final p in await get(token, '/v1/projects') as List) Map<String, dynamic>.from(p as Map)];

  static Future<List<Map<String, dynamic>>> functions(String token, String ref) async =>
      [for (final f in await get(token, '/v1/projects/$ref/functions') as List) Map<String, dynamic>.from(f as Map)];

  /// Logs of the last [hours] (Supabase allows at most 24) with a ClickHouse SQL query.
  static Future<List<Map<String, dynamic>>> logs(String token, String ref, String sql, {int hours = 24}) async {
    final end = DateTime.now().toUtc();
    final start = end.subtract(Duration(hours: hours.clamp(1, 24)));
    final r = await get(token, '/v1/projects/$ref/analytics/endpoints/logs', {
      'sql': sql,
      'iso_timestamp_start': start.toIso8601String(),
      'iso_timestamp_end': end.toIso8601String(),
    }) as Map;
    if (r['error'] != null) throw SupabaseApiError(200, 'Log query error: ${r['error']}');
    return [for (final row in (r['result'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
  }

  static Future<List<Map<String, dynamic>>> functionStats(String token, String ref, String functionId) async {
    final r = await get(token, '/v1/projects/$ref/analytics/endpoints/functions.combined-stats',
        {'interval': '1day', 'function_id': functionId}) as Map;
    if (r['error'] != null) throw SupabaseApiError(200, 'Stats error: ${r['error']}');
    return [for (final row in (r['result'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
  }
}

class SupabaseApiError implements Exception {
  const SupabaseApiError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => message;
}
