import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../services/recognition/recognition_engine.dart';

/// Navy page background with a soft blue glow at the top (depth without noise).
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.3,
            colors: [Color(0xFF14295A), AppColors.navy],
            stops: [0, 0.75],
          ),
        ),
        child: child,
      );
}

/// Compact glass pill: "Total ৳120 · 2 notes".
class TotalChip extends StatelessWidget {
  const TotalChip({super.key, required this.total, required this.count, required this.label, required this.notesLabel, required this.shortNotesLabel});
  final int total;
  final int count;
  final String label;
  final String notesLabel;
  final String shortNotesLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label ${taka(total)}, $count $notesLabel',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xB3071529),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.7), width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 22, color: AppColors.cyan),
            const SizedBox(width: 8),
            Text(taka(total),
                style: const TextStyle(fontFamily: AppFonts.display, fontFamilyFallback: AppFonts.fallback, fontSize: 24, color: Colors.white)),
            const SizedBox(width: 8),
            Text('· $count $shortNotesLabel', style: const TextStyle(fontSize: 18, color: Color(0xFFD5DEE8))),
          ]),
        ),
      );
}

/// Circular action with its label underneath (camera-app style).
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    this.size = 64,
    this.color = AppColors.glassBorder,
    this.filled = false,
    this.progress,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;
  final double size;
  final Color color;
  final bool filled;

  /// Optional 0..1 ring around the button (e.g. steadiness before auto-capture).
  final ValueListenable<double>? progress;

  @override
  Widget build(BuildContext context) {
    Widget circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : const Color(0x99071529),
        border: Border.all(color: color, width: 3),
        boxShadow: filled ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 18)] : null,
      ),
      child: Icon(icon, size: size * 0.45, color: filled ? AppColors.navy : Colors.white),
    );
    if (progress != null) {
      circle = SizedBox(
        width: size + 14,
        height: size + 14,
        child: Stack(alignment: Alignment.center, children: [
          ValueListenableBuilder<double>(
            valueListenable: progress!,
            builder: (_, v, _) => SizedBox(
              width: size + 14,
              height: size + 14,
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: 5,
                color: v >= 1 ? AppColors.successGreen : AppColors.scanYellow,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
          circle,
        ]),
      );
    }
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            circle,
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}

/// Labelled horizontal meter (confidence, torn ratio, money coverage).
class MeterBar extends StatelessWidget {
  const MeterBar({super.key, required this.value, required this.color, this.marker, this.height = 10});
  final double value; // 0..1
  final Color color;

  /// Optional 0..1 position of a threshold tick.
  final double? marker;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return SizedBox(
            height: height + 6,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                top: 3,
                left: 0,
                right: 0,
                child: Container(height: height, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(height))),
              ),
              Positioned(
                top: 3,
                left: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  width: w * value.clamp(0.0, 1.0),
                  height: height,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
                ),
              ),
              if (marker != null)
                Positioned(left: w * marker!.clamp(0.0, 1.0) - 1, top: 0, child: Container(width: 2, height: height + 6, color: Colors.white70)),
            ]),
          );
        }),
      );
}

/// Shows which recognition engine is active (honest about demo / missing model).
class ModeBadge extends StatelessWidget {
  const ModeBadge({super.key, required this.mode, required this.label});
  final EngineMode mode;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (mode) {
      EngineMode.onDevice => (Icons.phone_android_rounded, AppColors.cyan),
      EngineMode.server => (Icons.cloud_outlined, AppColors.glassBorder),
      EngineMode.demo => (Icons.science_outlined, AppColors.amber),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: color, width: 1.5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 16, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Themed section card used on the settings screen.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Row(children: [
              Icon(icon, color: AppColors.cyan, size: 26),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ]),
          ),
          const SizedBox(height: 6),
          ...children,
        ]),
      );
}
