/// Small helpers to show dates and numbers the same way everywhere.
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// For SQL `date` values (a day, no time): "13 Nov".
String fmtDay(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// For SQL timestamps: "13 Nov 2026" in this Mac's time.
String fmtDate(DateTime? d) {
  if (d == null) return '–';
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// "16:42" in this Mac's time.
String fmtTime(DateTime d) {
  final l = d.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// "13 Nov 2026 16:42"
String fmtDateTime(DateTime? d) => d == null ? '–' : '${fmtDate(d)} ${fmtTime(d)}';

/// "3 h ago", "2 days ago"
String fmtAgo(DateTime? d) {
  if (d == null) return 'never';
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} days ago';
}

/// Whole numbers without ".0", others with one decimal.
String fmtNum(Object? v) {
  if (v == null) return '–';
  if (v is double) return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  return '$v';
}

String fmtPct(int part, int whole) => whole == 0 ? '–' : '${(100 * part / whole).round()}%';

/// Today's date (this Mac's calendar) as a plain day, to compare with SQL `date` values.
DateTime todayDay() {
  final n = DateTime.now();
  return DateTime.utc(n.year, n.month, n.day);
}

/// A SQL `date` value as a plain day.
DateTime asDay(Object? v) {
  final d = v as DateTime;
  return DateTime.utc(d.year, d.month, d.day);
}

/// Monday of that day's week.
DateTime weekStart(DateTime day) => day.subtract(Duration(days: day.weekday - 1));

/// The Mac-calendar day of a SQL timestamp, as a plain day.
DateTime dayOf(DateTime timestamp) {
  final l = timestamp.toLocal();
  return DateTime.utc(l.year, l.month, l.day);
}
