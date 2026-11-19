import 'dart:convert';
import 'dart:io';

/// Ideas people bring in — kept in one file on this Mac:
///   gemstok_hq/ideas/ideas.json   (in .gitignore: it can hold who suggested what)
/// Ideas are never deleted: "No" or "Done" keeps them, so you can look back later.
class Idea {
  Idea({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.text,
    this.from = '',
    this.gsmId = '',
    this.app = 'Other',
    this.status = 'new',
    this.notes = '',
    this.number = 0,
    this.memberId = '',
    List<IdeaVoice>? also,
    this.creditedAt,
    this.mergedInto = '',
  }) : also = also ?? [];

  final String id;
  final DateTime createdAt;
  DateTime updatedAt;
  String text;
  String from; // who suggested it — a member's name, or free text ("agent in Ratnapura")
  String gsmId; // filled when "from" was picked from the member search
  String app;
  String status; // new · thinking · planned · done · no
  String notes;

  /// IDEA-0001, IDEA-0002 … given once, never reused.
  int number;

  /// The ONE person this idea is credited to: Gemstok member id (never changes, even if their
  /// GSM / TEMP id does — e.g. after a restore). Empty = not linked to a member → can't be credited.
  String memberId;

  /// Others who brought the same idea later. They're recorded, but the credit stays with [memberId].
  final List<IdeaVoice> also;

  /// When the credit was given (once). null = not yet.
  DateTime? creditedAt;

  /// "IDEA-0004" when this card was the same idea as an earlier one (then it never gets credit).
  String mergedInto;

  String get label => number == 0 ? 'IDEA-?' : 'IDEA-${number.toString().padLeft(4, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'text': text,
        'from': from,
        'gsm_id': gsmId,
        'app': app,
        'status': status,
        'notes': notes,
        'number': number,
        'member_id': memberId,
        'also': [for (final a in also) a.toJson()],
        'credited_at': creditedAt?.toIso8601String(),
        'merged_into': mergedInto,
      };

  static Idea fromJson(Map<String, dynamic> j) => Idea(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse((j['updated_at'] ?? j['created_at']) as String),
        text: j['text'] as String? ?? '',
        from: j['from'] as String? ?? '',
        gsmId: j['gsm_id'] as String? ?? '',
        app: j['app'] as String? ?? 'Other',
        status: j['status'] as String? ?? 'new',
        notes: j['notes'] as String? ?? '',
        number: (j['number'] as num?)?.toInt() ?? 0,
        memberId: j['member_id'] as String? ?? '',
        also: [for (final a in (j['also'] as List? ?? const [])) IdeaVoice.fromJson(a as Map<String, dynamic>)],
        creditedAt: j['credited_at'] == null ? null : DateTime.parse(j['credited_at'] as String),
        mergedInto: j['merged_into'] as String? ?? '',
      );
}

/// Someone else who suggested an idea that was already in the pool.
class IdeaVoice {
  IdeaVoice({required this.at, this.name = '', this.gsmId = '', this.memberId = ''});
  final DateTime at;
  final String name;
  final String gsmId;
  final String memberId;

  Map<String, dynamic> toJson() =>
      {'at': at.toIso8601String(), 'name': name, 'gsm_id': gsmId, 'member_id': memberId};

  static IdeaVoice fromJson(Map<String, dynamic> j) => IdeaVoice(
        at: DateTime.parse(j['at'] as String),
        name: j['name'] as String? ?? '',
        gsmId: j['gsm_id'] as String? ?? '',
        memberId: j['member_id'] as String? ?? '',
      );
}

class IdeasStore {
  static const apps = ['ManiKVault', 'Gem Broker', 'Quvlet', 'Gemmit', 'TraceGems', 'IntoGemology', 'Gemstok', 'Other'];
  static const statuses = {
    'new': 'New',
    'thinking': 'Thinking',
    'planned': 'Planned',
    'done': 'Done',
    'no': 'No',
  };

