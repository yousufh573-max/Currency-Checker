import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../providers/providers.dart';
import '../services/voice/amount_parser.dart';
import '../services/voice/command_parser.dart';
import '../widgets/common.dart';
import '../widgets/mic_button.dart';
import '../widgets/ui_kit.dart';
import '../widgets/waveform.dart';
import 'voice_screen.dart';

/// Screen 6 — Payment amount calculation (PDF page 6).
/// Fixes the PDF's duplicate label: the second card is "Required Payment Amount".
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> with VoiceScreen {
  String? _resultText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = ref.read(sessionProvider).payment;
      if (p != null) _resultText = s.paymentText(p);
      sayThenListen('${s.totalSpeech(ref.read(sessionProvider).total)} ${s.howMuchSpeech}');
    });
  }

  void _apply(int amount) {
    ref.read(sessionProvider.notifier).setRequired(amount);
    final p = ref.read(sessionProvider).payment!;
    haptic(p.sufficient ? HapticKind.success : HapticKind.warning);
    setState(() => _resultText = s.paymentText(p));
    say(s.paymentSpeech(p));
  }

  void _toSummary() {
    if (ref.read(sessionProvider).requiredAmount == null) {
      say(s.amountFirst);
      return;
    }
    haptic(HapticKind.tap);
    ref.read(sessionProvider.notifier).complete();
    context.go('/summary');
  }

  void _scanMore() {
    haptic(HapticKind.tap);
    context.go('/scan');
  }

  @override
  void onVoice(String words) {
    final amount = parseAmount(words);
    if (amount != null) {
      _apply(amount);
      return;
    }
    switch (parseCommand(words)) {
      case VoiceCommand.finish || VoiceCommand.confirm || VoiceCommand.stop:
        _toSummary();
      case VoiceCommand.scanMore || VoiceCommand.scan || VoiceCommand.scanNext:
        _scanMore();
      case VoiceCommand.total:
        say(s.totalSpeech(ref.read(sessionProvider).total));
      case VoiceCommand.undo:
        final removed = ref.read(sessionProvider.notifier).undo();
        say(s.undoSpeech(removed, ref.read(sessionProvider).total));
      case VoiceCommand.repeat:
        final p = ref.read(sessionProvider).payment;
        say(p != null ? s.paymentSpeech(p) : s.howMuchSpeech);
      case VoiceCommand.exit:
        context.go('/');
      default:
        say(s.amountNotUnderstood);
    }
  }

  Future<void> _manualEntry() async {
    stopListening();
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(strings: ref.read(stringsProvider), initial: ref.read(sessionProvider).requiredAmount),
    );
    if (!mounted) return;
    startListening();
    if (value != null) _apply(value);
  }

  @override
  Widget build(BuildContext context) {
    final str = ref.watch(stringsProvider);
    final session = ref.watch(sessionProvider);
    final t = Theme.of(context).textTheme;
    final p = session.payment;
    final resultColor = p == null ? AppColors.brightBlue : (p.sufficient ? AppColors.brightBlue : AppColors.warningRed);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: w * 0.05, vertical: 16),
              child: Column(children: [
                SpeakerBanner(text: str.howMuch, color: AppColors.successBorder, onTap: () => say(str.howMuchSpeech)),
                const SizedBox(height: 18),
                MicButton(listening: voice.listening, size: w * 0.26, label: str.listening, onPressed: () {
                  haptic(HapticKind.tap);
                  startListening();
                }),
                const SizedBox(height: 12),
                ValueListenableBuilder<bool>(
                  valueListenable: voice.listening,
                  builder: (_, listening, _) => Column(children: [
                    Waveform(level: voice.soundLevel, active: listening, bars: 18, width: w * 0.36, height: 56, style: WaveStyle.sparse),
                    Semantics(liveRegion: true, child: Text(listening ? str.listening : str.notListening, style: t.headlineMedium!.copyWith(fontSize: w * 0.075))),
                  ]),
                ),
                Text(str.exampleAmount, style: t.headlineMedium!.copyWith(fontSize: w * 0.06)),
                const SizedBox(height: 14),
                _AmountCard(label: str.totalScannedAmount, amount: session.total, seed: 3, width: w),
                const SizedBox(height: 10),
                Semantics(
                  button: true,
                  hint: str.enterAmount,
                  child: GestureDetector(
                    onTap: _manualEntry,
                    child: _AmountCard(label: str.requiredPaymentAmount, amount: session.requiredAmount, placeholder: str.notSetYet, seed: 7, width: w),
                  ),
                ),
                // Visual comparison: what you have vs what you need.
                if (p != null && p.required > 0) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: Text('${str.youHave} ${taka(p.total)}', style: t.bodyMedium)),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${str.youNeed} ${taka(p.required)}', textAlign: TextAlign.end, style: t.bodyMedium)),
                      ]),
                      const SizedBox(height: 4),
                      MeterBar(
                        value: p.total / p.required,
                        color: p.sufficient ? AppColors.successGreen : AppColors.warningRed,
                        height: 14,
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 12),
                if (_resultText != null)
                  SpeakerBanner(text: _resultText!, color: resultColor, onTap: () => p != null ? say(str.paymentSpeech(p)) : null),
                const SizedBox(height: 14),
                SketchyBorder(
                  color: AppColors.brightBlue,
                  seed: 11,
                  child: Semantics(
                    button: true,
                    label: str.scanMoreNotes,
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: _scanMore,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 72),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.document_scanner_outlined, size: 34),
                          const SizedBox(width: 10),
                          Flexible(child: Text(str.scanMoreNotes, style: t.bodyLarge)),
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: BigActionButton(label: str.typeAmount, icon: Icons.dialpad_rounded, onPressed: _manualEntry, hint: str.enterAmount)),
                  const SizedBox(width: 10),
                  Expanded(child: BigActionButton(label: str.seeSummary, icon: Icons.summarize_outlined, onPressed: _toSummary, color: AppColors.successGreen)),
                ]),
              ]),
            );
          }),
        ),
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.label, required this.amount, required this.seed, required this.width, this.placeholder});
  final String label;
  final int? amount;
  final String? placeholder;
  final int seed;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: ${amount == null ? (placeholder ?? '') : '$amount Taka'}',
      excludeSemantics: true,
      child: SketchyBorder(
        color: AppColors.steel,
        seed: seed,
        radius: 60,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(children: [
            Text(label, textAlign: TextAlign.center, style: t.bodyLarge!.copyWith(fontSize: width * 0.07)),
            if (amount != null) TakaAmount(amount!, size: width * 0.13) else Text(placeholder ?? '', style: t.bodyLarge),
          ]),
        ),
      ),
    );
  }
}

/// Owns its TextEditingController so it is disposed only after the dialog's
/// closing animation has finished.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.strings, this.initial});
  final S strings;
  final int? initial;
  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _ctrl = TextEditingController(text: widget.initial?.toString() ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final str = widget.strings;
    return AlertDialog(
      title: Text(str.enterAmount),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
        style: const TextStyle(fontSize: 28),
        decoration: InputDecoration(prefixText: '৳ ', labelText: str.enterAmount),
        onSubmitted: (v) => Navigator.pop(context, int.tryParse(v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(str.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(_ctrl.text)), child: Text(str.ok)),
      ],
    );
  }
}
