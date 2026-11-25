import 'dart:io';

import 'package:banknote_assistant/core/app_config.dart';
import 'package:banknote_assistant/models/analysis_result.dart';
import 'package:banknote_assistant/services/recognition/recognition_engine.dart';
import 'package:banknote_assistant/services/voice/voice_service.dart';
import 'package:flutter/foundation.dart';

/// Records speech and lets tests "say" phrases to the active listener.
class FakeVoice implements VoiceIO {
  final spoken = <String>[];
  void Function(String)? _handler;
  Object? _owner;

  @override
  final ValueNotifier<bool> listening = ValueNotifier(false);
  @override
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  @override
  final ValueNotifier<double> soundLevel = ValueNotifier(0);
  @override
  final ValueNotifier<bool> micAvailable = ValueNotifier(true);

  @override
  Future<bool> init() async => true;
  @override
  void configure({required String ttsLocale, required String sttLocale, required double rate, bool preferOffline = false}) {}
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Object listen(void Function(String words) onFinal) {
    _handler = onFinal;
    listening.value = true;
    return _owner = Object();
  }

  @override
  Future<void> stopListening([Object? owner]) async {
    if (owner != null && !identical(owner, _owner)) return;
    _handler = null;
    listening.value = false;
  }

  @override
  Future<void> stopAll() async => stopListening();
  @override
  void setPaused(bool paused) {}

  /// Simulates the user saying [words].
  void hear(String words) => _handler?.call(words);
  bool get isListening => _handler != null;
  String get last => spoken.isEmpty ? '' : spoken.last;
}

/// Test double engine returning queued results and reporting real stage order.
class FakeEngine extends RecognitionEngine {
  final queue = <AnalysisResult>[];
  Object? throwNext;

  @override
  EngineMode get mode => EngineMode.onDevice;
  @override
  Future<EngineStatus> status() async => const EngineStatus(ready: true, message: 'fake');

  @override
  Future<AnalysisResult> analyze(File image, {required StageCallback onStage}) async {
    if (throwNext != null) {
      final e = throwNext!;
      throwNext = null;
      throw e;
    }
    for (final s in StageName.values) {
      onStage(StageUpdate(s, StageStatus.running));
      onStage(StageUpdate(s, StageStatus.passed));
    }
    return queue.removeAt(0);
  }
}

AnalysisResult note(int d, {double conf = 0.98, double torn = 2}) {
  const t = Thresholds();
  final cond = classifyCondition(torn, true, t);
  final (ok, reason) = decideEligibility(denomination: d, confidence: conf, condition: cond, qualityOk: true, flags: const [], t: t);
  return AnalysisResult(success: true, denomination: d, confidence: conf, tornRatio: torn, tornRatioReliable: true, condition: cond, eligible: ok, rejectionReason: reason);
}