  static File get _file =>
      File('${Platform.environment['HOME']}/Development/Gemstok/gemstok_hq/ideas/ideas.json');

  static Future<List<Idea>> load() async {
    if (!await _file.exists()) return [];
    final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    final list = [for (final e in (j['ideas'] as List? ?? const [])) Idea.fromJson(e as Map<String, dynamic>)];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    try {
      _removedTop = (await _loadRemoved())
          .fold<int>(0, (m, r) => ((r['number'] as num?)?.toInt() ?? 0) > m ? (r['number'] as num).toInt() : m);
    } catch (_) {}
    // older ideas had no number: give them one, oldest first
    var next = nextNumber(list);
    for (final i in list.reversed) {
      if (i.number == 0) i.number = next++;
    }
    return list;
  }

  /// Writes a new copy first, then swaps it in — a crash mid-save can't wipe the list.
  static Future<void> save(List<Idea> ideas) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.saving');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'about': 'Gemstok HQ ideas list. Edit in HQ → Ideas.',
      'ideas': [for (final i in ideas) i.toJson()],
    }));
    await tmp.rename(_file.path);
  }

  /// Next IDEA number — counts removed ideas too, so a number is never given out twice.
  static int nextNumber(List<Idea> ideas) {
    final top = ideas.fold<int>(0, (m, i) => i.number > m ? i.number : m);
    return (top > _removedTop ? top : _removedTop) + 1;
  }

  // ---- removed ideas: kept in their own file (never truly gone), out of the pool
  static File get _removedFile =>
      File('${Platform.environment['HOME']}/Development/Gemstok/gemstok_hq/ideas/removed_ideas.json');
  static int _removedTop = 0;

  static Future<List<Map<String, dynamic>>> _loadRemoved() async {
    if (!await _removedFile.exists()) return [];
    final j = jsonDecode(await _removedFile.readAsString()) as Map<String, dynamic>;
    return [for (final e in (j['removed'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
  }

  /// Moves [idea] out of the pool into removed_ideas.json (with the date). Its number stays used.
  static Future<void> remove(Idea idea) async {
    final list = await _loadRemoved();
    list.add({...idea.toJson(), 'removed_at': DateTime.now().toIso8601String()});
    await _removedFile.parent.create(recursive: true);
    final tmp = File('${_removedFile.path}.saving');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'about': 'Ideas removed from the Gemstok HQ pool. Kept here so nothing is lost; their numbers are never reused.',
      'removed': list,
    }));
    await tmp.rename(_removedFile.path);
    if (idea.number > _removedTop) _removedTop = idea.number;
  }

  /// Ideas whose words overlap a lot with [text] — "is this already in the pool?"
  static List<Idea> similar(List<Idea> ideas, String text) {
    Set<String> words(String t) => {
          for (final w in t.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
            if (w.length > 2 && !_skip.contains(w)) w
        };
    final mine = words(text);
    final key = norm(text);
    final scored = <(Idea, double)>[];
    for (final i in ideas) {
      // same words (even one word, e.g. "shotgun"), or one fully inside the other
      final other = norm(i.text);
      if (key.length >= 3 && (other == key || (key.length >= 5 && (other.contains(key) || key.contains(other)) && other.length >= 5))) {
        scored.add((i, other == key ? 2.0 : 1.5));
        continue;
      }
      if (mine.length < 2) continue;
      final theirs = words(i.text);
      if (theirs.isEmpty) continue;
      final both = mine.intersection(theirs).length;
      final score = both / (mine.length < theirs.length ? mine.length : theirs.length);
      if (both >= 2 && score >= 0.5) scored.add((i, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final s in scored.take(3)) s.$1];
  }

  /// lower case, letters + digits only — "Shot gun!" and "shotgun" match.
  static String norm(String t) => t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static const _skip = {'the', 'and', 'for', 'add', 'with', 'app', 'can', 'should', 'please', 'make', 'from', 'that', 'this', 'have'};

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
