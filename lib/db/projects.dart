/// The Supabase projects HQ knows about. Refs are not secret (they're in every app).
/// Keys/passwords are NOT here — they live only in the Keychain (settings/key_store.dart).
class HqProject {
  const HqProject({
    required this.id,
    required this.name,
    required this.ref,
    required this.holds,
    this.inStep1 = true,
    this.role = 'hq_reader',
  });

  final String id; // our own short name, used as the Keychain key prefix
  final String name;
  final String ref; // Supabase project ref
  final String holds; // one line: what HQ reads from it
  final bool inStep1; // false = listed but not used yet
  final String role; // hq_reader (read-only) — or hq_operator for the one actions login

  /// Pooler user name, e.g. hq_reader.odcwzqiwfngozjztnfzm
  String get readerUser => '$role.$ref';
}

const hqProjects = <HqProject>[
  HqProject(
      id: 'gemstok', name: 'Gemstok', ref: 'odcwzqiwfngozjztnfzm',
      holds: 'members · app opens · credits · purchases · boosts · ad-free · reports'),
  HqProject(
      id: 'mkv', name: 'ManiKVault data', ref: 'qauisvfoxgotbasxkeus',
      holds: 'market stones · stone reports · boosts · boost views'),
  HqProject(
      id: 'social', name: 'Social', ref: 'mrgjjeyarzksiawkaxvw',
      holds: 'follows · follower counts'),
  HqProject(
      id: 'chat', name: 'Chat', ref: 'hnutebcsskpvechxbmxo',
      holds: 'conversation COUNTS only — never messages'),
  HqProject(
      id: 'gemmit', name: 'Gemmit', ref: 'yicrrarvefhrvgzdfzlh',
      holds: 'posts · circles · comments · post reports (counts)'),
  HqProject(
      id: 'quvlet_video', name: 'Quvlet video', ref: 'xpilkkhssgpmvdgqrydf',
      holds: 'videos · likes · video reports (counts)'),
  HqProject(
      id: 'tracegems', name: 'TraceGems', ref: 'otlkrgbqehnrrnkqiqan',
      holds: 'TraceGems records (counts)'),
  HqProject(
      id: 'websites', name: 'IntoGemology', ref: 'gtlvlumpgbztpjtfnkdn',
      holds: 'waitlist · subscribers · contacts (counts) · campaign clicks'),
];

/// HQ's ACTION login (Gemstok): may only call hq.set_maintenance / hq.set_min_version.
/// Used only after a confirm screen + Touch ID; every use is written to the action log.
const hqOperatorProject = HqProject(
  id: 'gemstok_operator',
  name: 'Actions login (hq_operator)',
  ref: 'odcwzqiwfngozjztnfzm',
  holds: 'app switches + agent codes — changes data only through checked functions',
  role: 'hq_operator',
);
