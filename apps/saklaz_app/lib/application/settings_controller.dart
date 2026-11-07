import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kullanıcı ayarları. Phase 1'de yalnızca bellekte tutulur (uygulama
/// kapanınca varsayılana döner). Şifreli kalıcı ayarlar Phase 2'de.
class AppSettings {
  const AppSettings({
    this.voiceReplies = true,
    this.listenOnAssistInvoke = true,
    this.preferOnDeviceRecognition = true,
    this.speechRate = 1.0,
    this.speechPitch = 1.0,
  });

  /// Yanıtları sesli oku.
  final bool voiceReplies;

  /// Yan tuşla (asistan olarak) çağrılınca dinlemeye başla. Yan tuşa basmak
  /// bilinçli bir kullanıcı eylemidir; yine de kapatılabilir.
  final bool listenOnAssistInvoke;

  /// Mümkünse cihaz üzerinde (çevrimdışı) konuşma tanıma.
  final bool preferOnDeviceRecognition;

  final double speechRate;
  final double speechPitch;

  AppSettings copyWith({
    bool? voiceReplies,
    bool? listenOnAssistInvoke,
    bool? preferOnDeviceRecognition,
    double? speechRate,
    double? speechPitch,
  }) =>
      AppSettings(
        voiceReplies: voiceReplies ?? this.voiceReplies,
        listenOnAssistInvoke: listenOnAssistInvoke ?? this.listenOnAssistInvoke,
        preferOnDeviceRecognition: preferOnDeviceRecognition ?? this.preferOnDeviceRecognition,
        speechRate: speechRate ?? this.speechRate,
        speechPitch: speechPitch ?? this.speechPitch,
      );
}

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void update(AppSettings Function(AppSettings s) change) => state = change(state);
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
