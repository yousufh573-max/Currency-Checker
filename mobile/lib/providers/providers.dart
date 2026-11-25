import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/strings.dart';
import '../models/analysis_result.dart';
import '../models/app_settings.dart';
import '../models/session.dart';
import '../services/recognition/demo_engine.dart';
import '../services/recognition/on_device_engine.dart';
import '../services/recognition/recognition_engine.dart';
import '../services/recognition/server_engine.dart';
import '../services/storage/session_repository.dart';
import '../services/storage/temp_images.dart';
import '../services/voice/voice_service.dart';

const _uuid = Uuid();

// ------------------------------------------------------------ infrastructure
/// Overridden in main() with real instances; null in tests = memory only.
final sharedPrefsProvider = Provider<SharedPreferences?>((_) => null);
final sessionRepoProvider = Provider<SessionRepository?>((_) => null);
final tempImagesProvider = Provider<TempImageStore?>((_) => null);
final initialSessionProvider = Provider<SessionState?>((_) => null);
final thresholdsProvider = Provider<Thresholds>((_) => const Thresholds());

final voiceProvider = Provider<VoiceIO>((ref) {
  final v = VoiceService();
  ref.onDispose(v.stopAll);
  return v;
});

// ------------------------------------------------------------------ settings
class SettingsController extends Notifier<AppSettings> {
  SharedPreferences? get _prefs => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    final p = _prefs;
    if (p == null) return const AppSettings();
    return AppSettings(
      language: AppLanguage.values.asNameMap()[p.getString('language')] ?? AppLanguage.en,
      speechRate: p.getDouble('speechRate') ?? 0.45,
      mode: EngineMode.values.asNameMap()[p.getString('mode')] ?? EngineMode.onDevice,
      serverUrl: p.getString('serverUrl') ?? '',
      serverConsent: p.getBool('serverConsent') ?? false,
      haptics: p.getBool('haptics') ?? true,
      preferOfflineSpeech: p.getBool('preferOfflineSpeech') ?? false,
      autoCapture: p.getBool('autoCapture') ?? true,
    );
  }

  void update(AppSettings s) {
    state = s;
    final p = _prefs;
    if (p == null) return;
    p
      ..setString('language', s.language.name)
      ..setDouble('speechRate', s.speechRate)
      ..setString('mode', s.mode.name)
      ..setString('serverUrl', s.serverUrl.trim())
      ..setBool('serverConsent', s.serverConsent)
      ..setBool('haptics', s.haptics)
      ..setBool('preferOfflineSpeech', s.preferOfflineSpeech)
      ..setBool('autoCapture', s.autoCapture);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
final stringsProvider = Provider<S>((ref) => S(ref.watch(settingsProvider.select((s) => s.language))));

// -------------------------------------------------------------------- engine
final onDeviceEngineProvider = Provider<OnDeviceRecognitionEngine>((ref) => OnDeviceRecognitionEngine(thresholds: ref.watch(thresholdsProvider)));
final demoEngineProvider = Provider<DemoRecognitionEngine>((ref) => DemoRecognitionEngine(thresholds: ref.watch(thresholdsProvider)));

final engineProvider = Provider<RecognitionEngine>((ref) {
  final s = ref.watch(settingsProvider);
  return switch (s.mode) {
    EngineMode.onDevice => ref.watch(onDeviceEngineProvider),
    EngineMode.demo => ref.watch(demoEngineProvider),
    EngineMode.server => ServerRecognitionEngine(baseUrl: s.serverUrl.trim(), consentGiven: s.serverConsent),
  };
});

// ------------------------------------------------------------------- session
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => ref.read(initialSessionProvider) ?? SessionState(id: _uuid.v4());

  void _persist() {
    final repo = ref.read(sessionRepoProvider);
    if (repo != null) unawaited(repo.save(state).catchError((Object e) => debugPrint('Session save failed: $e')));
  }

  /// Records an analysed capture. Returns true if it was added to the total.
  /// Idempotent per [captureId].
  bool recordResult(String captureId, AnalysisResult r) {
    if (state.containsCapture(captureId)) {
      return state.scans.firstWhere((s) => s.captureId == captureId).accepted;
    }
    final rec = ScanRecord(
      captureId: captureId,
      denomination: r.denomination,
      confidence: r.confidence,
      tornRatio: r.tornRatio,
      condition: r.condition,
      accepted: r.eligible && r.denomination != null,
      reason: r.rejectionReason,
      isDemo: r.isDemo,
      createdAt: DateTime.now(),
    );
    state = state.addScan(rec);
    _persist();
    return rec.accepted;
  }

  ScanRecord? undo() {
    if (state.scans.isEmpty || state.completed) return null;
    final last = state.scans.last;
    state = state.undoLast();
    _persist();
    return last;
  }

  void setRequired(int amount) {
    state = state.withRequired(amount);
    _persist();
  }

  void complete() {
    if (state.completed) return;
    state = state.complete();
    _persist();
  }

  void newSession() {
    if (!state.completed && state.scans.isNotEmpty) {
      state = state.complete(); // keep the previous session in history
      _persist();
    }
    state = SessionState(id: _uuid.v4());
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

// ----------------------------------------------------------------- scan flow
class ScanFlow {
  const ScanFlow({this.captureId, this.image, this.result, this.added = false, this.stages = const {}, this.running = false, this.errorCode});
  final String? captureId;
  final File? image;
  final AnalysisResult? result;
  final bool added;
  final Map<StageName, StageUpdate> stages;
  final bool running;
  final String? errorCode;

  ScanFlow copyWith({AnalysisResult? result, bool? added, Map<StageName, StageUpdate>? stages, bool? running, String? errorCode, bool clearError = false}) =>
      ScanFlow(
        captureId: captureId,
        image: image,
        result: result ?? this.result,
        added: added ?? this.added,
        stages: stages ?? this.stages,
        running: running ?? this.running,
        errorCode: clearError ? null : (errorCode ?? this.errorCode),
      );
}

class ScanFlowController extends Notifier<ScanFlow> {
  @override
  ScanFlow build() => const ScanFlow();

  /// Registers a new capture (deleting the previous temporary image).
  Future<void> setCapture(File image) async {
    await ref.read(tempImagesProvider)?.delete(state.image);
    state = ScanFlow(captureId: _uuid.v4(), image: image);
  }

  Future<void> discardImage() async {
    await ref.read(tempImagesProvider)?.delete(state.image);
  }

  Future<void> analyze() async {
    final image = state.image, captureId = state.captureId;
    if (image == null || captureId == null || state.running) return;
    final engine = ref.read(engineProvider);
    state = ScanFlow(
      captureId: captureId,
      image: image,
      running: true,
      stages: {for (final s in StageName.values) s: StageUpdate(s, StageStatus.pending)},
    );
    try {
      final result = await engine
          .analyze(image, onStage: (u) {
            if (!ref.mounted) return;
            state = state.copyWith(stages: {...state.stages, u.stage: u});
          })
          .timeout(analysisTimeout * 2, onTimeout: () {
            engine.cancel();
            throw const EngineException('timeout');
          });
      if (!ref.mounted) return;
      if (result.error == 'model_not_installed' || !result.success) {
        state = state.copyWith(result: result, running: false, added: false);
        return;
      }
      final added = ref.read(sessionProvider.notifier).recordResult(captureId, result);
      state = state.copyWith(result: result, running: false, added: added);
    } on EngineException catch (e) {
      if (ref.mounted) state = state.copyWith(running: false, errorCode: e.code);
    } catch (e) {
      debugPrint('Analysis failed: $e');
      if (ref.mounted) state = state.copyWith(running: false, errorCode: 'unknown');
    }
  }
}

final scanFlowProvider = NotifierProvider<ScanFlowController, ScanFlow>(ScanFlowController.new);
