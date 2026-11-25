import 'dart:io';

import '../../core/app_config.dart';
import '../../models/analysis_result.dart';
import 'recognition_engine.dart';

/// DEVELOPMENT DEMO ENGINE — NOT REAL RECOGNITION.
///
/// Returns a scripted sequence (20 good, 100 good, 500 too torn) so the UI
/// and calculation flow can be exercised before a trained model exists.
/// Every result is flagged `isDemo`, the UI shows a persistent DEMO banner,
/// and the spoken result starts with "Demo mode, not real recognition".
class DemoRecognitionEngine extends RecognitionEngine {
  DemoRecognitionEngine({this.thresholds = const Thresholds(), this.stageDelay = const Duration(milliseconds: 350)});

  final Thresholds thresholds;
  final Duration stageDelay;
  int _i = 0;
  static const _script = [(20, 0.986, 2.0), (100, 0.972, 3.5), (500, 0.916, 40.0)];

  @override
  EngineMode get mode => EngineMode.demo;

  @override
  Future<EngineStatus> status() async =>
      const EngineStatus(ready: true, message: 'DEMO MODE: scripted results, not real recognition.', modelVersion: 'demo', isDemo: true);

  @override
  Future<AnalysisResult> analyze(File image, {required StageCallback onStage}) async {
    final (denom, conf, torn) = _script[_i++ % _script.length];
    for (final s in StageName.values) {
      onStage(StageUpdate(s, StageStatus.running));
      await Future<void>.delayed(stageDelay);
      onStage(StageUpdate(s, StageStatus.passed, 'DEMO'));
    }
    final condition = classifyCondition(torn, true, thresholds);
    final (eligible, reason) = decideEligibility(
        denomination: denom, confidence: conf, condition: condition, qualityOk: true, flags: const [], t: thresholds);
    return AnalysisResult(
      success: true,
      denomination: denom,
      confidence: conf,
      tornRatio: torn,
      tornRatioReliable: true,
      condition: condition,
      eligible: eligible,
      rejectionReason: reason,
      modelVersion: 'demo',
      isDemo: true,
      engine: 'demo',
    );
  }
}
