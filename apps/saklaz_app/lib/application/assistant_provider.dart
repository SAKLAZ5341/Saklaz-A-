import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';

import '../infrastructure/providers.dart';
import 'local_ai_controller.dart';
import 'settings_controller.dart';

/// Ayarlar eksiksizse gateway istemcisi, değilse null.
final gatewayClientProvider = Provider<GatewayClient?>((ref) {
  final cfg = ref.watch(settingsProvider.select((s) => s.gatewayConfig));
  if (!cfg.isComplete) return null;
  return GatewayClient(cfg, ref.watch(httpTransportProvider));
});

final assistantProvider = Provider<SaklazAssistant>((ref) {
  return SaklazAssistant(
    facts: ref.watch(memoryProvider).facts,
    cloud: () => ref.read(gatewayClientProvider),
    localLlm: ref.watch(localLlmProvider),
    shareFactsWithCloud: () => ref.read(settingsProvider).shareFactsWithCloud,
    routeContext: () async {
      final s = ref.read(settingsProvider);
      final cloudConfigured = ref.read(gatewayClientProvider) != null;
      bool online;
      try {
        online = await ref.read(networkStatusProvider).isOnline();
      } on Object {
        online = false;
      }
      // Durum henüz okunmadıysa (ör. Ayarlar hiç açılmadı) bekle; askıda kalmasın.
      LocalLlmInfo? local;
      try {
        local = await ref.read(localAiProvider.future).timeout(const Duration(seconds: 3));
      } on Object {
        local = null;
      }
      return RouteContext(
        cloudMode: s.cloudMode,
        cloudConfigured: cloudConfigured,
        online: online,
        localLlmReady: s.useLocalLlm && local?.state == LocalLlmState.ready,
      );
    },
  );
});
