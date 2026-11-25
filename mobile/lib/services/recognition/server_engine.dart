import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/app_config.dart';
import '../../models/analysis_result.dart';
import 'recognition_engine.dart';

/// Validates a user-entered server URL. Release builds require HTTPS.
String? validateServerUrl(String url, {bool allowHttp = kDebugMode}) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !u.hasScheme || u.host.isEmpty) return 'invalid_url';
  if (u.scheme != 'https' && !(allowHttp && u.scheme == 'http')) return 'https_required';
  if (u.userInfo.isNotEmpty) return 'invalid_url'; // never embed credentials
  return null;
}

/// Sends the capture to the FastAPI backend. Only used after the user has
/// explicitly consented to server-based processing (see Settings).
class ServerRecognitionEngine extends RecognitionEngine {
  ServerRecognitionEngine({required this.baseUrl, required this.consentGiven, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: connectTimeout,
              sendTimeout: analysisTimeout,
              receiveTimeout: analysisTimeout,
            ));

  final String baseUrl;
  final bool consentGiven;
  final Dio _dio;
  CancelToken? _cancel;

  @override
  EngineMode get mode => EngineMode.server;

  @override
  Future<EngineStatus> status() async {
    if (validateServerUrl(baseUrl) != null) return const EngineStatus(ready: false, message: 'Invalid or insecure server URL.');
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/v1/model/status');
      final d = r.data!;
      return EngineStatus(
          ready: d['loaded'] == true || d['demo_mode'] == true,
          message: d['message'] as String? ?? '',
          modelVersion: d['model_version'] as String?,
          isDemo: d['demo_mode'] == true);
    } on DioException catch (e) {
      return EngineStatus(ready: false, message: 'Server unreachable (${e.type.name}).');
    }
  }

  Future<FormData> _form(File image) async =>
      FormData.fromMap({'image': await MultipartFile.fromFile(image.path, filename: 'capture.jpg', contentType: DioMediaType('image', 'jpeg'))});

  @override
  Future<AnalysisResult> analyze(File image, {required StageCallback onStage}) async {
    if (!consentGiven) throw const EngineException('consent_required');
    final urlError = validateServerUrl(baseUrl);
    if (urlError != null) throw EngineException('network', urlError);
    _cancel = CancelToken();
    try {
      // Stage 1 — real quality check on the server.
      onStage(const StageUpdate(StageName.imageQuality, StageStatus.running));
      final q = await _dio.post<Map<String, dynamic>>('/api/v1/image/quality', data: await _form(image), cancelToken: _cancel);
      final ok = q.data?['acceptable'] == true;
      onStage(StageUpdate(StageName.imageQuality, ok ? StageStatus.passed : StageStatus.failed, q.data?['image_quality'] as String? ?? ''));
      if (!ok) {
        return AnalysisResult(
            success: false, imageQuality: q.data?['image_quality'] as String? ?? 'unknown', rejectionReason: 'poor_image_quality', engine: 'server');
      }

      // Stages 2–4 — full analysis; each stage is reported from the server's result.
      onStage(const StageUpdate(StageName.tornDetection, StageStatus.running));
      final r = await _dio.post<Map<String, dynamic>>('/api/v1/banknote/analyze', data: await _form(image), cancelToken: _cancel);
      final data = r.data!;
      for (final s in (data['stages'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final name = stageFromString(s['name'] as String);
        if (name == null || name == StageName.imageQuality) continue;
        onStage(StageUpdate(name, stageStatusFromString(s['status'] as String), s['detail'] as String? ?? ''));
      }
      return AnalysisResult.fromJson(data);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const EngineException('cancelled');
      if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout || e.response?.statusCode == 504) {
        throw const EngineException('timeout');
      }
      final code = e.response?.statusCode;
      if (code == 413 || code == 415 || code == 422) throw EngineException('invalid_image', '$code');
      if (code != null) throw EngineException('server_error', '$code');
      throw EngineException('network', e.type.name);
    }
  }

  @override
  void cancel() => _cancel?.cancel();
}
