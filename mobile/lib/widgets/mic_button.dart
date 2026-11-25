import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';

/// Blue circular microphone button that pulses while listening (PDF page 6).
class MicButton extends StatefulWidget {
  const MicButton({super.key, required this.listening, required this.onPressed, required this.label, this.size = 140});
  final ValueListenable<bool> listening;
  final VoidCallback onPressed;
  final String label;
  final double size;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    widget.listening.addListener(_sync);
    _sync();
  }

  void _sync() {
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.listening.value && !reduce) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    widget.listening.removeListener(_sync);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF3A86F5), Color(0xFF2B5FC9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: AppColors.micBlue.withValues(alpha: 0.55), blurRadius: 12 + 26 * _pulse.value, spreadRadius: 10 * _pulse.value)],
            ),
            child: child,
          ),
          child: Icon(Icons.mic_none_rounded, size: s * 0.55, color: AppColors.white),
        ),
      ),
    );
  }
}
