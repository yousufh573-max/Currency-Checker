import 'dart:io';

import 'package:banknote_assistant/core/strings.dart';
import 'package:banknote_assistant/models/analysis_result.dart';
import 'package:banknote_assistant/services/recognition/demo_engine.dart';
import 'package:banknote_assistant/services/recognition/recognition_engine.dart';
import 'package:banknote_assistant/services/recognition/server_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simulates "no internet": every request fails with a connection error.
class OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) =>
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
  @override
  void close({bool force = false}) {}
}

void main() {
  late File img;
  setUpAll(() async {
    img = File('${Directory.systemTemp.path}/ba_test_capture.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff, 0x00]);
  });

  group('server URL validation (HTTPS in release)', () {
    test('https accepted', () => expect(validateServerUrl('https://api.example.org', allowHttp: false), isNull));
    test('http rejected in release', () => expect(validateServerUrl('http://192.168.1.5:8000', allowHttp: false), 'https_required'));
    test('http allowed in debug', () => expect(validateServerUrl('http://192.168.1.5:8000', allowHttp: true), isNull));
    test('credentials in URL rejected', () => expect(validateServerUrl('https://user:pw@host', allowHttp: false), 'invalid_url'));
    test('garbage rejected', () => expect(validateServerUrl('not a url', allowHttp: false), 'invalid_url'));
  });

  test('server mode refuses to upload without consent', () async {
    final e = ServerRecognitionEngine(baseUrl: 'https://api.example.org', consentGiven: false);
    expect(() => e.analyze(img, onStage: (_) {}), throwsA(isA<EngineException>().having((x) => x.code, 'code', 'consent_required')));
  });

  test('offline: network failure becomes a spoken, recoverable error (no fake result)', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.org'))..httpClientAdapter = OfflineAdapter();
    final e = ServerRecognitionEngine(baseUrl: 'https://api.example.org', consentGiven: true, dio: dio);
    final stages = <StageUpdate>[];
    await expectLater(e.analyze(img, onStage: stages.add), throwsA(isA<EngineException>().having((x) => x.code, 'code', 'network')));
    expect(stages.where((s) => s.status == StageStatus.passed), isEmpty, reason: 'no fake completion indicators');
    expect(const S(AppLanguage.en).errorMessage('network'), contains('Cannot reach'));
    final status = await e.status();
    expect(status.ready, isFalse);
  });

  test('demo engine results are always flagged and spoken as demo', () async {
    final e = DemoRecognitionEngine(stageDelay: Duration.zero);
    final r = await e.analyze(img, onStage: (_) {});
    expect(r.isDemo, isTrue);
    expect((await e.status()).isDemo, isTrue);
    expect(const S(AppLanguage.en).resultSpeech(r, added: true, total: 20), startsWith('Demo mode, not real recognition.'));
  });

  group('spoken result always matches the displayed/added state', () {
    const s = S(AppLanguage.en);
    test('accepted 20', () {
      const r = AnalysisResult(success: true, denomination: 20, confidence: 0.986, tornRatio: 2, tornRatioReliable: true, condition: NoteCondition.good, eligible: true);
      expect(s.resultSpeech(r, added: true, total: 20), '20 Taka detected. Torn ratio is 2 percent. Added to your total. Current total: 20 Taka.');
    });
    test('torn 500 says NOT added (fixes PDF page 5 inconsistency)', () {
      const r = AnalysisResult(
          success: true, denomination: 500, confidence: 0.916, tornRatio: 40, tornRatioReliable: true, condition: NoteCondition.tooTorn, rejectionReason: 'too_torn');
      final speech = s.resultSpeech(r, added: false, total: 20);
      expect(speech, contains('Not added to your total'));
      expect(speech, isNot(contains(' Added to your total')));
      expect(speech, contains('Current total: 20 Taka'));
    });
    test('Bengali', () {
      const r = AnalysisResult(success: true, denomination: 20, confidence: 0.99, tornRatio: 0, tornRatioReliable: true, condition: NoteCondition.good, eligible: true);
      expect(const S(AppLanguage.bn).resultSpeech(r, added: true, total: 20), allOf(contains('20 টাকা শনাক্ত হয়েছে'), contains('মোটে যোগ হয়েছে')));
    });
  });
}
