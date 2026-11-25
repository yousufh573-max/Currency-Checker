import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../models/app_settings.dart';
import '../models/session.dart';
import '../providers/providers.dart';
import '../services/recognition/recognition_engine.dart';
import '../services/recognition/server_engine.dart';
import '../widgets/ui_kit.dart';

final engineStatusProvider = FutureProvider.autoDispose<EngineStatus>((ref) => ref.watch(engineProvider).status());
final historyProvider = FutureProvider.autoDispose<List<SessionState>>((ref) async => await ref.watch(sessionRepoProvider)?.history() ?? const []);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final _url = TextEditingController(text: ref.read(settingsProvider).serverUrl);
  String? _urlError;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _update(AppSettings Function(AppSettings) f) => ref.read(settingsProvider.notifier).update(f(ref.read(settingsProvider)));

  Future<void> _selectMode(EngineMode m) async {
    if (m == EngineMode.server && !ref.read(settingsProvider).serverConsent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Send photos to a server?'),
          content: const SingleChildScrollView(
            child: Text(
              'In server mode, each banknote photo you capture is uploaded to the server address you enter here '
              'for analysis. The server analyses the image in memory and keeps only the result '
              '(denomination, confidence, torn ratio) — not the photo. Do not use servers you do not trust. '
              'You can withdraw consent at any time by switching back to on-device mode.',
              style: TextStyle(fontSize: 18),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Do not allow')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('I agree')),
          ],
        ),
      );
      if (ok != true) return;
      _update((s) => s.copyWith(mode: m, serverConsent: true));
      return;
    }
    if (m == EngineMode.demo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable developer demo mode?'),
          content: const Text(
            'Demo mode returns a fixed, scripted sequence of results (20, 100, then a torn 500 Taka). '
            'It does NOT look at your notes and must never be used to count real money.',
            style: TextStyle(fontSize: 18),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enable demo')),
          ],
        ),
      );
      if (ok != true) return;
    }
    _update((s) => s.copyWith(mode: m, serverConsent: m == EngineMode.server ? s.serverConsent : false));
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(settingsProvider);
    final str = ref.watch(stringsProvider);
    final status = ref.watch(engineStatusProvider);
    final history = ref.watch(historyProvider);
    final t = Theme.of(context).textTheme;
    const tileText = TextStyle(fontSize: 20);

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: Text(str.settings, style: t.titleLarge),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          // Recognition status first: the most important thing to know.
          Semantics(
            liveRegion: true,
            child: status.when(
              data: (e) {
                final color = e.ready ? (e.isDemo ? AppColors.amber : AppColors.successGreen) : AppColors.warningRed;
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(e.ready ? Icons.check_circle : Icons.error_outline, color: color, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.ready ? 'Recognition ready${e.modelVersion != null ? ' (model ${e.modelVersion})' : ''}' : 'Recognition NOT available',
                            style: t.bodyLarge!.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(e.message, style: t.bodyMedium),
                      ]),
                    ),
                  ]),
                );
              },
              loading: () => const Padding(padding: EdgeInsets.all(16), child: Text('Checking recognition engine…')),
              error: (e, _) => Text('Status check failed: $e'),
            ),
          ),
          SectionCard(title: 'Voice  ·  কণ্ঠ', icon: Icons.record_voice_over_outlined, children: [
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AppLanguage>(
                segments: const [
                  ButtonSegment(value: AppLanguage.en, label: Text('English', style: tileText)),
                  ButtonSegment(value: AppLanguage.bn, label: Text('বাংলা', style: tileText)),
                ],
                selected: {st.language},
                onSelectionChanged: (v) => _update((s) => s.copyWith(language: v.first)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Speech rate: ${(st.speechRate * 200).round()}%', style: tileText),
            Slider(
              value: st.speechRate,
              min: 0.2,
              max: 0.8,
              divisions: 12,
              label: '${(st.speechRate * 200).round()}%',
              semanticFormatterCallback: (v) => 'Speech rate ${(v * 200).round()} percent',
              onChanged: (v) => _update((s) => s.copyWith(speechRate: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Prefer offline speech recognition', style: tileText),
              subtitle: const Text('Uses the on-device recogniser when your phone supports it.'),
              value: st.preferOfflineSpeech,
              onChanged: (v) => _update((s) => s.copyWith(preferOfflineSpeech: v)),
            ),
          ]),
          SectionCard(title: 'Scanning', icon: Icons.document_scanner_outlined, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatic capture', style: tileText),
              subtitle: const Text('Capture automatically when the note is steady inside the frame.'),
              value: st.autoCapture,
              onChanged: (v) => _update((s) => s.copyWith(autoCapture: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibration feedback', style: tileText),
              value: st.haptics,
              onChanged: (v) => _update((s) => s.copyWith(haptics: v)),
            ),
          ]),
          SectionCard(title: 'Recognition', icon: Icons.memory_rounded, children: [
            RadioGroup<EngineMode>(
              groupValue: st.mode,
              onChanged: (m) => m == null ? null : _selectMode(m),
              child: const Column(children: [
                RadioListTile(
                    contentPadding: EdgeInsets.zero,
                    value: EngineMode.onDevice,
                    title: Text('On this phone (offline)', style: tileText),
                    subtitle: Text('Photos never leave the device.')),
                RadioListTile(
                    contentPadding: EdgeInsets.zero,
                    value: EngineMode.server,
                    title: Text('Server', style: tileText),
                    subtitle: Text('Uploads photos to your FastAPI server (requires consent).')),
                RadioListTile(
                    contentPadding: EdgeInsets.zero,
                    value: EngineMode.demo,
                    title: Text('Developer demo (NOT real recognition)', style: TextStyle(fontSize: 20, color: AppColors.amber))),
              ]),
            ),
            if (st.mode == EngineMode.server) ...[
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: 'Server URL (https://…)', errorText: _urlError),
                onSubmitted: (v) {
                  final err = validateServerUrl(v);
                  setState(() => _urlError = err == null ? null : (err == 'https_required' ? 'HTTPS is required' : 'Invalid URL'));
                  if (err == null) _update((s) => s.copyWith(serverUrl: v.trim()));
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Consent to upload photos for analysis', style: TextStyle(fontSize: 18)),
                value: st.serverConsent,
                onChanged: (v) => _update((s) => s.copyWith(serverConsent: v)),
              ),
            ],
          ]),
          SectionCard(title: 'Saved sessions', icon: Icons.history_rounded, children: [
            history.when(
              data: (list) => list.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No completed sessions yet.'))
                  : Column(children: [
                      for (final h in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${str.totalScannedLine(h.total)}${h.hasDemoScans ? '  [DEMO]' : ''}'),
                          subtitle: Text('${str.neededLine(h.requiredAmount)} · ${str.remainingLine(h.payment)}'),
                          trailing: IconButton(
                            tooltip: 'Delete session',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await ref.read(sessionRepoProvider)?.delete(h.id);
                              ref.invalidate(historyProvider);
                            },
                          ),
                        ),
                    ]),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Banknote Assistant counts cash only. It does not detect counterfeit notes, verify authenticity, '
              'or process payments. Torn-ratio thresholds (Good ≤5%, Damaged ≤20%, Too torn >20%) are app settings, '
              'not Bangladesh Bank rules.',
              style: t.bodyMedium!.copyWith(color: AppColors.glassBorder),
            ),
          ),
        ]),
      ),
    );
  }
}
