import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';

/// Rounded outlined banner with a speaker icon showing the spoken message
/// (PDF pages 4–7). Announced as a live region for TalkBack users.
class SpeakerBanner extends StatelessWidget {
  const SpeakerBanner({super.key, required this.text, required this.color, this.onTap, this.bold = false});
  final String text;
  final Color color;
  final VoidCallback? onTap;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: bold ? FontWeight.w700 : null);
    return Semantics(
      liveRegion: true,
      button: onTap != null,
      label: text,
      hint: onTap != null ? 'Double tap to hear again' : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(40), border: Border.all(color: color, width: 3)),
          child: Row(children: [
            const Icon(Icons.volume_up_rounded, size: 52, color: AppColors.white),
            const SizedBox(width: 14),
            Expanded(child: Text(text, textAlign: TextAlign.center, style: style)),
          ]),
        ),
      ),
    );
  }
}

/// Rounded card with coloured outline (result cards).
class OutlinedCard extends StatelessWidget {
  const OutlinedCard({super.key, required this.child, required this.color, this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 12)});
  final Widget child;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), border: Border.all(color: color, width: 3)),
        child: child,
      );
}

/// Hand-drawn style outline used on PDF pages 6–7.
class SketchyBorder extends StatelessWidget {
  const SketchyBorder({super.key, required this.child, required this.color, this.strokeWidth = 3, this.seed = 1, this.radius = 48});
  final Widget child;
  final Color color;
  final double strokeWidth;
  final int seed;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SketchyPainter(color, strokeWidth, seed, radius), child: child);
}

class _SketchyPainter extends CustomPainter {
  _SketchyPainter(this.color, this.width, this.seed, this.radius);
  final Color color;
  final double width;
  final int seed;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(width), Radius.circular(math.min(radius, size.height / 2.2)));
    final metric = (Path()..addRRect(rrect)).computeMetrics().first;
    final rnd = math.Random(seed);
    final path = Path();
    const steps = 90;
    for (var i = 0; i <= steps; i++) {
      final tan = metric.getTangentForOffset(metric.length * i / steps)!;
      final n = Offset(-tan.vector.dy, tan.vector.dx);
      final p = tan.position + n * ((rnd.nextDouble() - 0.5) * 3.0);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SketchyPainter old) => old.color != color || old.seed != seed;
}

/// Large accessible action button (min 64dp) with icon + text.
class BigActionButton extends StatelessWidget {
  const BigActionButton({super.key, required this.label, required this.icon, required this.onPressed, this.color = AppColors.steel, this.hint, this.shortLabel});

  /// Full label (announced by TalkBack).
  final String label;

  /// Optional shorter text shown on screen.
  final String? shortLabel;
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        hint: hint,
        excludeSemantics: true,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 72),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            side: BorderSide(color: color, width: 2.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          ),
          // Icon above the label; the label scales down rather than breaking words.
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 28, color: AppColors.white),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(shortLabel ?? label, maxLines: 1, style: Theme.of(context).textTheme.labelLarge),
            ),
          ]),
        ),
      );
}

/// Persistent banner that makes demo mode impossible to miss.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        label: text,
        container: true,
        child: Container(
          width: double.infinity,
          color: AppColors.amber,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Text(text,
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16, fontFamily: AppFonts.body)),
        ),
      );
}

/// "৳ 120" in large display font.
class TakaAmount extends StatelessWidget {
  const TakaAmount(this.amount, {super.key, this.size = 56, this.color = AppColors.white});
  final int amount;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        taka(amount),
        style: TextStyle(fontFamily: AppFonts.display, fontFamilyFallback: AppFonts.fallback, fontSize: size, color: color, height: 1.1),
      );
}
