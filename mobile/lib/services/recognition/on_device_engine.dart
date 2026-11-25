import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/app_config.dart';
import '../../models/analysis_result.dart';
import '../vision/torn_estimator.dart';
import 'recognition_engine.dart';

const modelAsset = 'assets/models/banknote_classifier.tflite';
const labelsAsset = 'assets/models/labels.json';

/// Fully offline engine: Dart image-quality + torn estimation, TensorFlow
/// Lite denomination classifier. When the model asset is absent it reports
/// `model_not_installed` — it never guesses a denomination.
class OnDeviceRecognitionEngine extends RecognitionEngine {
  OnDeviceRecognitionEngine({this.thresholds = const Thresholds(), AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final Thresholds thresholds;
  final AssetBundle _bundle;
  Interpreter? _interpreter;
  Map<String, dynamic>? _meta;
  String? _loadError;
  bool _loadAttempted = false;

  @override
  EngineMode get mode => EngineMode.onDevice;

  Future<bool> _ensureModel() async {
    if (_interpreter != null) return true;
    if (_loadAttempted) return false;
    _loadAttempted = true;
    try {
      _meta = jsonDecode(await _bundle.loadString(labelsAsset)) as Map<String, dynamic>;
      await _bundle.load(modelAsset); // throws if the asset is not bundled
      _interpreter = await Interpreter.fromAsset(modelAsset, options: InterpreterOptions()..threads = 2);
      return true;
    } catch (e) {
      _loadError = 'On-device model not installed ($modelAsset). See machine_learning/README.md.';
      return false;
    }
  }

  @override
  Future<EngineStatus> status() async {
    final ok = await _ensureModel();
    return EngineStatus(
        ready: ok, message: ok ? 'On-device model loaded.' : (_loadError ?? 'Model not loaded.'), modelVersion: _meta?['model_version'] as String?);
  }

  @override
  Future<AnalysisResult> analyze(File image, {required StageCallback onStage}) async {
    final sw = Stopwatch()..start();
    final bytes = await image.readAsBytes();

    onStage(const StageUpdate(StageName.imageQuality, StageStatus.running));
    final pre = await Isolate.run(() => _preprocess(bytes));
    if (pre == null) throw const EngineException('invalid_image');
    onStage(StageUpdate(StageName.imageQuality, pre.qualityOk ? StageStatus.passed : StageStatus.failed, pre.quality));
    if (!pre.qualityOk) {
      return AnalysisResult(success: false, imageQuality: pre.quality, rejectionReason: 'poor_image_quality', engine: 'on_device');
    }

    onStage(const StageUpdate(StageName.tornDetection, StageStatus.running));
    final torn = await Isolate.run(() => estimateTorn(pre.image));
    if (!torn.found) {
      onStage(StageUpdate(StageName.tornDetection, StageStatus.failed, torn.reason ?? ''));
      return AnalysisResult(success: false, rejectionReason: torn.reason ?? 'no_note_found', flags: torn.flags, engine: 'on_device');
    }
    onStage(StageUpdate(StageName.tornDetection, torn.reliable ? StageStatus.passed : StageStatus.warning, torn.flags.join(',')));

    // Recognition (needed to pick the denomination-specific geometry).
    if (!await _ensureModel()) {
      onStage(const StageUpdate(StageName.tornRatio, StageStatus.skipped, 'awaiting recognition'));
      onStage(const StageUpdate(StageName.currencyRecognition, StageStatus.failed, 'model_not_installed'));
      return AnalysisResult(
          success: false, error: 'model_not_installed', rejectionReason: 'model_not_installed', tornRatio: torn.tornRatio, flags: torn.flags, engine: 'on_device');
    }
    final (denom, conf) = _classify(torn.crop ?? pre.image);

    onStage(const StageUpdate(StageName.tornRatio, StageStatus.running));
    var ratio = torn.tornRatio, reliable = torn.reliable;
    final flags = [...torn.flags];
    final dims = denom == null ? null : noteDimensionsMm[denom];
    if (dims != null) {
      final refined = await Isolate.run(() => estimateTorn(pre.image, expectedAspect: dims.$1 / dims.$2));
      if (refined.found) {
        ratio = refined.tornRatio;
        reliable = refined.reliable;
        flags.addAll(refined.flags.where((f) => !flags.contains(f)));
      }
    }
    onStage(StageUpdate(StageName.tornRatio, reliable ? StageStatus.passed : StageStatus.warning, '$ratio%'));
    final recogOk = denom != null && conf >= thresholds.minConfidence;
    onStage(StageUpdate(StageName.currencyRecognition, recogOk ? StageStatus.passed : StageStatus.failed, denom == null ? 'not_a_banknote' : '$denom BDT'));

    final condition = classifyCondition(ratio, reliable, thresholds);
    final (eligible, reason) =
        decideEligibility(denomination: denom, confidence: conf, condition: condition, qualityOk: true, flags: flags, t: thresholds);
    return AnalysisResult(
      success: true,
      denomination: denom,
      confidence: conf,
      tornRatio: ratio,
      tornRatioReliable: reliable,
      condition: condition,
      flags: flags,
      eligible: eligible,
      rejectionReason: reason,
      processingTimeMs: sw.elapsedMilliseconds,
      modelVersion: _meta?['model_version'] as String?,
      engine: 'on_device',
    );
  }

  (int?, double) _classify(img.Image crop) {
    final interp = _interpreter!;
    final size = (_meta?['input_size'] as num?)?.toInt() ?? 224;
    final labels = (_meta!['labels'] as List).cast<String>();
    final mean = ((_meta?['mean'] as List?) ?? [0, 0, 0]).map((e) => (e as num).toDouble()).toList();
    final std = ((_meta?['std'] as List?) ?? [1, 1, 1]).map((e) => (e as num).toDouble()).toList();
    final nhwc = (_meta?['layout'] as String? ?? 'NHWC') == 'NHWC';

    // Letterbox to square (grey 114), matching training preprocessing.
    final s = size / math.max(crop.width, crop.height);
    final resized = img.copyResize(crop, width: math.max(1, (crop.width * s).round()), height: math.max(1, (crop.height * s).round()));
    final canvas = img.Image(width: size, height: size)..clear(img.ColorRgb8(114, 114, 114));
    img.compositeImage(canvas, resized, dstX: (size - resized.width) ~/ 2, dstY: (size - resized.height) ~/ 2);

    final input = Float32List(size * size * 3);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final p = canvas.getPixel(x, y);
        final c = [p.r / 255.0, p.g / 255.0, p.b / 255.0];
        for (var k = 0; k < 3; k++) {
          final v = (c[k] - mean[k]) / std[k];
          input[nhwc ? (y * size + x) * 3 + k : k * size * size + y * size + x] = v;
        }
      }
    }
    final shape = interp.getInputTensor(0).shape;
    final out = List.filled(labels.length, 0.0).reshape([1, labels.length]);
    interp.run(input.reshape(shape), out);
    var probs = (out[0] as List).map((e) => (e as num).toDouble()).toList();
    final sum = probs.fold(0.0, (a, b) => a + b);
    if (probs.any((p) => p < 0) || (sum - 1).abs() > 1e-3) {
      final mx = probs.reduce(math.max);
      final e = probs.map((p) => math.exp(p - mx)).toList();
      final es = e.fold(0.0, (a, b) => a + b);
      probs = e.map((v) => v / es).toList();
    }
    var best = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[best]) best = i;
    }
    final head = labels[best].split('_').first;
    final d = int.tryParse(head);
    return (d != null && supportedDenominations.contains(d) ? d : null, probs[best]);
  }
}

