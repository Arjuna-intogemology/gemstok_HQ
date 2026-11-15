import 'dart:convert';
import 'dart:io';

import '../settings/key_store.dart';

/// One blog = one table in the IntoGemology (websites) database. Same list as internal.gemstok.com/blog.html.
class BlogSite {
  const BlogSite(this.id, this.label, this.table, this.key, this.folder, this.site, this.postUrl, {this.dailyGem = false});
  final String id;
  final String label;
  final String table;
  final String key; // column that identifies a post for update / delete
  final String folder; // image folder inside the blog-images bucket
  final String site; // the blog page
  final String Function(String slug) postUrl;
  final bool dailyGem; // intoGEMOLOGY posts have a "daily gem" field

  static final all = [
    BlogSite('intogemology', 'intoGEMOLOGY', 'blogs', 'title', 'intogemology/', 'https://www.intogemology.com/dailygems.html',
        (s) => 'https://www.intogemology.com/dailygem-post.html?post=${Uri.encodeComponent(s)}',
        dailyGem: true),
    BlogSite('gemstok', 'gemstok.com', 'blogs_gemstok', 'id', 'gemstok/', 'https://gemstok.com/blog.html',
        (s) => 'https://gemstok.com/blog-post.html?slug=${Uri.encodeComponent(s)}'),
    BlogSite('manikvault', 'ManiKVault', 'blogs_manikvault', 'id', '', 'https://manikvault.com/blog.html',
        (s) => 'https://manikvault.com/post.html?slug=${Uri.encodeComponent(s)}'),
    BlogSite('quvlet', 'Quvlet', 'blogs_quvlet', 'id', 'quvlet/', 'https://quvlet.com/blog.html',
        (s) => 'https://quvlet.com/post.html?slug=${Uri.encodeComponent(s)}'),
    BlogSite('gemmit', 'Gemmit', 'blogs_gemmit', 'id', 'gemmit/', 'https://gemmit.app/blog.html',
        (s) => 'https://gemmit.app/post.html?slug=${Uri.encodeComponent(s)}'),
  ];
}

/// Writes blog posts the same way the site admin pages do: signs in as the blog admin (Supabase Auth,
/// e-mail + password from Settings → Other services → Blog admin), then reads / writes the blog tables
/// with THAT login. The database decides what's allowed (site_admins + is_site_admin()) — never service_role.
/// Only this one host, only the 5 blog tables + the blog-images bucket. The sign-in lasts in memory only and
/// is forgotten when HQ locks.
class BlogApi {
  static const host = 'gtlvlumpgbztpjtfnkdn.supabase.co';
  // public "anon" key — the same one the websites ship in their pages (not a secret)
  static const _anon =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd0bHZsdW1wZ2J6dHBqdGZua2RuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM0NTMwMDcsImV4cCI6MjA4OTAyOTAwN30.WLxCSdNrd5KWrvUPKvvDEy2SXirkjhB4B0pGzbQS7AA';
  static const bucket = 'blog-images';
  static final _tables = {for (final b in BlogSite.all) b.table};

  static String? _token;
  static DateTime? _until;
  static String? signedInAs;

  static void forget() {
    _token = null;
    _until = null;
    signedInAs = null;
  }

  static Future<String> _auth() async {
    if (_token != null && _until != null && DateTime.now().isBefore(_until!)) return _token!;
    final k = await KeyStore.serviceFields('blogadmin');
    final email = k['email'] ?? '', password = k['password'] ?? '';
    if (email.isEmpty || password.isEmpty) {
      throw const BlogError('Add the blog admin e-mail + password in Settings → Other services → Blog admin.');
    }
    final (code, body) = await _send('POST', Uri.https(host, '/auth/v1/token', {'grant_type': 'password'}),
        json: {'email': email, 'password': password}, withUser: false);
    if (code != 200) {
      throw BlogError(code == 400 ? 'Blog admin: wrong e-mail or password.' : 'Blog sign-in answered $code.');
    }
    final j = jsonDecode(body) as Map<String, dynamic>;
    _token = j['access_token'] as String;
    _until = DateTime.now().add(Duration(seconds: ((j['expires_in'] as num?)?.toInt() ?? 3600) - 120));
    signedInAs = email;
    return _token!;
  }

