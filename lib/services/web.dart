import 'dart:convert';
import 'dart:io';

/// Small HTTP helper for the outside services. Only these hosts can be called — anything else is
/// refused before it leaves the Mac. Keys go in headers only and are never logged or shown.
class Web {
  static const allowedHosts = {
    'api.cloudflare.com',
    'api.appstoreconnect.apple.com',
    'oauth2.googleapis.com',
    'storage.googleapis.com',
    'androidpublisher.googleapis.com',
    'admob.googleapis.com',
  };

  static Future<(int, List<int>)> _send(String method, Uri uri,
      {Map<String, String>? headers, List<int>? body}) async {
    if (!allowedHosts.contains(uri.host)) throw WebError('HQ doesn\'t call ${uri.host}.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl(method, uri);
      headers?.forEach(req.headers.set);
      if (body != null) req.add(body);
      final res = await req.close().timeout(const Duration(seconds: 60));
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      return (res.statusCode, bytes);
    } finally {
      client.close(force: true);
    }
  }

  static WebError _err(String what, int code, List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    text = text.replaceAll('&#39;', "'").replaceAll('&quot;', '"').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');
    if (text.length > 240) text = '${text.substring(0, 240)}…';
    return WebError('$what answered $code: $text');
  }

  static Future<dynamic> getJson(String what, Uri uri, {Map<String, String>? headers}) async {
    final (code, bytes) = await _send('GET', uri, headers: {'Accept': 'application/json', ...?headers});
    if (code != 200) throw _err(what, code, bytes);
    return jsonDecode(utf8.decode(bytes));
  }

  static Future<List<int>> getBytes(String what, Uri uri, {Map<String, String>? headers}) async {
    final (code, bytes) = await _send('GET', uri, headers: headers);
    if (code == 404) throw WebError('$what: not found (404)');
    if (code != 200) throw _err(what, code, bytes);
    return bytes;
  }

  /// POST is only used where the service's READ call is a POST (Cloudflare GraphQL query,
  /// Google token exchange, AdMob report generate). Nothing here creates or changes anything.
  static Future<dynamic> postJson(String what, Uri uri, Object body, {Map<String, String>? headers}) async {
    final (code, bytes) = await _send('POST', uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json', ...?headers},
        body: utf8.encode(jsonEncode(body)));
    if (code != 200) throw _err(what, code, bytes);
    return jsonDecode(utf8.decode(bytes));
  }

  static Future<dynamic> postForm(String what, Uri uri, Map<String, String> form) async {
    final (code, bytes) = await _send('POST', uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'},
        body: utf8.encode(Uri(queryParameters: form).query));
    if (code != 200) throw _err(what, code, bytes);
    return jsonDecode(utf8.decode(bytes));
  }
}

class WebError implements Exception {
  WebError(this.message);
  final String message;
  @override
  String toString() => message;
}
