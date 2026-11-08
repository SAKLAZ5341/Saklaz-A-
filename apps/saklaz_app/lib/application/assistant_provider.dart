import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';

import '../infrastructure/providers.dart';
import 'local_ai_controller.dart';
import 'settings_controller.dart';

/// Etkin bulut sağlayıcısının istemcisi. Yerel AI seçiliyse veya sağlayıcı
/// etkin değilse null — bu durumda HİÇBİR bulut çağrısı yapılamaz.
final activeCloudClientProvider = FutureProvider<LlmClient?>((ref) async {
  final p = ref.watch(settingsProvider.select((s) => s.activeCloud));
  if (p == null) return null;
  final key = await ref.read(secretStoreProvider).get(p.kind.secretName);
  if (key == null || key.isEmpty) return null;
  final transport = ref.watch(httpTransportProvider);
  return switch (p.kind) {
    ProviderKind.openai => OpenAiResponsesClient(baseUrl: p.effectiveBaseUrl, apiKey: key, model: p.effectiveModel, transport: transport),
    ProviderKind.deepseek || ProviderKind.custom =>
      ChatCompletionsClient(baseUrl: p.effectiveBaseUrl, apiKey: key, model: p.effectiveModel, transport: transport),
    ProviderKind.gateway =>
      GatewayClient(GatewayConfig(baseUrl: p.effectiveBaseUrl, deviceToken: key, model: p.effectiveModel), transport),
  };
});

final assistantProvider = Provider<SaklazAssistant>((ref) {
  final memory = ref.watch(memoryProvider);
  return SaklazAssistant(
    facts: memory.facts,
    notes: memory.notes,
    reminders: memory.reminders,
    device: ref.watch(devicePortsProvider),
    localLlm: ref.watch(localLlmProvider),
    cloud: () => ref.read(activeCloudClientProvider).value,
    shareFactsWithCloud: () => ref.read(settingsProvider).shareFactsWithCloud,
    autoLearn: () => ref.read(settingsProvider).autoLearn,
    routeContext: () async {
      final s = ref.read(settingsProvider);
      final client = await ref.read(activeCloudClientProvider.future);
      var online = false;
      if (client != null) {
        try {
          online = await ref.read(networkStatusProvider).isOnline();
        } on Object {
          online = false;
        }
      }
      return RouteContext(
        cloudMode: client == null ? CloudMode.off : s.cloudConsent,
        cloudConfigured: client != null,
        online: online,
        localLlmReady: ref.read(localAiProvider).usable,
      );
    },
  );
});
