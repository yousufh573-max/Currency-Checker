import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';

/// Yellow rounded corner brackets of the scanning frame (PDF page 2).
/// [pulse] 0..1 animates the bracket length; [locked] turns them green.
class ScanBracketsPainter extends CustomPainter {
  ScanBracketsPainter({required this.rect, required this.pulse, this.locked = false}) : super(repaint: pulse);
  final Rect rect;
  final Animation<double> pulse;
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = locked ? AppColors.successGreen : AppColors.scanYellow
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final r = math.min(40.0, rect.shortestSide / 6);
    final len = rect.width * (0.30 + 0.04 * pulse.value);
    final vlen = rect.height * (0.30 + 0.04 * pulse.value);
    final l = rect.left, t = rect.top, rt = rect.right, b = rect.bottom;
    // Top-left
    canvas.drawPath(
        Path()
          ..moveTo(l, t + vlen)
          ..lineTo(l, t + r)
          ..arcToPoint(Offset(l + r, t), radius: Radius.circular(r))
          ..lineTo(l + len, t),
        p);
    // Top-right
    canvas.drawPath(
        Path()
          ..moveTo(rt - len, t)
          ..lineTo(rt - r, t)
          ..arcToPoint(Offset(rt, t + r), radius: Radius.circular(r))
          ..lineTo(rt, t + vlen),
        p);
    // Bottom-right
    canvas.drawPath(
        Path()
          ..moveTo(rt, b - vlen)
          ..lineTo(rt, b - r)
          ..arcToPoint(Offset(rt - r, b), radius: Radius.circular(r))
          ..lineTo(rt - len, b),
        p);
    // Bottom-left
    canvas.drawPath(
        Path()
          ..moveTo(l + len, b)
          ..lineTo(l + r, b)
          ..arcToPoint(Offset(l, b - r), radius: Radius.circular(r))
          ..lineTo(l, b - vlen),
        p);
  }

  @override
  bool shouldRepaint(ScanBracketsPainter old) => old.rect != rect || old.locked != locked;
}

/// Segmented blue progress ring with an outlined "current" segment (PDF page 3).
class SegmentedRingPainter extends CustomPainter {
  SegmentedRingPainter({required this.progress, required this.pulse, this.segments = 12}) : super(repaint: pulse);
  final double progress; // 0..1
  final Animation<double> pulse;
  final int segments;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final thick = outer * 0.26;
    final rect = Rect.fromCircle(center: c, radius: outer - thick / 2);
    final sweep = 2 * math.pi / segments;
    const gap = 0.035;
    final filled = (progress * segments).floor();
    for (var i = 0; i < segments; i++) {
      final start = -math.pi / 2 + i * sweep + gap / 2;
      final isCurrent = i == filled && progress < 1;
      final paint = Paint()
        ..color = isCurrent ? AppColors.brightBlue.withValues(alpha: 0.4 + 0.6 * pulse.value) : AppColors.brightBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = isCurrent ? 3 : thick;
      if (i < filled) {
        canvas.drawArc(rect, start, sweep - gap, false, paint);
      } else if (isCurrent) {
        final o = Rect.fromCircle(center: c, radius: outer - 1.5);
        final inn = Rect.fromCircle(center: c, radius: outer - thick + 1.5);
        final path = Path()
          ..arcTo(o, start, sweep - gap, true)
          ..arcTo(inn, start + sweep - gap, -(sweep - gap), false)
          ..close();
        canvas.drawPath(path, paint);
      } else {
        canvas.drawArc(rect, start, sweep - gap, false, Paint()
          ..color = AppColors.brightBlue.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = thick);
      }
    }
  }

  @override
  bool shouldRepaint(SegmentedRingPainter old) => old.progress != progress;
}
