import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../providers/providers.dart';
import '../services/voice/command_parser.dart';
import '../widgets/common.dart';
import '../widgets/glass_panel.dart';
import '../widgets/ui_kit.dart';
import 'scanner_screen.dart';
import 'voice_screen.dart';

/// Screens 4 & 5 — Recognised note (green, added) or rejected note
/// (red, not added) — PDF pages 4 and 5. The banner text, the spoken message
/// and the total all come from the same session state, so they always agree.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});
  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> with VoiceScreen {
  late String _speech;

  @override
  void initState() {
    super.initState();
    final flow = ref.read(scanFlowProvider);
    _speech = flow.result == null ? '' : s.resultSpeech(flow.result!, added: flow.added, total: ref.read(sessionProvider).total);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      haptic(flow.added ? HapticKind.success : HapticKind.warning);
      sayThenListen('$_speech ${s.resultHelp}');
    });
  }

  void _scanNext() {
    haptic(HapticKind.tap);
    final flow = ref.read(scanFlowProvider);
    // Rescanning a rejected note: allow immediate capture of the same note.
    if (!flow.added) ref.read(captureGateProvider).rearm();
    ref.read(scanFlowProvider.notifier).discardImage();
    context.go('/scan');
  }

  void _undo() {
    haptic(HapticKind.tap);
    final removed = ref.read(sessionProvider.notifier).undo();
    final total = ref.read(sessionProvider).total;
    setState(() => _speech = s.undoSpeech(removed, total));
    say(_speech);
  }

  void _finish() {
    haptic(HapticKind.tap);
    ref.read(scanFlowProvider.notifier).discardImage();
    context.go('/payment');
  }

  @override
  void onVoice(String words) {
    switch (parseCommand(words)) {
      case VoiceCommand.scan || VoiceCommand.scanNext || VoiceCommand.scanMore || VoiceCommand.start || VoiceCommand.scanAgain:
        _scanNext();
      case VoiceCommand.undo:
        _undo();
      case VoiceCommand.total:
        say(s.totalSpeech(ref.read(sessionProvider).total));
      case VoiceCommand.finish || VoiceCommand.stop:
        _finish();
      case VoiceCommand.repeat:
        say(_speech);
      case VoiceCommand.exit:
        context.go('/');
      default:
        break;
    }
  }


  @override
  Widget build(BuildContext context) {
    final str = ref.watch(stringsProvider);
    final flow = ref.watch(scanFlowProvider);
    final total = ref.watch(sessionProvider.select((x) => x.total));
    final th = ref.watch(thresholdsProvider);
    final r = flow.result;
    final t = Theme.of(context).textTheme;
    if (r == null) return const Scaffold();

    // Derived from the session (not the flow flag) so Undo is reflected immediately.
    final added = ref.watch(sessionProvider.select((x) => x.scans.any((sc) => sc.captureId == flow.captureId && sc.accepted)));
    final accent = added ? AppColors.successBorder : AppColors.warningRed;
    final denomText = r.denomination != null ? str.takaWord(r.denomination!) : str.notRecognized;
    final torn = r.tornRatioReliable || r.isDemo ? r.tornRatio : null;
    final conf = r.confidence;
    final confColor = conf == null ? AppColors.neutralGrey : (conf >= th.minConfidence ? AppColors.successGreen : AppColors.amber);
    final tornColor = torn == null
        ? AppColors.neutralGrey
        : torn <= th.tornGoodMax
            ? AppColors.successGreen
            : torn <= th.tornDamagedMax
                ? AppColors.amber
                : AppColors.warningRed;
    const tornScale = 50.0; // meter spans 0–50 % missing area

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return Column(children: [
              if (r.isDemo) DemoBanner(text: str.demoBanner),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(w * 0.05, 14, w * 0.05, 8),
                  child: Column(children: [
                    SpeakerBanner(text: _speech, color: accent, onTap: () => say(_speech)),
                    const SizedBox(height: 12),
                    // Captured photo with a status badge (temporary file, deleted on next scan).
                    if (flow.image != null)
                      Semantics(
                        image: true,
                        label: 'Photo of the scanned note',
                        child: Stack(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.file(
                              flow.image!,
                              height: w * 0.42,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              cacheWidth: 800,
                              errorBuilder: (_, _, _) => Container(
                                height: w * 0.3,
                                width: double.infinity,
                                color: const Color(0x14FFFFFF),
                                child: const Icon(Icons.payments_outlined, size: 56, color: AppColors.glassBorder),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                              child: Icon(added ? Icons.check_rounded : Icons.close_rounded, color: Colors.white, size: 26),
                            ),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 12),
                    OutlinedCard(
                      color: accent,
                      child: Semantics(
                        container: true,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(denomText, style: t.displayMedium!.copyWith(fontSize: w * 0.1)),
                          if (conf != null) ...[
                            Text(str.confidence(conf), style: t.bodyLarge!.copyWith(fontSize: 22)),
                            const SizedBox(height: 4),
                            MeterBar(value: conf, color: confColor, marker: th.minConfidence),
                            const SizedBox(height: 6),
                          ],
                        ]),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedCard(
                      color: accent,
                      child: Semantics(
                        container: true,
                        child: Column(children: [
                          Row(children: [
                            Icon(added ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                                size: 52, color: added ? AppColors.successGreen : AppColors.warningRed),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(children: [
                                Text(str.conditionLine(r.condition), style: t.bodyLarge!.copyWith(fontSize: 24), textAlign: TextAlign.center),
                                Text(str.tornLine(torn), style: t.bodyLarge!.copyWith(fontSize: 22), textAlign: TextAlign.center),
                              ]),
                            ),
                          ]),
                          if (torn != null) ...[
                            const SizedBox(height: 8),
                            MeterBar(value: torn / tornScale, color: tornColor, marker: th.tornDamagedMax / tornScale),
                            const SizedBox(height: 4),
                          ],
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Status pill: icon + text so meaning is not conveyed by colour alone.
                    Semantics(
                      liveRegion: true,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 68),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: added ? AppColors.successGreen : AppColors.neutralGrey,
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: added ? [BoxShadow(color: AppColors.successGreen.withValues(alpha: 0.35), blurRadius: 16)] : null,
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(added ? Icons.add_circle_outline : Icons.block, color: Colors.white, size: 28),
                          const SizedBox(width: 10),
                          Flexible(
                              child: Text(added ? str.addedToTotal : str.notAddedToTotal,
                                  textAlign: TextAlign.center, style: t.bodyLarge!.copyWith(fontSize: 26))),
                        ]),
                      ),
                    ),
                    if (!added && r.rejectionReason != null) ...[
                      const SizedBox(height: 8),
                      Text(str.reason(r.rejectionReason), textAlign: TextAlign.center, style: t.bodyMedium),
                    ],
                  ]),
                ),
              ),
              // Pinned footer: actions + running total are always on screen.
              Container(
                padding: EdgeInsets.fromLTRB(w * 0.05, 10, w * 0.05, 10),
                decoration: const BoxDecoration(
                  color: Color(0xF2091A33),
                  border: Border(top: BorderSide(color: Color(0x33B8C8D8))),
                ),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: BigActionButton(
                            label: added ? str.scanNext : str.rescan, icon: Icons.document_scanner_outlined, onPressed: _scanNext, color: AppColors.micBlue)),
                    const SizedBox(width: 8),
                    Expanded(child: BigActionButton(label: str.undo, icon: Icons.undo_rounded, onPressed: _undo)),
                    const SizedBox(width: 8),
                    Expanded(child: BigActionButton(label: str.finish, icon: Icons.check_rounded, onPressed: _finish, color: AppColors.successGreen)),
                  ]),
                  const SizedBox(height: 10),
                  Semantics(
                    button: true,
                    label: '${str.currentTotal}: ${str.takaWord(total)}',
                    hint: str.hearTotal,
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => say(str.totalSpeech(total)),
                      child: GlassPanel(
                        radius: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(children: [
                          const Icon(Icons.volume_up_rounded, size: 36, color: Color(0xFFB0BCC8)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(str.currentTotal, style: t.headlineMedium!.copyWith(fontSize: w * 0.065))),
                          TakaAmount(total, size: w * 0.11),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}
