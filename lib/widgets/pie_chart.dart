import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// One slice of a pie.
class PieSlice {
  const PieSlice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// Calm colours for slices, in order.
const pieColors = [
  Color(0xFF0089A8), Color(0xFFE0A526), Color(0xFF6A8CAF), Color(0xFF3FA37A),
  Color(0xFFC15F3C), Color(0xFF8E6BBF), Color(0xFF9AA83E), Color(0xFFB0587C),
  Color(0xFF5A6B78), Color(0xFF2E9CC4),
];

/// Pie chart: the chosen slice grows and moves out a little. Tap a slice to choose it
/// (tap it again to let go). The legend is drawn by the screen, so names can be clicked too.
class PieChart extends StatelessWidget {
  const PieChart({super.key, required this.slices, this.selected, this.onSelect, this.size = 220, this.centerText});

  final List<PieSlice> slices;
  final int? selected;
  final ValueChanged<int?>? onSelect;
  final double size;
  final String? centerText;

  double get _total => slices.fold(0.0, (a, s) => a + math.max(0, s.value));

  int? _hit(Offset p) {
    final c = Offset(size / 2, size / 2);
    final d = p - c;
    if (d.distance > size / 2 || d.distance < size * 0.22) return null;
    var a = math.atan2(d.dy, d.dx) + math.pi / 2; // 0 at the top, clockwise
    if (a < 0) a += 2 * math.pi;
    var start = 0.0;
    for (var i = 0; i < slices.length; i++) {
      final sweep = _total == 0 ? 0.0 : math.max(0, slices[i].value) / _total * 2 * math.pi;
      if (a >= start && a < start + sweep) return i;
      start += sweep;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty || _total == 0) {
      return SizedBox(width: size, height: size, child: Center(child: Text('No data yet.', style: jost(13, color: HqColors.muted))));
    }
    return GestureDetector(
      onTapUp: (d) {
        final i = _hit(d.localPosition);
        if (i != null) onSelect?.call(i == selected ? null : i);
      },
      child: TweenAnimationBuilder<double>(
        key: ValueKey(selected),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (context, t, _) => CustomPaint(
          size: Size.square(size),
          painter: _PiePainter(slices, selected, t, _total, centerText),
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.slices, this.selected, this.t, this.total, this.centerText);
  final List<PieSlice> slices;
  final int? selected;
  final double t; // 0 → 1 while the chosen slice grows
  final double total;
  final String? centerText;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 * 0.86; // room for the chosen slice to grow
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = math.max(0, slices[i].value) / total * 2 * math.pi;
      if (sweep <= 0) continue;
      final chosen = i == selected;
      final grow = chosen ? t : 0.0;
      final mid = start + sweep / 2;
      final offset = Offset(math.cos(mid), math.sin(mid)) * (size.width * 0.05 * grow);
      final radius = r * (1 + 0.12 * grow);
      final faded = selected != null && !chosen;
      final paint = Paint()..color = faded ? slices[i].color.withValues(alpha: 0.35) : slices[i].color;
      canvas.drawArc(Rect.fromCircle(center: c + offset, radius: radius), start, sweep, true, paint);
      // thin gap between slices
      canvas.drawArc(Rect.fromCircle(center: c + offset, radius: radius), start, sweep, true,
          Paint()
            ..color = HqColors.background
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      start += sweep;
    }
    // hole in the middle (a donut reads calmer) + optional text
    canvas.drawCircle(c, r * 0.5, Paint()..color = HqColors.background);
    if (centerText != null) {
      final tp = TextPainter(
        text: TextSpan(text: centerText, style: jost(15, weight: 600)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r);
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.selected != selected || old.t != t || old.slices != slices || old.centerText != centerText;
}
