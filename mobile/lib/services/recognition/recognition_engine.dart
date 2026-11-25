import 'dart:io';

import '../../models/analysis_result.dart';

enum EngineMode { onDevice, server, demo }

class EngineStatus {
  const EngineStatus({required this.ready, required this.message, this.modelVersion, this.isDemo = false});
  final bool ready;
  final String message;
  final String? modelVersion;
  final bool isDemo;
}

/// Thrown for recoverable engine errors; [code] maps to S.errorMessage.
class EngineException implements Exception {
  const EngineException(this.code, [this.detail = '']);
  final String code;
  final String detail;
  @override
  String toString() => 'EngineException($code, $detail)';
}

typedef StageCallback = void Function(StageUpdate update);

/// Analyses one captured note image. Implementations must report each stage
/// via [onStage] only when that stage has actually completed.
abstract class RecognitionEngine {
  EngineMode get mode;
  Future<EngineStatus> status();
  Future<AnalysisResult> analyze(File image, {required StageCallback onStage});
  void cancel() {}
}
