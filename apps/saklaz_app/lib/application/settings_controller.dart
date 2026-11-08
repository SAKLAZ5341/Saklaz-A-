import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';

import '../infrastructure/providers.dart';
import 'model_catalog.dart';

/// Kullanıcı tercihleri. Şifreli hafızadaki `preferences` tablosunda kalıcıdır.
/// API anahtarları BURADA DEĞİL, Keystore destekli güvenli depoda saklanır.
class AppSettings {
  AppSettings({
    this.voiceReplies = true,
    this.listenOnAssistInvoke = false,
    this.preferOnDeviceRecognition = true,
    this.speechRate = 1.0,
    this.speechPitch = 1.0,
    this.autoLearn = true,
    this.preferGpu = true,
    String? activeModelId,
    this.activeProvider,
    this.cloudConsent = CloudMode.ask,
    this.shareFactsWithCloud = false,
    Map<ProviderKind, ProviderSettings>? providers,
  })  : activeModelId = activeModelId ?? modelCatalog.firstWhere((m) => m.recommended).id,
        providers = providers ?? {for (final k in ProviderKind.values) k: ProviderSettings(kind: k)};

  final bool voiceReplies;

  /// Yan tuşla çağrılınca konuşmayı otomatik başlat. Varsayılan KAPALI.
  final bool listenOnAssistInvoke;
  final bool preferOnDeviceRecognition;
  final double speechRate;
  final double speechPitch;

  /// Konuşmalardan otomatik kişisel bilgi öğrenme.
  final bool autoLearn;
  final bool preferGpu;
  final String activeModelId;

  /// null = Yerel AI (varsayılan). Bulut yalnızca kullanıcı seçip etkinleştirirse.
  final ProviderKind? activeProvider;

  /// Bulut sağlayıcısı etkinken: her seferinde sor / sormadan gönder.
  final CloudMode cloudConsent;
  final bool shareFactsWithCloud;
  final Map<ProviderKind, ProviderSettings> providers;

  ProviderSettings provider(ProviderKind k) => providers[k] ?? ProviderSettings(kind: k);

  /// Etkin ve seçili bulut sağlayıcısı (yoksa null => tamamen yerel).
  ProviderSettings? get activeCloud {
    final k = activeProvider;
    if (k == null) return null;
    final p = provider(k);
    return p.enabled ? p : null;
  }

  AppSettings copyWith({
    bool? voiceReplies,
    bool? listenOnAssistInvoke,
    bool? preferOnDeviceRecognition,
    double? speechRate,
    double? speechPitch,
    bool? autoLearn,
    bool? preferGpu,
    String? activeModelId,
    ProviderKind? activeProvider,
    bool clearActiveProvider = false,
    CloudMode? cloudConsent,
    bool? shareFactsWithCloud,
    ProviderSettings? providerUpdate,
  }) =>
      AppSettings(
        voiceReplies: voiceReplies ?? this.voiceReplies,
        listenOnAssistInvoke: listenOnAssistInvoke ?? this.listenOnAssistInvoke,
        preferOnDeviceRecognition: preferOnDeviceRecognition ?? this.preferOnDeviceRecognition,
        speechRate: speechRate ?? this.speechRate,
        speechPitch: speechPitch ?? this.speechPitch,
        autoLearn: autoLearn ?? this.autoLearn,
        preferGpu: preferGpu ?? this.preferGpu,
        activeModelId: activeModelId ?? this.activeModelId,
        activeProvider: clearActiveProvider ? null : (activeProvider ?? this.activeProvider),
        cloudConsent: cloudConsent ?? this.cloudConsent,
        shareFactsWithCloud: shareFactsWithCloud ?? this.shareFactsWithCloud,
        providers: providerUpdate == null ? providers : {...providers, providerUpdate.kind: providerUpdate},
      );

  Map<String, String> toPrefs() => {
        'voiceReplies': '$voiceReplies',
        'listenOnAssistInvoke': '$listenOnAssistInvoke',
        'preferOnDeviceRecognition': '$preferOnDeviceRecognition',
        'speechRate': '$speechRate',
        'speechPitch': '$speechPitch',
        'autoLearn': '$autoLearn',
        'preferGpu': '$preferGpu',
        'activeModelId': activeModelId,
        'activeProvider': activeProvider?.name ?? 'local',
        'cloudConsent': cloudConsent.name,
        'shareFactsWithCloud': '$shareFactsWithCloud',
        'providers': jsonEncode({for (final e in providers.entries) e.key.name: e.value.toJson()}),
      };

  static AppSettings fromPrefs(Map<String, String> p) {
    final d = AppSettings();
    bool b(String k, bool def) => p[k] == null ? def : p[k] == 'true';
    double n(String k, double def) => double.tryParse(p[k] ?? '') ?? def;
    final providers = <ProviderKind, ProviderSettings>{};
    try {
      final j = jsonDecode(p['providers'] ?? '{}') as Map<String, Object?>;
      for (final k in ProviderKind.values) {
        final v = j[k.name];
        providers[k] = v is Map<String, Object?> ? ProviderSettings.fromJson(k, v) : ProviderSettings(kind: k);
      }
    } on Object {
      // bozuk tercih -> varsayılanlar
    }
    // Phase 2 gateway ayarlarını taşı (yalnızca adres; etkinleştirme kullanıcıda).
    if ((p['gatewayUrl'] ?? '').isNotEmpty && (providers[ProviderKind.gateway]?.baseUrl ?? '').isEmpty) {
      providers[ProviderKind.gateway] = ProviderSettings(kind: ProviderKind.gateway, baseUrl: p['gatewayUrl']!);
    }
    return AppSettings(
      voiceReplies: b('voiceReplies', d.voiceReplies),
      listenOnAssistInvoke: b('listenOnAssistInvoke', d.listenOnAssistInvoke),
      preferOnDeviceRecognition: b('preferOnDeviceRecognition', d.preferOnDeviceRecognition),
      speechRate: n('speechRate', d.speechRate),
      speechPitch: n('speechPitch', d.speechPitch),
      autoLearn: b('autoLearn', d.autoLearn),
      preferGpu: b('preferGpu', d.preferGpu),
      activeModelId: modelById(p['activeModelId']) != null ? p['activeModelId'] : null,
      activeProvider: ProviderKind.values.asNameMap()[p['activeProvider']],
      cloudConsent: p['cloudConsent'] == 'always' ? CloudMode.always : CloudMode.ask,
      shareFactsWithCloud: b('shareFactsWithCloud', d.shareFactsWithCloud),
      providers: providers.isEmpty ? null : providers,
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
