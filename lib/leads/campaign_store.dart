import 'dart:convert';
import 'dart:io';

/// Campaigns = one tag per place you hand out a link or a QR (a flyer, a WhatsApp group, a gem fair…)
/// or per PERSON who hands it out for you (an agent, a broker, a friend) — then HQ shows who brought whom.
/// Kept in  gemstok_hq/leads/campaigns.json  (holds people's names → not in git, see .gitignore).
/// The tag rule matches the database's (member_signup.from_tag): a–z, 0–9, _ and -, 2–40 long.
class Campaign {
  Campaign({
    required this.tag,
    required this.name,
    required this.site,
    required this.createdAt,
    this.where = '',
    this.notes = '',
    this.active = true,
    this.kind = 'place',
    this.memberGsm = '',
    this.removed = false,
  });

  final String tag;
  String name;
  String site; // key of CampaignStore.sites
  final DateTime createdAt;
  String where; // where it's used: "flyer — Ratnapura gem market"
  String notes;
  bool active;
  String kind; // 'place' or 'person'
  String memberGsm; // person campaigns: their Gemstok ID if they're a member (GSM-…), else ''

  bool get isPerson => kind == 'person';

  /// Deleted in HQ: hidden everywhere, but kept in the file so its tag is never given out again
  /// (old clicks in the database stay with the old tag).
  bool removed;

  /// For posts and messages: opens the Get page (store buttons).
  String get link => '${CampaignStore.sites[site]!.$2}?from=$tag';

  /// For QR codes: the same, but the phone goes straight to its store.
  String get qrLink => '$link&go=1';

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'name': name,
        'site': site,
        'created_at': createdAt.toIso8601String(),
        'where': where,
        'notes': notes,
        'active': active,
        'kind': kind,
        'member_gsm': memberGsm,
        if (removed) 'removed': true,
      };

  static Campaign fromJson(Map<String, dynamic> j) => Campaign(
        tag: j['tag'] as String,
        name: j['name'] as String? ?? '',
        site: CampaignStore.sites.containsKey(j['site']) ? j['site'] as String : 'manikvault',
        createdAt: DateTime.parse(j['created_at'] as String),
        where: j['where'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        active: j['active'] as bool? ?? true,
        kind: j['kind'] == 'person' ? 'person' : 'place',
        memberGsm: j['member_gsm'] as String? ?? '',
        removed: j['removed'] as bool? ?? false,
      );
}

class CampaignStore {
  /// key → (label, Get page). Only ManiKVault's Get page exists so far; add the others when they do.
  static const sites = <String, (String, String)>{
    'manikvault': ('ManiKVault', 'https://manikvault.com/get/'),
  };

  static final tagRule = RegExp(r'^[a-z0-9_-]{2,40}$');

  static String get folder => '${Platform.environment['HOME']}/Development/Gemstok/gemstok_hq/leads';
  static File get _file => File('$folder/campaigns.json');

  static Future<List<Campaign>> load() async {
    if (!await _file.exists()) return [];
    final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    final list = [for (final e in (j['campaigns'] as List? ?? const [])) Campaign.fromJson(e as Map<String, dynamic>)];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static Future<void> save(List<Campaign> list) async {
    await Directory(folder).create(recursive: true);
    final tmp = File('${_file.path}.saving');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'about': 'Gemstok HQ campaign links. Edit in HQ → Leads.',
      'campaigns': [for (final c in list) c.toJson()],
    }));
    await tmp.rename(_file.path);
  }

  /// "Ratnapura Gem Fair 2026" → "ratnapura-gem-fair-2026"
  static String suggestTag(String name) {
    final t = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return t.length > 40 ? t.substring(0, 40).replaceAll(RegExp(r'-+$'), '') : t;
  }

  /// "Sunil Perera" → "p-sunil-perera" (the p- keeps people's tags apart from places').
  static String suggestPersonTag(String name) {
    final t = suggestTag(name);
    return t.isEmpty ? '' : suggestTag('p-$t');
  }

  /// [base] if it's free, else base-2, base-3 …
  static String uniqueTag(String base, Iterable<String> used) {
    final taken = used.toSet();
    if (!taken.contains(base)) return base;
    for (var i = 2;; i++) {
      final suffix = '-$i';
      final b = base.length + suffix.length > 40 ? base.substring(0, 40 - suffix.length) : base;
      if (!taken.contains('$b$suffix')) return '$b$suffix';
    }
  }
}
