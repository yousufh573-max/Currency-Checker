import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../models/analysis_result.dart';
import '../providers/providers.dart';
import '../services/voice/command_parser.dart';
import '../widgets/common.dart';
import '../widgets/glass_panel.dart';
import '../widgets/painters.dart';
import '../widgets/ui_kit.dart';
import '../widgets/waveform.dart';
import 'scanner_screen.dart';
import 'voice_screen.dart';

/// Screen 3 — Banknote analysis (PDF page 3). Each check mark appears only
/// when the engine reports that stage as actually completed.
class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});
  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> with VoiceScreen, SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    say(s.analyzingSpeech);
    await ref.read(scanFlowProvider.notifier).analyze();
    if (!mounted) return;
    final flow = ref.read(scanFlowProvider);
    if (flow.errorCode != null) {
      haptic(HapticKind.warning);
      await sayThenListen(s.errorMessage(flow.errorCode!));
    } else if (flow.result != null) {
      context.go('/result');
    }
  }

  void _retry() {
    haptic(HapticKind.tap);
    stopListening();
    _run();
  }

  void _rescan() {
    haptic(HapticKind.tap);
    ref.read(captureGateProvider).rearm();
    ref.read(scanFlowProvider.notifier).discardImage();
    context.go('/scan');
  }

  @override
  void onVoice(String words) {
    switch (parseCommand(words)) {
      case VoiceCommand.repeat:
        final code = ref.read(scanFlowProvider).errorCode;
        if (code != null) say(s.errorMessage(code));
      case VoiceCommand.confirm || VoiceCommand.start:
        _retry();
      case VoiceCommand.scan || VoiceCommand.scanNext || VoiceCommand.scanAgain:
        _rescan();
      case VoiceCommand.finish || VoiceCommand.stop:
        context.go('/payment');
      default:
        if (normalizeSpeech(words).contains('retry') || words.contains('আবার চেষ্টা')) _retry();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(stringsProvider);
    final flow = ref.watch(scanFlowProvider);
    final t = Theme.of(context).textTheme;
    final done = flow.stages.values.where((u) => u.status != StageStatus.pending && u.status != StageStatus.running).length;
    final progress = flow.stages.isEmpty ? 0.0 : done / StageName.values.length;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: w * 0.1, vertical: 28),
            child: Column(children: [
              Semantics(header: true, child: Text(str.analyzing, style: t.headlineMedium!.copyWith(fontSize: w * 0.085))),
              const SizedBox(height: 18),
              Semantics(
                label: '${str.analyzing} ${(progress * 100).round()}%',
                excludeSemantics: true,
                child: SizedBox(
                  width: w * 0.38,
                  height: w * 0.38,
                  child: CustomPaint(
                    painter: SegmentedRingPainter(progress: progress, pulse: _pulse),
                    child: Center(child: Icon(Icons.psychology_outlined, size: w * 0.17, color: AppColors.white)),
                  ),
                ),
              ),
              SizedBox(height: w * 0.1),
              for (final stage in StageName.values) _StageRow(update: flow.stages[stage] ?? StageUpdate(stage, StageStatus.pending), label: str.stage(stage), statusText: str.stageStatus),
              SizedBox(height: w * 0.08),
              if (flow.errorCode == null)
                GlassPanel(
                  radius: 50,
                  child: Column(children: [
                    Waveform(level: voice.soundLevel, width: w * 0.55, height: 70),
                    Semantics(liveRegion: true, child: Text(str.pleaseWait, style: t.headlineMedium!.copyWith(fontSize: w * 0.085))),
                  ]),
                )
              else ...[
                SpeakerBanner(text: str.errorMessage(flow.errorCode!), color: AppColors.warningRed, onTap: () => say(str.errorMessage(flow.errorCode!))),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: BigActionButton(label: str.retry, icon: Icons.refresh_rounded, onPressed: _retry, color: AppColors.micBlue)),
                  const SizedBox(width: 12),
                  Expanded(child: BigActionButton(label: str.rescan, icon: Icons.camera_alt_rounded, onPressed: _rescan, color: AppColors.scanYellow)),
                ]),
              ],
            ]),
          );
        }),
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.update, required this.label, required this.statusText});
  final StageUpdate update;
  final String label;
  final String Function(StageStatus) statusText;

  @override
  Widget build(BuildContext context) {
    final icon = switch (update.status) {
      StageStatus.passed => const _Badge(color: AppColors.successGreen, icon: Icons.check_rounded),
      StageStatus.warning => const _Badge(color: AppColors.amber, icon: Icons.priority_high_rounded),
      StageStatus.failed => const _Badge(color: AppColors.warningRed, icon: Icons.close_rounded),
      StageStatus.skipped => const _Badge(color: AppColors.neutralGrey, icon: Icons.remove_rounded),
      StageStatus.running => const SizedBox(width: 44, height: 44, child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.cyan))),
      StageStatus.pending => Container(
          width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.neutralGrey, width: 2))),
    };
    final t = Theme.of(context).textTheme;
    // Real output of the stage (e.g. "acceptable", "2.0%", "20 BDT"), shown once it finished.
    final finished = update.status != StageStatus.pending && update.status != StageStatus.running;
    final detail = finished ? update.detail.replaceAll('_', ' ') : '';
    final active = update.status != StageStatus.pending;
    return Semantics(
      label: '$label: ${statusText(update.status)}${detail.isEmpty ? '' : ', $detail'}',
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: active ? 1 : 0.55,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            icon,
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: t.bodyLarge!.copyWith(fontSize: 24)),
                if (detail.isNotEmpty) Text(detail, style: t.bodyMedium!.copyWith(color: const Color(0xFFB8C8D8))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.icon});
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color.lerp(color, Colors.white, 0.25)!, color]),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, color: Colors.white, size: 30),
      );
}
