import '../core/app_config.dart';

enum NoteCondition { good, damaged, tooTorn, uncertain }

enum StageName { imageQuality, tornDetection, tornRatio, currencyRecognition }

enum StageStatus { pending, running, passed, warning, failed, skipped }

class StageUpdate {
  const StageUpdate(this.stage, this.status, [this.detail = '']);
  final StageName stage;
  final StageStatus status;
  final String detail;
}

NoteCondition conditionFromString(String s) => switch (s) {
      'good' => NoteCondition.good,
      'damaged' => NoteCondition.damaged,
      'too_torn' => NoteCondition.tooTorn,
      _ => NoteCondition.uncertain,
    };

StageName? stageFromString(String s) => switch (s) {
      'image_quality' => StageName.imageQuality,
      'torn_detection' => StageName.tornDetection,
      'torn_ratio' => StageName.tornRatio,
      'currency_recognition' => StageName.currencyRecognition,
      _ => null,
    };

StageStatus stageStatusFromString(String s) => switch (s) {
      'passed' => StageStatus.passed,
      'warning' => StageStatus.warning,
      'failed' => StageStatus.failed,
      _ => StageStatus.skipped,
    };

/// Result of analysing one captured note (from any engine).
class AnalysisResult {
  const AnalysisResult({
    required this.success,
    this.denomination,
    this.confidence,
    this.tornRatio,
    this.tornRatioReliable = false,
    this.condition = NoteCondition.uncertain,
    this.imageQuality = 'acceptable',
    this.flags = const [],
    this.eligible = false,
    this.rejectionReason,
    this.processingTimeMs = 0,
    this.modelVersion,
    this.isDemo = false,
    this.error,
    this.engine = '',
  });

  final bool success;
  final int? denomination;
  final double? confidence;
  final double? tornRatio;
  final bool tornRatioReliable;
  final NoteCondition condition;
  final String imageQuality;
  final List<String> flags;
  final bool eligible;
  final String? rejectionReason;
  final int processingTimeMs;
  final String? modelVersion;
  final bool isDemo;
  final String? error;
  final String engine;

  factory AnalysisResult.failure(String error, {String engine = '', String? reason}) =>
      AnalysisResult(success: false, error: error, rejectionReason: reason ?? error, engine: engine);

  factory AnalysisResult.fromJson(Map<String, dynamic> j, {String engine = 'server'}) => AnalysisResult(
        success: j['success'] == true,
        denomination: (j['denomination'] as num?)?.toInt(),
        confidence: (j['confidence'] as num?)?.toDouble(),
        tornRatio: (j['torn_ratio'] as num?)?.toDouble(),
        tornRatioReliable: j['torn_ratio_reliable'] == true,
        condition: conditionFromString(j['condition'] as String? ?? 'uncertain'),
        imageQuality: j['image_quality'] as String? ?? 'acceptable',
        flags: (j['flags'] as List?)?.cast<String>() ?? const [],
        eligible: j['eligible_for_counting'] == true,
        rejectionReason: j['rejection_reason'] as String?,
        processingTimeMs: (j['processing_time_ms'] as num?)?.toInt() ?? 0,
        modelVersion: j['model_version'] as String?,
        isDemo: j['demo'] == true,
        error: j['error'] as String?,
        engine: engine,
      );
}

NoteCondition classifyCondition(double? torn, bool reliable, Thresholds t) {
  if (torn == null || !reliable) return NoteCondition.uncertain;
  if (torn <= t.tornGoodMax) return NoteCondition.good;
  if (torn <= t.tornDamagedMax) return NoteCondition.damaged;
  return NoteCondition.tooTorn;
}

/// Single source of truth for on-device eligibility (mirrors the backend).
(bool, String?) decideEligibility({
  required int? denomination,
  required double? confidence,
  required NoteCondition condition,
  required bool qualityOk,
  required List<String> flags,
  required Thresholds t,
}) {
  if (!qualityOk) return (false, 'poor_image_quality');
  if (flags.contains('multiple_notes')) return (false, 'multiple_notes');
  if (denomination == null) return (false, 'not_recognized');
  if (confidence == null || confidence < t.minConfidence) return (false, 'low_confidence');
  if (condition == NoteCondition.uncertain) return (false, 'condition_uncertain');
  if (condition == NoteCondition.tooTorn) return (false, 'too_torn');
  if (condition == NoteCondition.damaged && !t.countDamagedNotes) return (false, 'damaged');
  return (true, null);
}
