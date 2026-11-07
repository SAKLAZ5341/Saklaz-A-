import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';

import '../infrastructure/providers.dart';

/// Kullanıcı tercihleri. Şifreli hafızadaki `preferences` tablosunda kalıcıdır
/// (şifreleme yoksa yalnızca bellekte).
class AppSettings {
  const AppSettings({
    this.voiceReplies = true,
    this.listenOnAssistInvoke = false,
    this.preferOnDeviceRecognition = true,
    this.speechRate = 1.0,
    this.speechPitch = 1.0,
    this.useLocalLlm = true,
    this.cloudMode = CloudMode.ask,
    this.gatewayUrl = '',
    this.gatewayToken = '',
    this.cloudModel = '',
    this.shareFactsWithCloud = false,
  });

  /// Yanıtları sesli oku (dinlemeden bağımsız).
  final bool voiceReplies;

  /// Yan tuşla çağrılınca konuşmayı otomatik başlat. Varsayılan KAPALI:
  /// mikrofon yalnızca "Konuşmayı Başlat" ile açılır.
  final bool listenOnAssistInvoke;
  final bool preferOnDeviceRecognition;
  final double speechRate;
  final double speechPitch;

  /// Cihaz içi dil modelini (Gemini Nano) kullan.
  final bool useLocalLlm;
  final CloudMode cloudMode;
  final String gatewayUrl;

  /// Gateway cihaz tokenı (OpenAI anahtarı DEĞİL). Şifreli hafızada saklanır.
  final String gatewayToken;

  /// Boşsa gateway varsayılan modeli.
  final String cloudModel;

  /// İlgili kayıtlı kişisel bilgiler bulut isteğine bağlam olarak eklensin mi?
  final bool shareFactsWithCloud;

  GatewayConfig get gatewayConfig => GatewayConfig(baseUrl: gatewayUrl, deviceToken: gatewayToken, model: cloudModel);

  AppSettings copyWith({
    bool? voiceReplies,
    bool? listenOnAssistInvoke,
    bool? preferOnDeviceRecognition,
    double? speechRate,
    double? speechPitch,
    bool? useLocalLlm,
    CloudMode? cloudMode,
    String? gatewayUrl,
    String? gatewayToken,
    String? cloudModel,
    bool? shareFactsWithCloud,
  }) =>
      AppSettings(
        voiceReplies: voiceReplies ?? this.voiceReplies,
        listenOnAssistInvoke: listenOnAssistInvoke ?? this.listenOnAssistInvoke,
        preferOnDeviceRecognition: preferOnDeviceRecognition ?? this.preferOnDeviceRecognition,
        speechRate: speechRate ?? this.speechRate,
        speechPitch: speechPitch ?? this.speechPitch,
        useLocalLlm: useLocalLlm ?? this.useLocalLlm,
        cloudMode: cloudMode ?? this.cloudMode,
        gatewayUrl: gatewayUrl ?? this.gatewayUrl,
        gatewayToken: gatewayToken ?? this.gatewayToken,
        cloudModel: cloudModel ?? this.cloudModel,
        shareFactsWithCloud: shareFactsWithCloud ?? this.shareFactsWithCloud,
      );

  Map<String, String> toPrefs() => {
        'voiceReplies': '$voiceReplies',
        'listenOnAssistInvoke': '$listenOnAssistInvoke',
        'preferOnDeviceRecognition': '$preferOnDeviceRecognition',
        'speechRate': '$speechRate',
        'speechPitch': '$speechPitch',
        'useLocalLlm': '$useLocalLlm',
        'cloudMode': cloudMode.name,
        'gatewayUrl': gatewayUrl,
        'gatewayToken': gatewayToken,
        'cloudModel': cloudModel,
        'shareFactsWithCloud': '$shareFactsWithCloud',
      };

  static AppSettings fromPrefs(Map<String, String> p) {
    const d = AppSettings();
    bool b(String k, bool def) => p[k] == null ? def : p[k] == 'true';
    double n(String k, double def) => double.tryParse(p[k] ?? '') ?? def;
    return AppSettings(
      voiceReplies: b('voiceReplies', d.voiceReplies),
      listenOnAssistInvoke: b('listenOnAssistInvoke', d.listenOnAssistInvoke),
      preferOnDeviceRecognition: b('preferOnDeviceRecognition', d.preferOnDeviceRecognition),
      speechRate: n('speechRate', d.speechRate),
      speechPitch: n('speechPitch', d.speechPitch),
      useLocalLlm: b('useLocalLlm', d.useLocalLlm),
      cloudMode: CloudMode.values.asNameMap()[p['cloudMode']] ?? d.cloudMode,
      gatewayUrl: p['gatewayUrl'] ?? '',
      gatewayToken: p['gatewayToken'] ?? '',
      cloudModel: p['cloudModel'] ?? '',
      shareFactsWithCloud: b('shareFactsWithCloud', d.shareFactsWithCloud),
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.fromPrefs(ref.watch(memoryProvider).initialPreferences);

  void update(AppSettings Function(AppSettings s) change) {
    final next = change(state);
    state = next;
    final store = ref.read(memoryProvider).preferences;
    for (final e in next.toPrefs().entries) {
      unawaited(store.write(e.key, e.value));
    }
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