class _Pre {
  _Pre(this.image, this.quality, this.qualityOk);
  final img.Image image;
  final String quality;
  final bool qualityOk;
}

/// Decode (with EXIF orientation), downscale, and assess blur/brightness.
_Pre? _preprocess(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  if (math.max(im.width, im.height) > 1024) {
    im = im.width >= im.height ? img.copyResize(im, width: 1024) : img.copyResize(im, height: 1024);
  }
  final gray = img.grayscale(img.copyResize(im, width: 640));
  double sum = 0, sum2 = 0, lsum = 0, lsum2 = 0;
  var n = 0;
  for (var y = 1; y < gray.height - 1; y++) {
    for (var x = 1; x < gray.width - 1; x++) {
      final c = gray.getPixel(x, y).r.toDouble();
      sum += c;
      sum2 += c * c;
      final lap = 4 * c - gray.getPixel(x - 1, y).r - gray.getPixel(x + 1, y).r - gray.getPixel(x, y - 1).r - gray.getPixel(x, y + 1).r;
      lsum += lap;
      lsum2 += lap * lap;
      n++;
    }
  }
  final mean = sum / n, contrast = math.sqrt(math.max(0, sum2 / n - mean * mean));
  final lapVar = lsum2 / n - (lsum / n) * (lsum / n);
  final q = mean < 45
      ? 'too_dark'
      : mean > 225
          ? 'too_bright'
          : contrast < 12
              ? 'low_contrast'
              : lapVar < 60
                  ? 'blurry'
                  : 'acceptable';
  return _Pre(im, q, q == 'acceptable');
}
