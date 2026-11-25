import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../providers/providers.dart';
import '../services/voice/command_parser.dart';
import '../widgets/common.dart';
import 'scanner_screen.dart';
import 'voice_screen.dart';

/// Screen 7 — Session summary (PDF page 7). The wording says "Calculation
/// complete" (not "Transaction complete"): the app only counts cash.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});
  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> with VoiceScreen {
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Ensure the completed session is saved locally (not during build).
      ref.read(sessionProvider.notifier).complete();
      sayThenListen(s.summarySpeech(ref.read(sessionProvider)));
    });
  }

  Future<void> _askScanAgain() async {
    haptic(HapticKind.tap);
    setState(() => _confirming = true);
    say(s.confirmNewSession);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.confirmNewSession, style: Theme.of(ctx).textTheme.bodyLarge),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel, style: const TextStyle(fontSize: 20))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.confirm, style: const TextStyle(fontSize: 20))),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (ok == true) _startNew();
  }

  void _startNew() {
    ref.read(sessionProvider.notifier).newSession();
    ref.read(captureGateProvider).rearm();
    ref.read(scanFlowProvider.notifier).discardImage();
    context.go('/scan');
  }

  Future<void> _exit() async {
    haptic(HapticKind.tap);
    stopListening();
    await ref.read(scanFlowProvider.notifier).discardImage();
    await ref.read(tempImagesProvider)?.clearAll();
    await say(s.goodbye);
    ref.read(sessionProvider.notifier).newSession();
    await SystemNavigator.pop();
  }

  @override
  void onVoice(String words) {
    final cmd = parseCommand(words);
    if (_confirming) {
      if (cmd == VoiceCommand.confirm || cmd == VoiceCommand.scanAgain) {
        Navigator.of(context).pop(true);
      } else if (cmd == VoiceCommand.cancel || cmd == VoiceCommand.exit) {
        Navigator.of(context).pop(false);
      }
      return;
    }
    switch (cmd) {
      case VoiceCommand.scanAgain || VoiceCommand.scan || VoiceCommand.start:
        _askScanAgain();
      case VoiceCommand.exit || VoiceCommand.stop:
        _exit();
      case VoiceCommand.repeat || VoiceCommand.total:
        say(s.summarySpeech(ref.read(sessionProvider)));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(stringsProvider);
    final session = ref.watch(sessionProvider);
    final t = Theme.of(context).textTheme;
    final summaryStyle = TextStyle(fontFamily: AppFonts.body, fontFamilyFallback: AppFonts.fallback, color: AppColors.summaryText, fontSize: 24, height: 1.2);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return Column(children: [
            if (session.hasDemoScans) DemoBanner(text: str.demoBanner),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: w * 0.05, vertical: 16),
                child: Column(children: [
                  SpeakerBanner(text: str.summaryText(session), color: AppColors.successBorder, onTap: () => say(str.summarySpeech(session))),
                  const SizedBox(height: 22),
                  // Summary card: cream page, blue spine, offset black shadow.
                  Semantics(
                    container: true,
                    label: '${str.summary}. ${str.totalScannedLine(session.total)}. ${str.neededLine(session.requiredAmount)}. ${str.remainingLine(session.payment)}.',
                    excludeSemantics: true,
                    child: Container(
                      width: w * 0.74,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(14, 16))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 6), borderRadius: BorderRadius.circular(22)),
                          child: IntrinsicHeight(
                            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Container(width: w * 0.12, color: AppColors.summaryBlue),
                              Container(width: 5, color: Colors.black),
                              Expanded(
                                child: Container(
                                  color: AppColors.cream,
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black, width: 5))),
                                      child: Text(str.summary, textAlign: TextAlign.center, style: summaryStyle.copyWith(fontSize: 22)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(8, 18, 8, 26),
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(str.totalScannedLine(session.total), style: summaryStyle),
                                        const SizedBox(height: 22),
                                        Text(str.neededLine(session.requiredAmount), style: summaryStyle),
                                        const SizedBox(height: 22),
                                        Text(str.remainingLine(session.payment), style: summaryStyle),
                                        if (session.rejected.isNotEmpty) ...[
                                          const SizedBox(height: 22),
                                          Text(str.rejectedLine(session.rejected.length), style: summaryStyle.copyWith(color: const Color(0xFFB3261E))),
                                        ],
                                      ]),
                                    ),
                                  ]),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(str.cashOnlyDisclaimer, textAlign: TextAlign.center, style: t.bodyMedium!.copyWith(color: AppColors.glassBorder)),
                  const SizedBox(height: 18),
                  _ActionPanel(
                    color: AppColors.brightBlue,
                    icon: Icons.find_in_page_outlined,
                    iconColor: Colors.white,
                    title: str.scanAgainTitle,
                    hint: str.scanAgainHint,
                    onTap: _askScanAgain,
                    seed: 5,
                  ),
                  const SizedBox(height: 22),
                  _ActionPanel(
                    color: AppColors.warningRed,
                    icon: Icons.exit_to_app_rounded,
                    iconColor: const Color(0xFFE0262B),
                    title: str.exitTitle,
                    hint: str.exitHint,
                    onTap: _exit,
                    seed: 9,
                  ),
                ]),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({required this.color, required this.icon, required this.iconColor, required this.title, required this.hint, required this.onTap, required this.seed});
  final Color color;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String hint;
  final VoidCallback onTap;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$title. $hint',
      excludeSemantics: true,
      child: SketchyBorder(
        color: color,
        seed: seed,
        radius: 60,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(60),
          child: Container(
            constraints: const BoxConstraints(minHeight: 110),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(children: [
              Icon(icon, size: 56, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(title, textAlign: TextAlign.center, style: t.bodyLarge!.copyWith(fontSize: 26)),
                  Text(hint, textAlign: TextAlign.center, style: t.bodyLarge!.copyWith(fontSize: 23)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