  /// Settings → Check: signs in, nothing else.
  static Future<String> check() async {
    forget();
    await _auth();
    return 'signed in as $signedInAs';
  }

  static Future<(int, String)> _send(String method, Uri uri,
      {Object? json, List<int>? bytes, String? contentType, Map<String, String>? extra, bool withUser = true}) async {
    if (uri.host != host) throw const BlogError('HQ only writes blogs to the IntoGemology database.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl(method, uri);
      req.headers.set('apikey', _anon);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${withUser ? await _auth() : _anon}');
      extra?.forEach(req.headers.set);
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(json)));
      } else if (bytes != null) {
        req.headers.set(HttpHeaders.contentTypeHeader, contentType ?? 'application/octet-stream');
        req.add(bytes);
      }
      final res = await req.close().timeout(const Duration(seconds: 60));
      return (res.statusCode, await res.transform(utf8.decoder).join());
    } finally {
      client.close(force: true);
    }
  }

  static Uri _rest(String table, [Map<String, String>? q]) {
    if (!_tables.contains(table)) throw const BlogError('Not a blog table.');
    return Uri.https(host, '/rest/v1/$table', q);
  }

  static String _friendly(int code, String body) {
    if (RegExp('row-level security|permission denied|violates', caseSensitive: false).hasMatch(body) || code == 403) {
      return 'Not allowed — this login is not a blog admin in the database.';
    }
    if (body.contains('duplicate key')) return 'A post with that title or slug already exists.';
    return 'Answered $code: ${body.length > 200 ? body.substring(0, 200) : body}';
  }

  static List<Map<String, dynamic>> _rows(int code, String body, {bool mustChange = false}) {
    if (code < 200 || code > 299) throw BlogError(_friendly(code, body));
    final rows = [for (final r in jsonDecode(body) as List) Map<String, dynamic>.from(r as Map)];
    if (mustChange && rows.isEmpty) throw BlogError(_friendly(403, 'row-level security'));
    return rows;
  }

  /// All posts of a blog, drafts first, then newest published.
  static Future<List<Map<String, dynamic>>> posts(BlogSite b) async {
    final (code, body) =
        await _send('GET', _rest(b.table, {'select': '*', 'order': 'published_at.desc.nullsfirst'}));
    return _rows(code, body);
  }

  static Future<Map<String, dynamic>> insert(BlogSite b, Map<String, dynamic> rec) async {
    final (code, body) =
        await _send('POST', _rest(b.table), json: rec, extra: {'Prefer': 'return=representation'});
    return _rows(code, body, mustChange: true).first;
  }

  static Future<Map<String, dynamic>> update(BlogSite b, Object keyValue, Map<String, dynamic> rec) async {
    final (code, body) = await _send('PATCH', _rest(b.table, {b.key: 'eq.$keyValue'}),
        json: rec, extra: {'Prefer': 'return=representation'});
    return _rows(code, body, mustChange: true).first;
  }

  static Future<void> delete(BlogSite b, Object keyValue) async {
    final (code, body) = await _send('DELETE', _rest(b.table, {b.key: 'eq.$keyValue'}),
        extra: {'Prefer': 'return=representation'});
    _rows(code, body, mustChange: true);
  }

  /// Uploads a picture to blog-images/<folder><time>-<name> and returns its public link.
  static Future<String> uploadImage(BlogSite b, File f) async {
    final name = f.uri.pathSegments.last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]+'), '-');
    final path = '${b.folder}${DateTime.now().millisecondsSinceEpoch}-$name';
    final ext = name.split('.').last;
    final type = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };
    final (code, body) = await _send('POST', Uri.https(host, '/storage/v1/object/$bucket/$path'),
        bytes: await f.readAsBytes(), contentType: type, extra: {'x-upsert': 'false'});
    if (code != 200) throw BlogError('Upload failed: ${_friendly(code, body)}');
    return 'https://$host/storage/v1/object/public/$bucket/$path';
  }

  /// Same rule as the site admin pages: lower case, keep a–z 0–9 spaces and dashes, spaces → dashes.
  static String slugify(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
}

class BlogError implements Exception {
  const BlogError(this.message);
  final String message;
  @override
  String toString() => message;
}
