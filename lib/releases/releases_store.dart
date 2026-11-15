import 'dart:convert';
import 'dart:io';

/// The apps HQ plans releases for: key (as in login_history.app) → name + project folder on this Mac.
class HqApp {
  const HqApp(this.key, this.name, this.folder);
  final String key;
  final String name;
  final String folder; // inside ~/Development/Gemstok

  static const all = [
    HqApp('manikvault', 'ManiKVault', 'manikvault_app'),
    HqApp('gem_broker', 'Gem Broker', 'gem_broker_app'),
    HqApp('quvlet', 'Quvlet', 'Quvlet/super_app'),
  ];

  static String get _root => '${Platform.environment['HOME']}/Development/Gemstok';

  /// `version:` from the app's pubspec.yaml on this Mac (what the next build will be), e.g. "1.1.0+18".
  Future<String?> macVersion() async {
    try {
      final f = File('$_root/$folder/pubspec.yaml');
      for (final line in await f.readAsLines()) {
        final m = RegExp(r'^version:\s*([0-9][^\s#]*)').firstMatch(line);
        if (m != null) return m.group(1);
      }
    } catch (_) {}
    return null;
  }
}

/// "1.1.0+18" → [1, 1, 0, 18]. null when it isn't a version (e.g. "next", "unknown").
List<int>? parseVersion(String v) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?').firstMatch(v.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 4; i++) int.parse(m.group(i) ?? '0')];
}

/// <0 a older than b, 0 same, >0 newer. Build number only counts when both have one.
int compareVersions(String a, String b) {
  final x = parseVersion(a), y = parseVersion(b);
  if (x == null || y == null) return 0;
  final bothBuilds = a.contains('+') && b.contains('+');
  for (var i = 0; i < (bothBuilds ? 4 : 3); i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

class ReleaseItem {
  ReleaseItem(this.text, {this.done = false});
  String text;
  bool done;
  Map<String, dynamic> toJson() => {'text': text, 'done': done};
  static ReleaseItem fromJson(Map<String, dynamic> j) =>
      ReleaseItem(j['text'] as String? ?? '', done: j['done'] as bool? ?? false);
}

/// One planned (or shipped) app update.
class Release {
  Release({
    required this.id,
    required this.app,
    required this.version,
    this.status = 'planned',
    this.target = '',
    this.notes = '',
    List<ReleaseItem>? items,
    this.releasedAt,
  }) : items = items ?? [];

  final String id;
  String app; // HqApp.key
  String version; // "1.2.0" or "next"
  String status; // Release.statuses
  String target; // free text date: "Dec 2026", "2026-12-05"
  String notes;
  final List<ReleaseItem> items;
  DateTime? releasedAt;

  static const statuses = {
    'planned': 'Planned',
    'building': 'Building',
    'testing': 'Testing',
    'review': 'In store review',
    'live': 'Live',
  };

  int get doneCount => items.where((i) => i.done).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'app': app,
        'version': version,
        'status': status,
        'target': target,
        'notes': notes,
        'items': [for (final i in items) i.toJson()],
        if (releasedAt != null) 'released_at': releasedAt!.toIso8601String(),
      };

  static Release fromJson(Map<String, dynamic> j) => Release(
        id: j['id'] as String,
        app: j['app'] as String? ?? 'manikvault',
        version: j['version'] as String? ?? 'next',
        status: statuses.containsKey(j['status']) ? j['status'] as String : 'planned',
        target: j['target'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        items: [for (final i in (j['items'] as List? ?? const [])) ReleaseItem.fromJson(i as Map<String, dynamic>)],
        releasedAt: DateTime.tryParse(j['released_at'] as String? ?? ''),
      );
}

/// Release plans live in  gemstok_hq/releases/releases.json  — edit in HQ → Releases, or by hand
/// (HQ re-reads it each time you open the page or press Reload). Fine in git.
class ReleaseStore {
  static String get folder => '${Platform.environment['HOME']}/Development/Gemstok/gemstok_hq/releases';
  static File get file => File('$folder/releases.json');

  static Future<List<Release>> load() async {
    if (!await file.exists()) {
      final seed = _seed();
      await save(seed);
      return seed;
    }
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return [for (final r in (j['releases'] as List? ?? const [])) Release.fromJson(r as Map<String, dynamic>)];
  }

  static Future<void> save(List<Release> list) async {
    await Directory(folder).create(recursive: true);
    final tmp = File('${file.path}.saving');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'about': 'Gemstok HQ release plans. Edit in HQ → Releases (or here; HQ re-reads it). '
          'status: planned · building · testing · review · live',
      'releases': [for (final r in list) r.toJson()],
    }));
    await tmp.rename(file.path);
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// First run: the next builds from the "App changes for Gemstok HQ" plan.
  static List<Release> _seed() => [
        Release(id: 'seed-mkv', app: 'manikvault', version: 'next', notes: 'From the HQ app-changes plan.', items: [
          ReleaseItem('Count an app open at start-up (not only Browse)'),
          ReleaseItem('record_signup() once for new accounts'),
          ReleaseItem('Android: campaign tag from the Play install referrer'),
          ReleaseItem('"How did you hear about us?" (optional)'),
          ReleaseItem('Android credit buys through the newer purchase function'),
        ]),
        Release(id: 'seed-gb', app: 'gem_broker', version: 'next', notes: 'From the HQ app-changes plan.', items: [
          ReleaseItem('Count an app open at start-up (not only Market)'),
          ReleaseItem('record_signup() once for new accounts'),
          ReleaseItem('Android: campaign tag from the Play install referrer'),
          ReleaseItem('"How did you hear about us?" (optional)'),
          ReleaseItem('Market views for every listed stone (database first)'),
        ]),
        Release(id: 'seed-quvlet', app: 'quvlet', version: 'next', notes: 'At Quvlet\'s launch.', items: [
          ReleaseItem('record_signup() once for new accounts'),
          ReleaseItem('"How did you hear about us?" (optional)'),
        ]),
      ];
}
