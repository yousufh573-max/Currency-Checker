import '../core/strings.dart';
import '../services/recognition/recognition_engine.dart';

class AppSettings {
  const AppSettings({
    this.language = AppLanguage.en,
    this.speechRate = 0.45,
    this.mode = EngineMode.onDevice,
    this.serverUrl = '',
    this.serverConsent = false,
    this.haptics = true,
    this.preferOfflineSpeech = false,
    this.autoCapture = true,
  });

  final AppLanguage language;
  final double speechRate;
  final EngineMode mode;
  final String serverUrl;

  /// Explicit, revocable consent to upload captures for server processing.
  final bool serverConsent;
  final bool haptics;
  final bool preferOfflineSpeech;
  final bool autoCapture;

  AppSettings copyWith({
    AppLanguage? language,
    double? speechRate,
    EngineMode? mode,
    String? serverUrl,
    bool? serverConsent,
    bool? haptics,
    bool? preferOfflineSpeech,
    bool? autoCapture,
  }) =>
      AppSettings(
        language: language ?? this.language,
        speechRate: speechRate ?? this.speechRate,
        mode: mode ?? this.mode,
        serverUrl: serverUrl ?? this.serverUrl,
        serverConsent: serverConsent ?? this.serverConsent,
        haptics: haptics ?? this.haptics,
        preferOfflineSpeech: preferOfflineSpeech ?? this.preferOfflineSpeech,
        autoCapture: autoCapture ?? this.autoCapture,
      );
}
