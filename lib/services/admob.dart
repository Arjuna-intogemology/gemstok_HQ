import 'dart:async';
import 'dart:io';

import 'web.dart';

/// AdMob (read-only): estimated earnings, impressions and clicks per app per day.
/// AdMob only allows a person's sign-in (no service accounts), so HQ does Google's "desktop app"
/// sign-in once: your browser opens, you allow access to your AdMob reports (admob.report), and HQ keeps
/// the resulting refresh token in the Keychain.
/// Keys: an OAuth client of type "Desktop app" (Google Cloud gemstok-490000 → APIs & Services →
/// Credentials; enable "AdMob API" first) — client ID + client secret — and your publisher ID (pub-…,
/// AdMob → Settings → Account information).
class AdMob {
  // reports only (earnings, impressions, clicks) — narrower than admob.readonly, no payments / settings
  static const _scope = 'https://www.googleapis.com/auth/admob.report';

  /// Opens the browser for the one-time sign-in and waits for Google to send the code back to
  /// a small page on this Mac (127.0.0.1, a free port). Returns the refresh token.
  static Future<String> signIn(Map<String, String> k) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': k['client_id']!,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': _scope,
      'access_type': 'offline',
      'prompt': 'consent',
    });
    await Process.run('open', [url.toString()]);
    try {
      final req = await server.first.timeout(const Duration(minutes: 5));
      final code = req.uri.queryParameters['code'];
      req.response
        ..headers.contentType = ContentType.html
        ..write('<html><body style="font-family:-apple-system;padding:40px">'
            '${code == null ? 'Sign-in was cancelled.' : 'Done — you can close this tab and go back to Gemstok HQ.'}'
            '</body></html>');
      await req.response.close();
      if (code == null) throw WebError('AdMob sign-in cancelled');
      final j = await Web.postForm('Google sign-in', Uri.https('oauth2.googleapis.com', '/token'), {
        'code': code,
        'client_id': k['client_id']!,
        'client_secret': k['client_secret']!,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
      }) as Map;
      final refresh = j['refresh_token'] as String?;
      if (refresh == null) throw WebError('Google gave no refresh token — try again');
      return refresh;
    } finally {
      await server.close(force: true);
    }
  }

  static Future<String> accessToken(Map<String, String> k) async {
    final j = await Web.postForm('Google sign-in', Uri.https('oauth2.googleapis.com', '/token'), {
      'client_id': k['client_id']!,
      'client_secret': k['client_secret']!,
      'refresh_token': k['refresh_token']!,
      'grant_type': 'refresh_token',
    }) as Map;
    return j['access_token'] as String;
  }

  /// Rows: date (YYYYMMDD), app name, earnings (in the account currency), impressions, clicks.
  static Future<List<Map<String, dynamic>>> earnings(String token, String publisherId, {int days = 30}) async {
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days - 1));
    Map<String, int> d(DateTime t) => {'year': t.year, 'month': t.month, 'day': t.day};
    final res = await Web.postJson(
      'AdMob',
      Uri.https('admob.googleapis.com', '/v1/accounts/$publisherId/networkReport:generate'),
      {
        'reportSpec': {
          'dateRange': {'startDate': d(start), 'endDate': d(end)},
          'dimensions': ['DATE', 'APP'],
          'metrics': ['ESTIMATED_EARNINGS', 'IMPRESSIONS', 'CLICKS'],
        },
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    final out = <Map<String, dynamic>>[];
    for (final part in (res is List ? res : [res])) {
      final row = (part as Map)['row'];
      if (row == null) continue;
      final dim = row['dimensionValues'] as Map;
      final met = row['metricValues'] as Map;
      out.add({
        'date': '${dim['DATE']?['value'] ?? ''}',
        'app': '${dim['APP']?['displayLabel'] ?? dim['APP']?['value'] ?? ''}',
        'earnings': (int.tryParse('${met['ESTIMATED_EARNINGS']?['microsValue'] ?? 0}') ?? 0) / 1e6,
        'impressions': int.tryParse('${met['IMPRESSIONS']?['integerValue'] ?? 0}') ?? 0,
        'clicks': int.tryParse('${met['CLICKS']?['integerValue'] ?? 0}') ?? 0,
      });
    }
    return out;
  }
}
