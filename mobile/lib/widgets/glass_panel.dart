import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';

/// Glassmorphism panel with a light rim and a soft bottom glow (PDF pages 1–4).
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.radius = 56, this.padding = const EdgeInsets.all(20), this.blur = 14});

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: const [BoxShadow(color: Color(0x553A6BFF), blurRadius: 30, spreadRadius: 1, offset: Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x40FFFFFF), Color(0x1AFFFFFF), Color(0x26FFFFFF)],
              ),
              border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.85), width: 2),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
