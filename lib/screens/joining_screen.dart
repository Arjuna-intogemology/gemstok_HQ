import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../db/hq_data.dart';
import '../db/queries.dart';
import '../widgets/charts.dart';
import '../widgets/format.dart';
import '../widgets/screen_frame.dart';

/// Joining: sign-ups per day / week, by app and by sign-in type.
class JoiningScreen extends StatefulWidget {
  const JoiningScreen({super.key, required this.data});
  final HqData data;

  @override
  State<JoiningScreen> createState() => _JoiningScreenState();
}

class _JoiningScreenState extends State<JoiningScreen> {
  int _days = 30; // 0 = all time
  bool _weeks = false;

  static const _appNames = {
    'manikvault': 'ManiKVault',
    'gem_broker': 'Gem Broker',
    'quvlet': 'Quvlet',
    'gemmit': 'Gemmit',
    'intogemology': 'IntoGemology',
    'gemstok': 'Gemstok account site',
    'no app yet': 'No app opened yet',
  };

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Joining',
      subtitle: 'Who signed up, when, in which app, and how they signed in.',
      data: widget.data,
      queries: const [Q.joining],
      body: () {
        final all = widget.data.rows(Q.joining);
        if (all == null) return [];
        final today = todayDay();
        final from = _days == 0 ? null : today.subtract(Duration(days: _days - 1));
        final rows = all.where((r) => from == null || !asDay(r['day']).isBefore(from)).toList();
        final total = rows.fold<int>(0, (a, r) => a + (r['n'] as int));

        // ---- bars: per day, or per week (Monday)
        final buckets = <DateTime, double>{};
        if (!_weeks && from != null) {
          for (var d = from; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
            buckets[d] = 0;
          }
        }
        for (final r in rows) {
          final day = asDay(r['day']);
          final key = _weeks ? weekStart(day) : day;
          buckets[key] = (buckets[key] ?? 0) + (r['n'] as int);
        }
        if (_weeks && buckets.isNotEmpty) {
          final first = buckets.keys.reduce((a, b) => a.isBefore(b) ? a : b);
          for (var w = first; !w.isAfter(today); w = w.add(const Duration(days: 7))) {
            buckets.putIfAbsent(w, () => 0);
          }
        }
        final keys = buckets.keys.toList()..sort();
        final bars = [for (final k in keys) (_weeks ? 'wk ${fmtDay(k)}' : fmtDay(k), buckets[k]!)];

        // ---- by app / by sign-in type
        final byApp = <String, (int, int)>{}; // app → (count, guessed)
        final bySignin = <String, int>{};
        for (final r in rows) {
          final app = r['app'] as String;
          final n = r['n'] as int;
          final g = (r['guessed'] as bool) ? n : 0;
          final old = byApp[app] ?? (0, 0);
          byApp[app] = (old.$1 + n, old.$2 + g);
          final s = r['signin'] as String;
          bySignin[s] = (bySignin[s] ?? 0) + n;
        }
        final appRows = byApp.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
        final signRows = bySignin.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        return [
          Wrap(spacing: 16, runSpacing: 8, children: [
            Choice<int>(
              options: const {7: '7 days', 30: '30 days', 90: '90 days', 0: 'All time'},
              value: _days,
              onChanged: (v) => setState(() => _days = v),
            ),
            Choice<bool>(
              options: const {false: 'Per day', true: 'Per week'},
              value: _weeks,
              onChanged: (v) => setState(() => _weeks = v),
            ),
          ]),
          const SizedBox(height: 16),
          Text('$total sign-ups', style: jost(32, weight: 600)),
          const SizedBox(height: 8),
          Bars(items: bars),
          const Heading('By app',
              note: '"guessed" = the app didn\'t record it yet, so HQ uses the first app they opened.'),
          SimpleTable(
            header: const ['App', 'Sign-ups', 'Share', 'Guessed'],
            rows: [
              for (final e in appRows)
                [
                  _appNames[e.key] ?? e.key,
                  '${e.value.$1}',
                  fmtPct(e.value.$1, total),
                  e.value.$2 == 0 ? '–' : '${e.value.$2}',
                ],
            ],
          ),
          const Heading('By sign-in type'),
          SimpleTable(
            header: const ['Signed in with', 'Sign-ups', 'Share'],
            rows: [
              for (final e in signRows) [_signin(e.key), '${e.value}', fmtPct(e.value, total)],
            ],
          ),
          const SizedBox(height: 20),
          Text('Source: ${Q.joining.source}', style: jost(11, color: HqColors.muted)),
        ];
      },
    );
  }

  static String _signin(String s) => switch (s) {
        'apple' => 'Apple',
        'google' => 'Google',
        'email' => 'Email',
        _ => s,
      };
}
