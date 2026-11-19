import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Settings → How to use HQ. One card per part of the app: what it shows, where the numbers come from,
/// what you can do there, and what it needs to work. Search box at the top.
class HelpView extends StatefulWidget {
  const HelpView({super.key});

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _Topic {
  const _Topic(this.group, this.name, this.shows, {this.from = '', this.doHere = const [], this.needs = ''});
  final String group;
  final String name;
  final String shows;
  final String from; // where the numbers come from
  final List<String> doHere; // what you can do
  final String needs; // what it needs to work
}

const _topics = <_Topic>[
  // ---- everyday
  _Topic('Everyday', 'Unlocking and locking',
      'HQ opens only with Touch ID. It locks again after 5 minutes without use, when the Mac sleeps or the screen locks, '
          'and when you press Lock (bottom left).',
      doHere: [
        'Touch ID asks by itself when HQ is the app in front.',
        'If Touch ID won\'t read your finger, macOS offers "Use Password" — type your Mac login password.',
        'Locking throws away every loaded number and the keys in memory; unlocking loads them again.',
      ]),
  _Topic('Everyday', 'Refresh and "loaded" times',
      'Every number says where it came from and when it was loaded (the small grey line under it).',
      doHere: [
        'Database numbers reload every 5 minutes by themselves; press Refresh (top right) to load now.',
        'Store, ads and website numbers reload every hour.',
        'A red box means that source failed — it says which one. Settings → Check tests each login.',
      ]),
  _Topic('Everyday', 'Updating HQ after Claude changes code',
      'HQ is installed in Applications like any app. New code reaches it only when you build and install again.',
      doHere: [
        'Terminal:  cd ~/Development/Gemstok/gemstok_hq  then  ./tool/install.sh',
        'While Claude and you are working on it: flutter run -d macos (r = reload, R = restart, q = quit).',
        'Afterwards: git add -A, git commit -m "…", git push — so the code is safe on GitHub.',
      ]),
  _Topic('Everyday', 'Changes HQ can make (and how they\'re guarded)',
      'HQ mostly only reads. The few things it can change — app switches, agent codes, blog posts, uploads — always '
          'show a confirm screen saying exactly what happens, then ask for Touch ID, then write a line to the action log '
          '(~/Library/Application Support/gemstok_hq/actions.log).'),
  // ---- people
  _Topic('People', 'Today', 'Sign-ups, active people, credits bought and stones listed — today and the last 7 days. '
      'Warnings about renewals due soon appear at the top.', from: 'Gemstok + ManiKVault data databases'),
  _Topic('People', 'Joining', 'Sign-ups per day / week, by app and by sign-in type (Apple, Google, Email). '
      '"guessed" = the app was guessed from the first app open, until the apps record it at sign-up.',
      from: 'Gemstok · members, member_signup, login_history'),
  _Topic('People', 'Using', 'Who opened each app in the last 24 hours, 7 and 30 days.', from: 'Gemstok · login_history',
      needs: 'ManiKVault / Gem Broker count an app open only on Browse / Market until app change 1 ships.'),
  _Topic('People', 'Staying', 'Of the people who joined in a week, how many came back in their first week.',
      from: 'Gemstok · members, login_history'),
  _Topic('People', 'Doing', 'Market stones, boosts, credits, chats started, Gemmit posts and circles, follows, '
      'Quvlet videos, TraceGems records, website sign-ups.', from: 'all 8 databases (counts only)'),
  _Topic('People', 'People', 'Look up one person by Gemstok ID or username: name, joined, apps used, last seen, tier, stones.',
      doHere: ['Type GSM-… or a username and press Enter.'], from: 'Gemstok + ManiKVault data'),
  // ---- inbox
  _Topic('Inbox', 'Reports', 'Everything people report from the apps: traders, stones, posts — with the reason and who reported.',
      from: 'Gemstok · trader_reports, ManiKVault · stone_reports, Gemmit · post_reports'),
  _Topic('Inbox', 'Restore requests', 'A deleted member signed in again with the same email (new TEMP- id) and asked, '
      'with their rejoin PIN, for their old GSM id back. HQ only shows them — old GSM → new TEMP id, how long waiting.',
      doHere: ['Copy approve line → Gemstok SQL Editor → paste → Run → Refresh here.',
        'Copy reject line → change "reason here" → Run.', 'Count of waiting ones shows on Today.'],
      from: 'Gemstok · restore_requests (no note, emails, PINs or names)'),
  _Topic('Inbox', 'Ideas', 'The idea pool. Each idea gets a number (IDEA-0001) and ONE credited member, linked by their '
      'Gemstok member id — so it stays with them even if their GSM/TEMP id changes (a restore).',
      doHere: ['Type the idea → if it looks like one already in the pool, press "Same idea → add as also suggested" '
          '(they\'re recorded, no second credit).', 'Pick who suggested it from the member list (free text can\'t be credited).',
        'Older ideas: "Link member". When the reward is given: "Mark credit given" (once, can\'t move).',
        'Status: New → Thinking → Planned → Done (or No).',
        'Bin icon = delete: moved to ideas/removed_ideas.json, number never reused. Not for credited ideas.'],
      from: 'gemstok_hq/ideas/ideas.json (only on this Mac) + Gemstok member names'),
  // ---- business
  _Topic('Business', 'Money', 'Credit packs bought in the stores (real vs test), App Store money after Apple\'s cut, '
      'in-app purchases, AdMob earnings.', from: 'Gemstok · store_purchases, App Store Connect, AdMob',
      needs: 'App Store Connect and AdMob keys (Settings → Other services).'),
  _Topic('Business', 'Downloads', 'iPhone downloads and updates, Android installs, uninstalls and active devices, store reviews.',
      from: 'App Store Connect, Google Play reports', needs: 'App Store Connect + Google Play keys.'),
  _Topic('Business', 'Leads', 'Your campaign links and QR codes — one per place (flyer, gem fair, WhatsApp group) or per person.',
      doHere: [
        'For a place / For a person → name → Create link. Save QR for print makes a print-ready picture.',
        'Several people at once: paste one name per line.',
        'Person linked to a member → "Make approved agent…" gives them a permanent agent QR. New users who scan it '
            'IN the app within 1 day of signing up are counted as brought in by that agent (Brought in: N, Show people).',
        'Pause stops counting; Delete hides it but keeps the tag reserved.',
      ],
      from: 'IntoGemology · campaign_visits (clicks), Gemstok · member_signup + agent_referrals',
      needs: 'Sign-ups per campaign appear once the apps send the tag / scan the QR (app updates).'),
  _Topic('Business', 'Blogs', 'Write, publish, unpublish and delete posts on the 5 blogs (intoGEMOLOGY, gemstok.com, '
      'ManiKVault, Quvlet, Gemmit).', doHere: [
        '+ New post → title, category, picture (Upload picture…), content in HTML → tick Published → Create.',
        'Every save / delete / upload asks for Touch ID.',
      ], needs: 'Settings → Other services → Blog admin (the blog-admin e-mail + password).'),
  _Topic('Business', 'Websites', 'Visitors, page views and blocked threats per website.', from: 'Cloudflare',
      needs: 'Cloudflare token.'),
  // ---- system
  _Topic('System', 'Renewals', 'Everything that expires: the Apple sign-in secret (6 months), Apple Developer membership, '
      'tokens. Countdown, and a warning on Today 30 days before.',
      doHere: ['Renewed today, or Set the date it was made…', 'Apple secret: Read the date from the secret… (not saved).']),
  _Topic('System', 'Releases', 'Per app: the version in its project on this Mac vs the versions people really use, '
      'and your planned updates with checklists.', from: 'pubspec.yaml on this Mac + Gemstok · login_history',
      doHere: ['+ Plan an update → add checklist items → move the status to Live when it\'s out.']),
  _Topic('System', 'Servers', 'Each Supabase project (Active / PAUSED), edge functions, logs, cron jobs, keep-alive pings, '
      'and the app switches (maintenance mode, minimum version).',
      needs: 'Supabase access tokens for status/functions/logs; Actions login for the app switches.'),
  _Topic('System', 'Storage', 'Small pies: each database\'s size against its 500 MB. Click one for what fills it. '
      'Below: photo storage (Cloudflare R2) against 10 GB.', from: 'each database, Cloudflare R2 analytics'),
  _Topic('System', 'ASK', 'Save a question with today\'s numbers attached. Then say "answer" in the Claude chat — '
      'the answer appears here.', from: 'gemstok_hq/ask/ (only on this Mac)'),
  _Topic('System', 'Settings', 'Keys and logins (Keychain only), How to use HQ, and Recovery.',
      doHere: ['Each database: Add → pooler host + that database\'s hq_reader password → Check.',
        'Show (Touch ID) reveals a saved password for 30 seconds.']),
];

class _HelpViewState extends State<HelpView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final shown = _topics
        .where((t) => q.isEmpty || '${t.name} ${t.shows} ${t.from} ${t.needs} ${t.doHere.join(' ')}'.toLowerCase().contains(q))
        .toList();
    final groups = <String>{for (final t in shown) t.group};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 380,
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Search, e.g. "agent", "QR", "password"', prefixIcon: Icon(Icons.search, size: 18), isDense: true),
        ),
      ),
      const SizedBox(height: 8),
      if (shown.isEmpty) Text('Nothing found.', style: jost(13, color: HqColors.muted)),
      for (final g in groups) ...[
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(g.toUpperCase(), style: jost(11, weight: 600, color: HqColors.muted).copyWith(letterSpacing: 1.2)),
        ),
        for (final t in shown.where((t) => t.group == g)) _card(t),
      ],
    ]);
  }

  Widget _card(_Topic t) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HqColors.surface,
          border: Border.all(color: HqColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.name, style: jost(16, weight: 600)),
          const SizedBox(height: 4),
          Text(t.shows, style: jost(14)),
          for (final d in t.doHere)
            Padding(padding: const EdgeInsets.only(top: 3, left: 4), child: Text('•  $d', style: jost(13))),
          if (t.from.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('From: ${t.from}', style: jost(12, color: HqColors.muted))),
          if (t.needs.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text('Needs: ${t.needs}', style: jost(12, color: HqColors.warn))),
        ]),
      );
}
