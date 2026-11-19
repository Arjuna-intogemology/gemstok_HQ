/// Sidebar sections, in sidebar order. `group` = the small heading it sits under
/// (null = stands alone: Today at the top, ASK and Settings at the bottom).
/// `ready` = built; the others show what's coming and stay grey.
enum HqSection {
  today('Today', 'Sign-ups, active people, stones listed, credits bought — today and last 7 days.', ready: true),

  joining('Joining', 'Sign-ups per day / week, by app and by sign-in type (Apple · Google · Email).',
      group: 'People', ready: true),
  using('Using', 'Active people in the last 24 hours, 7 and 30 days, per app.', group: 'People', ready: true),
  staying('Staying', 'Of the people who joined each week: how many came back in their first week.',
      group: 'People', ready: true),
  doing('Doing', 'Market stones, boosts, credits bought / spent, chats started, Gemmit posts / circles, follows.',
      group: 'People', ready: true),
  people('People', 'Search by GSM ID → name, username, joined, apps used, last seen, tier, stone count.',
      group: 'People', ready: true),

  reports('Reports', 'Every report people send from the apps, in one place.', group: 'Inbox', ready: true),
  restores('Restore requests', 'Deleted members who came back: old GSM → new TEMP id, waiting time, the SQL line to approve.',
      group: 'Inbox', ready: true),
  ideas('Ideas', 'New ideas users bring in — noted, then New → Thinking → Planned → Done.', group: 'Inbox', ready: true),

  money('Money', 'Store purchases, App Store proceeds and in-app purchases, AdMob earnings.',
      group: 'Business', ready: true),
  downloads('Downloads', 'iPhone downloads and updates, Android installs and active devices, store reviews.',
      group: 'Business', ready: true),
  leads('Leads', 'Campaign links + printable QR, per place or per person; clicks and sign-ups per tag.',
      group: 'Business', ready: true),
  blogs('Blogs', 'Write and publish posts on the 5 blogs (intoGEMOLOGY, gemstok.com, ManiKVault, Quvlet, Gemmit).',
      group: 'Business', ready: true),
  websites('Websites', 'Visitors and page views per site (Cloudflare).', group: 'Business', ready: true),

  releases('Releases', 'Per app: version on this Mac vs versions in use, and the planned updates with checklists.',
      group: 'System', ready: true),
  renewals('Renewals', 'Keys, secrets and memberships that expire — countdown, warning on Today 30 days before.',
      group: 'System', ready: true),
  servers('Servers', 'Status, edge functions, logs, keep alive, cron jobs, app switches.', group: 'System', ready: true),
  storage('Storage', 'Database sizes (500 MB each) and R2 photo storage (10 GB), as pies.', group: 'System', ready: true),

  ask('ASK', 'Save a question; say "answer" in the Claude chat; the answer shows here.', ready: true),
  settings('Settings', 'Keys and connection checks.', ready: true);

  const HqSection(this.label, this.about, {this.group, this.ready = false});

  final String label;
  final String about;
  final String? group;
  final bool ready;
}
