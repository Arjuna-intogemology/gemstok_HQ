import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../ask/ask_screen.dart';
import '../blogs/blogs_screen.dart';
import '../db/hq_data.dart';
import '../ideas/ideas_screen.dart';
import '../keepalive/keep_alive.dart';
import '../leads/leads_screen.dart';
import '../lock/lock_controller.dart';
import '../releases/releases_screen.dart';
import '../renewals/renewals_screen.dart';
import '../screens/doing_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/joining_screen.dart';
import '../screens/money_screen.dart';
import '../screens/people_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/restores_screen.dart';
import '../screens/servers_screen.dart';
import '../screens/storage_screen.dart';
import '../screens/today_screen.dart';
import '../screens/using_screen.dart';
import '../screens/websites_screen.dart';
import '../servers/servers_data.dart';
import '../services/services_data.dart';
import '../settings/settings_screen.dart';
import 'sections.dart';

/// Sidebar + the open section. Built fresh on every unlock; owns the cache (HqData),
/// so locking throws every loaded number away.
class HqShell extends StatefulWidget {
  const HqShell({super.key, required this.lock, required this.keepAlive});

  final LockController lock;
  final HqKeepAlive keepAlive; // lives for the whole app (keeps pinging while locked)

  @override
  State<HqShell> createState() => _HqShellState();
}

class _HqShellState extends State<HqShell> {
  HqSection _open = HqSection.today;
  late final _data = HqData(onRead: widget.keepAlive.markRead);
  final _servers = ServersData(); // Supabase Management API (read-only), while unlocked
  final _services = ServicesData(); // App Store, Google Play, AdMob, Cloudflare (read-only), while unlocked

  @override
  void dispose() {
    _data.dispose();
    _servers.dispose();
    _services.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sidebar(),
          const VerticalDivider(width: 1),
          // KeyedSubtree: each section gets its own state (choices like "30 days" reset per visit;
          // the numbers themselves stay in the cache).
          Expanded(child: KeyedSubtree(key: ValueKey(_open), child: _page(_open))),
        ],
      ),
    );
  }

  Widget _sidebar() => Container(
        width: 230,
        color: HqColors.sidebar,
        padding: const EdgeInsets.fromLTRB(14, 28, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 22),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset('assets/logo/hq_logo.png', width: 30, height: 30),
                ),
                const SizedBox(width: 10),
                Text('GEMSTOK HQ', style: jost(17, weight: 600)),
              ]),
            ),
            _home(),
            const SizedBox(height: 6),
            // the list scrolls when the window is short; ASK, Settings and Lock stay at the bottom
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final g in _groups) ...[
                    _groupLabel(g),
                    // drop-down: the group's pages slide open / closed
                    AnimatedSize(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: _isOpen(g)
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [for (final s in HqSection.values) if (s.group == g) _item(s)],
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            _item(HqSection.ask),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _footButton(Icons.settings_outlined, 'Settings', () => setState(() => _open = HqSection.settings),
                  selected: _open == HqSection.settings)),
              _footButton(Icons.lock_outline, 'Lock', widget.lock.lock),
            ]),
          ],
        ),
      );

  /// Today: the home of HQ — its own look, above the groups.
  Widget _home() {
    final selected = _open == HqSection.today;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _open = HqSection.today),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? HqColors.accent : HqColors.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.wb_sunny_outlined, size: 18, color: selected ? Colors.white : HqColors.accent),
          const SizedBox(width: 10),
          Text('Today', style: jost(15, weight: 600, color: selected ? Colors.white : HqColors.accent)),
        ]),
      ),
    );
  }

  /// Groups in sidebar order: People, Inbox, Business, System.
  static final _groups = <String>{
    for (final s in HqSection.values)
      if (s.group != null) s.group!,
  }.toList();

  /// Which groups are open. Static, so it stays as you left it after HQ locks and unlocks.
  static final _openGroups = <String>{'People'};

  /// The group of the page you're on is always shown open.
  bool _isOpen(String g) => _openGroups.contains(g) || _open.group == g;

  /// Group heading = the drop-down button. Shows how many pages are inside when closed.
  Widget _groupLabel(String g) {
    final open = _isOpen(g);
    final here = _open.group == g;
    final count = HqSection.values.where((s) => s.group == g).length;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() {
        if (open) {
          _openGroups.remove(g);
          if (here) _open = HqSection.today; // closing the group you're in → back to Today
        } else {
          _openGroups.add(g);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 6, 6),
        child: Row(children: [
          Expanded(
            child: Text(g.toUpperCase(),
                style: jost(10.5, weight: 600, color: here ? HqColors.ink : HqColors.muted)
                    .copyWith(letterSpacing: 1.2)),
          ),
          if (!open) Text('$count', style: jost(11, color: HqColors.muted)),
          AnimatedRotation(
            turns: open ? 0 : -0.25,
            duration: const Duration(milliseconds: 160),
            child: const Icon(Icons.expand_more, size: 18, color: HqColors.muted),
          ),
        ]),
      ),
    );
  }

  /// Settings / Lock: small, quiet, pinned at the bottom.
  Widget _footButton(IconData icon, String label, VoidCallback onTap, {bool selected = false}) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? HqColors.surface : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: selected ? HqColors.ink : HqColors.muted),
            const SizedBox(width: 6),
            Text(label,
                style: jost(13, weight: selected ? 600.0 : 500.0, color: selected ? HqColors.ink : HqColors.muted)),
          ]),
        ),
      );

  Widget _item(HqSection s) {
    final selected = s == _open;
    final dim = !s.ready;
    final claude = s == HqSection.ask;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() {
        _open = s;
        if (s.group != null) _openGroups.add(s.group!);
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: claude ? HqColors.claudeTint : (selected ? HqColors.surface : null),
          border: claude && selected ? Border.all(color: HqColors.claude) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          s.label,
          style: jost(14,
              weight: selected || claude ? 600.0 : 450.0,
              color: claude ? HqColors.claude : (dim ? HqColors.muted.withValues(alpha: 0.6) : HqColors.ink)),
        ),
      ),
    );
  }

  Widget _page(HqSection s) => switch (s) {
        HqSection.today => TodayScreen(
            data: _data,
            onOpenRenewals: () => setState(() {
                  _open = HqSection.renewals;
                  _openGroups.add('System');
                }),
            onOpenSection: (sec) => setState(() {
                  _open = sec;
                  if (sec.group != null) _openGroups.add(sec.group!);
                })),
        HqSection.joining => JoiningScreen(data: _data),
        HqSection.using => UsingScreen(data: _data),
        HqSection.staying => UsingScreen(data: _data, staying: true),
        HqSection.doing => DoingScreen(data: _data),
        HqSection.people => PeopleScreen(data: _data),
        HqSection.reports => ReportsScreen(data: _data),
        HqSection.restores => RestoresScreen(data: _data),
        HqSection.ideas => IdeasScreen(data: _data),
        HqSection.leads => LeadsScreen(data: _data),
        HqSection.websites => WebsitesScreen(services: _services),
        HqSection.downloads => DownloadsScreen(services: _services),
        HqSection.storage => StorageScreen(data: _data, services: _services),
        HqSection.blogs => const BlogsScreen(),
        HqSection.releases => ReleasesScreen(data: _data),
        HqSection.renewals => const RenewalsScreen(),
        HqSection.money => MoneyScreen(data: _data, services: _services),
        HqSection.servers => ServersScreen(keepAlive: widget.keepAlive, servers: _servers, data: _data),
        HqSection.ask => AskScreen(data: _data),
        HqSection.settings => SettingsScreen(services: _services),
      };
}
