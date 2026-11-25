import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import '../providers/providers.dart';
import '../services/voice/command_parser.dart';
import '../widgets/glass_panel.dart';
import '../widgets/waveform.dart';
import 'voice_screen.dart';

/// Screen 1 — Welcome and voice activation (PDF page 1).
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> with VoiceScreen {
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final micOk = await _ensurePermission(Permission.microphone);
    if (micOk) await voice.init();
    if (!mounted) return;
    if (micOk && voice.micAvailable.value) {
      await sayThenListen(s.welcomeSpeech);
    } else {
      await say('${s.welcomeSpeech} ${s.micPermissionDenied}');
    }
  }

  Future<bool> _ensurePermission(Permission p) async {
    try {
      final st = await p.request();
      return st.isGranted || st.isLimited;
    } catch (_) {
      return false; // permission plugin unavailable (e.g. tests)
    }
  }

  @override
  void onVoice(String words) {
    final cmd = parseCommand(words, allowed: {VoiceCommand.start, VoiceCommand.scan, VoiceCommand.scanAgain, VoiceCommand.repeat});
    if (cmd == VoiceCommand.repeat) {
      say(s.welcomeSpeech);
    } else if (cmd != null) {
      _start();
    }
  }

  Future<void> _start() async {
    if (_navigating) return;
    _navigating = true;
    haptic(HapticKind.tap);
    final camOk = await _ensurePermission(Permission.camera);
    if (!mounted) return;
    if (!camOk) {
      _navigating = false;
      await say(s.cameraPermissionDenied);
      return;
    }
    if (ref.read(sessionProvider).completed) ref.read(sessionProvider.notifier).newSession();
    stopListening();
    await voice.stopAll();
    if (mounted) context.go('/scan');
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return Stack(children: [
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: w * 0.08, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 48),
                child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  // Large circular speaker icon with blue ring.
                  ExcludeSemantics(
                    child: Container(
                      width: w * 0.36,
                      height: w * 0.36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.ringBlue, width: 2.5),
                        boxShadow: const [BoxShadow(color: Color(0x553A4BCB), blurRadius: 18)],
                      ),
                      child: Icon(Icons.volume_up_rounded, size: w * 0.2, color: const Color(0xFFCFD8DF)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Semantics(
                    header: true,
                    child: Text(str.appTitle, textAlign: TextAlign.center, style: t.displayLarge!.copyWith(fontSize: w * 0.12)),
                  ),
                  const SizedBox(height: 14),
                  Text(str.tagline, textAlign: TextAlign.center, style: t.bodyLarge),
                  const SizedBox(height: 28),
                  // Glass listening panel with live status + waveform.
                  ValueListenableBuilder<bool>(
                    valueListenable: voice.speaking,
                    builder: (context, speaking, _) => ValueListenableBuilder<bool>(
                      valueListenable: voice.listening,
                      builder: (context, listening, _) {
                        final label = speaking ? str.speaking : (listening ? str.listening : str.notListening);
                        return GlassPanel(
                          padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
                          child: Column(children: [
                            Semantics(liveRegion: true, child: Text(label, textAlign: TextAlign.center, style: t.headlineMedium!.copyWith(fontSize: w * 0.085))),
                            const SizedBox(height: 18),
                            Waveform(level: voice.soundLevel, active: listening || speaking, width: w * 0.62, height: w * 0.2),
                          ]),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Microphone pill: tap alternative to saying "Start".
                  Semantics(
                    button: true,
                    label: '${str.sayStart}. Double tap to start scanning.',
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: _start,
                      borderRadius: BorderRadius.circular(60),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 88),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(60), border: Border.all(color: AppColors.steel, width: 5)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.mic_rounded, size: 56, color: Color(0xFF8FA6C2)),
                          const SizedBox(width: 14),
                          Flexible(child: Text(str.sayStart, style: t.bodyLarge!.copyWith(fontSize: 22))),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: str.settings,
                iconSize: 32,
                constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
                onPressed: () async {
                  stopListening();
                  await context.push('/settings');
                  if (mounted && voice.micAvailable.value) startListening();
                },
                icon: const Icon(Icons.settings_rounded, color: AppColors.glassBorder),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}
