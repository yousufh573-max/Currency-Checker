import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';

/// Cyan audio waveform (PDF). Amplitude follows the live microphone level
/// when [level] is provided and [active] is true; otherwise it idles gently.
/// Decorative: excluded from the accessibility tree.
class Waveform extends StatefulWidget {
  const Waveform({super.key, this.level, this.active = true, this.bars = 48, this.height = 110, this.width = 300, this.style = WaveStyle.dense});

  final ValueListenable<double>? level;
  final bool active;
  final int bars;
  final double height;
  final double width;
  final WaveStyle style;

  @override
  State<Waveform> createState() => _WaveformState();
}

enum WaveStyle { dense, sparse }

class _WaveformState extends State<Waveform> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  final _smoothed = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _sync();
    widget.level?.addListener(_onLevel);
  }

  void _sync() {
    // Respect "remove animations" accessibility settings.
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.active && !reduce) {
      _c.repeat();
    } else {
      _c.stop();
    }
  }

  void _onLevel() {
    final target = widget.level!.value;
    _smoothed.value = _smoothed.value * 0.6 + target * 0.4;
  }

  @override
  void didUpdateWidget(Waveform old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) {
      old.level?.removeListener(_onLevel);
      widget.level?.addListener(_onLevel);
    }
    if (old.active != widget.active) _sync();
  }

  @override
  void dispose() {
    widget.level?.removeListener(_onLevel);
    _c.dispose();
    _smoothed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(widget.width, widget.height),
            painter: _WavePainter(_c, _smoothed, widget.bars, widget.active, widget.style),
          ),
        ),
      );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.anim, this.level, this.bars, this.active, this.style) : super(repaint: Listenable.merge([anim, level]));
  final Animation<double> anim;
  final ValueListenable<double> level;
  final int bars;
  final bool active;
  final WaveStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.cyan
      ..strokeCap = StrokeCap.round
      ..strokeWidth = style == WaveStyle.dense ? math.max(2.0, size.width / bars * 0.45) : math.max(3.0, size.width / bars * 0.35);
    final t = anim.value * 2 * math.pi;
    final lv = active ? 0.35 + 0.65 * level.value : 0.15;
    final mid = size.height / 2;
    for (var i = 0; i < bars; i++) {
      final x = (i + 0.5) * size.width / bars;
      final pos = i / (bars - 1);
      // Bell-shaped envelope like the design, modulated by pseudo-random motion.
      final env = style == WaveStyle.dense ? math.exp(-math.pow((pos - 0.5) * 3.2, 2)) : 0.55 + 0.45 * math.sin(pos * math.pi * 3).abs();
      final wobble = 0.55 + 0.45 * math.sin(t * (1.0 + (i % 5) * 0.37) + i * 1.7);
      final hh = math.max(3.0, mid * env * wobble * lv);
      canvas.drawLine(Offset(x, mid - hh), Offset(x, mid + hh), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.active != active || old.bars != bars;
}
