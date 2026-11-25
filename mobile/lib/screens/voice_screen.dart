import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/strings.dart';
import '../providers/providers.dart';
import '../services/voice/voice_service.dart';

/// Shared voice behaviour for screens: speak, listen for commands while the
/// screen is visible, stop listening when it goes away, haptic feedback.
mixin VoiceScreen<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final VoiceIO voice = ref.read(voiceProvider);
  Object? _listenToken;

  S get s => ref.read(stringsProvider);

  /// Called with each final phrase recognised while this screen listens.
  void onVoice(String words);

  Future<void> say(String text) => voice.speak(text);

  void startListening() {
    _listenToken = voice.listen((w) {
      if (mounted) onVoice(w);
    });
  }

  void stopListening() {
    final token = _listenToken;
    _listenToken = null;
    // Only stop our own session; a null token would stop whichever screen is listening now.
    if (token != null) voice.stopListening(token);
  }

  Future<void> sayThenListen(String text) async {
    startListening(); // recognition starts automatically once speech finishes
    await say(text);
  }

  void haptic(HapticKind kind) {
    if (!ref.read(settingsProvider).haptics) return;
    switch (kind) {
      case HapticKind.tap:
        HapticFeedback.selectionClick();
      case HapticKind.success:
        HapticFeedback.lightImpact();
        Future.delayed(const Duration(milliseconds: 120), HapticFeedback.lightImpact);
      case HapticKind.warning:
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 200), HapticFeedback.heavyImpact);
        Future.delayed(const Duration(milliseconds: 400), HapticFeedback.heavyImpact);
      case HapticKind.capture:
        HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

enum HapticKind { tap, success, warning, capture }
