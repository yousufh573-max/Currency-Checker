import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'command_parser.dart' show normalizeSpeech;

/// Voice input/output used by the screens. Abstract so tests can inject a fake.
abstract class VoiceIO {
  ValueListenable<bool> get listening;
  ValueListenable<bool> get speaking;

  /// Normalised microphone level 0..1 (drives the audio-reactive waveform).
  ValueListenable<double> get soundLevel;
  ValueListenable<bool> get micAvailable;

  Future<bool> init();
  void configure({required String ttsLocale, required String sttLocale, required double rate, bool preferOffline});

  /// Speaks [text]. Speech recognition is paused while speaking and resumes
  /// afterwards (if a screen still wants to listen), so the app never hears itself.
  Future<void> speak(String text);

  /// Start listening; [onFinal] receives each final recognised phrase.
  /// Listening auto-restarts after silence until [stopListening] is called.
  /// Returns an owner token: [stopListening] with a stale token is ignored, so
  /// a screen being disposed cannot stop the next screen's listening.
  Object listen(void Function(String words) onFinal);
  Future<void> stopListening([Object? owner]);

  /// Stops speech and recognition (app paused / screen disposed).
  Future<void> stopAll();
  void setPaused(bool paused);
}

class VoiceService implements VoiceIO {
  final _tts = FlutterTts();
  final _stt = SpeechToText();

  @override
  final ValueNotifier<bool> listening = ValueNotifier(false);
  @override
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  @override
  final ValueNotifier<double> soundLevel = ValueNotifier(0.0);
  @override
  final ValueNotifier<bool> micAvailable = ValueNotifier(false);

  bool _initialized = false;
  bool _wantListening = false;
  bool _paused = false;
  bool _starting = false;
  void Function(String)? _handler;
  String _sttLocale = 'en_US';
  bool _preferOffline = false;
  int _speakGen = 0;
  int _errorStreak = 0;
  DateTime _lastSpeechEnd = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSpoken = '';
  Timer? _restartTimer;

  static const _echoGuard = Duration(milliseconds: 700);

  @override
  Future<bool> init() async {
    if (_initialized) return micAvailable.value;
    _initialized = true;
    await _tts.awaitSpeakCompletion(true);
    try {
      micAvailable.value = await _stt.initialize(onError: _onError, onStatus: _onStatus);
    } catch (e) {
      debugPrint('STT init failed: $e');
      micAvailable.value = false;
    }
    return micAvailable.value;
  }

  @override
  void configure({required String ttsLocale, required String sttLocale, required double rate, bool preferOffline = false}) {
    _sttLocale = sttLocale;
    _preferOffline = preferOffline;
    unawaited(() async {
      final ok = await _tts.isLanguageAvailable(ttsLocale);
      await _tts.setLanguage(ok == true ? ttsLocale : 'en-US');
      await _tts.setSpeechRate(rate.clamp(0.2, 0.8));
    }());
  }

  @override
  Future<void> speak(String text) async {
    final gen = ++_speakGen;
    _lastSpoken = normalizeSpeech(text);
    speaking.value = true;
    _restartTimer?.cancel();
    if (_stt.isListening) await _stt.cancel(); // never record our own voice
    listening.value = false;
    await _tts.stop();
    if (gen != _speakGen) return;
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS failed: $e');
    }
    if (gen != _speakGen) return; // superseded by a newer utterance
    _lastSpeechEnd = DateTime.now();
    speaking.value = false;
    _scheduleRestart(const Duration(milliseconds: 350));
  }

  Object? _owner;

  @override
  Object listen(void Function(String words) onFinal) {
    final owner = Object();
    _owner = owner;
    _handler = onFinal;
    _wantListening = true;
    _errorStreak = 0;
    _startIfPossible();
    return owner;
  }

  @override
  Future<void> stopListening([Object? owner]) async {
    if (owner != null && !identical(owner, _owner)) return;
    _owner = null;
    _wantListening = false;
    _handler = null;
    _restartTimer?.cancel();
    if (_stt.isListening) await _stt.stop();
    listening.value = false;
    soundLevel.value = 0;
  }

  @override
  Future<void> stopAll() async {
    _speakGen++;
    await stopListening();
    await _tts.stop();
    speaking.value = false;
  }

  @override
  void setPaused(bool paused) {
    _paused = paused;
    if (paused) {
      _restartTimer?.cancel();
      _speakGen++;
      unawaited(_tts.stop());
      speaking.value = false;
      if (_stt.isListening) unawaited(_stt.cancel());
      listening.value = false;
    } else {
      _scheduleRestart(const Duration(milliseconds: 300));
    }
  }

  void _scheduleRestart(Duration d) {
    _restartTimer?.cancel();
    if (!_wantListening) return;
    _restartTimer = Timer(d, _startIfPossible);
  }

  Future<void> _startIfPossible() async {
    if (!_wantListening || _paused || speaking.value || _starting || !micAvailable.value || _stt.isListening) return;
    _starting = true;
    try {
      await _stt.listen(
        onResult: _onResult,
        onSoundLevelChange: _onLevel,
        listenOptions: SpeechListenOptions(
          localeId: _sttLocale,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
          partialResults: false,
          onDevice: _preferOffline,
          listenMode: ListenMode.confirmation,
          cancelOnError: true,
          autoPunctuation: false,
        ),
      );
      listening.value = true;
    } catch (e) {
      debugPrint('STT listen failed: $e');
      _scheduleRestart(const Duration(seconds: 2));
    } finally {
      _starting = false;
    }
  }

  void _onLevel(double db) {
    // Android reports roughly -2..10 dB; map to 0..1.
    soundLevel.value = ((db + 2) / 12).clamp(0.0, 1.0);
  }

  void _onResult(SpeechRecognitionResult r) {
    if (!r.finalResult) return;
    final words = r.recognizedWords;
    if (words.trim().isEmpty) return;
    // Echo guard: ignore anything captured right after our own speech, or that
    // closely matches what we just said.
    if (speaking.value || DateTime.now().difference(_lastSpeechEnd) < _echoGuard) return;
    final norm = normalizeSpeech(words);
    if (_lastSpoken.isNotEmpty && norm.length > 12 && _lastSpoken.contains(norm)) return;
    _errorStreak = 0;
    _handler?.call(words);
  }

  void _onStatus(String status) {
    if (status == SpeechToText.notListeningStatus || status == SpeechToText.doneStatus) {
      listening.value = false;
      soundLevel.value = 0;
      _scheduleRestart(Duration(milliseconds: 300 + 400 * math.min(_errorStreak, 6)));
    } else if (status == SpeechToText.listeningStatus) {
      listening.value = true;
    }
  }

  void _onError(SpeechRecognitionError e) {
    listening.value = false;
    if (e.errorMsg.contains('permission')) {
      micAvailable.value = false;
      _wantListening = false;
      return;
    }
    // Back off on repeated no-match/timeout to save battery.
    _errorStreak++;
    _scheduleRestart(Duration(milliseconds: 500 + 500 * math.min(_errorStreak, 6)));
  }
}
