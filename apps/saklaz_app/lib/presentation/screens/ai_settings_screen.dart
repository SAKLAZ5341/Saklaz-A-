import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';

import '../../application/assistant_provider.dart';
import '../../application/local_ai_controller.dart';
import '../../application/settings_controller.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/common.dart';
import 'memory_screen.dart';
import 'model_screen.dart';
import 'providers_screen.dart';

/// Yapay Zekâ Ayarları: aktif zekâ (Yerel varsayılan), bulut izni, öğrenme.
class AiSettingsScreen extends ConsumerWidget {
  const AiSettingsScreen({super.key});
  static const route = '/ai-settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final ai = ref.watch(localAiProvider);

    void select(ProviderKind? k) {
      ctrl.update((x) => k == null ? x.copyWith(clearActiveProvider: true) : x.copyWith(activeProvider: k));
      ref.invalidate(activeCloudClientProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Yapay Zekâ Ayarları')),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SectionTitle('Aktif zekâ'),
            RadioGroup<ProviderKind?>(
              groupValue: s.activeProvider,
              onChanged: select,
              child: Column(children: [
                RadioListTile<ProviderKind?>(
                  value: null,
                  title: const Text('Yerel AI (varsayılan)'),
                  subtitle: Text(ai.ready ? 'Hazır: ${ai.llm.modelName}' : 'Model indirilmeli / yüklenmeli — internet gerekmez'),
                ),
                for (final k in ProviderKind.values)
                  RadioListTile<ProviderKind?>(
                    value: k,
                    enabled: s.provider(k).enabled,
                    title: Text(k.label),
                    subtitle: Text(s.provider(k).enabled ? 'Ücretli olabilir; ücret sana aittir' : 'Pasif — API Sağlayıcıları\'ndan etkinleştir'),
                  ),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Model Yönetimi'),
              subtitle: const Text('Yerel modeli indir, yükle, sil'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, ModelScreen.route),
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('API Sağlayıcıları'),
              subtitle: const Text('OpenAI, DeepSeek, özel API, SAKLAZ Gateway'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, ProvidersScreen.route),
            ),
            if (s.activeProvider != null) ...[
              const SectionTitle('Bulut kullanımı'),
              SwitchListTile(
                title: const Text('Her bulut isteğinden önce sor'),
                subtitle: const Text('Kapalıysa genel sorular sormadan buluta gönderilir. Basit komutlar ve hafıza her zaman yerelde kalır.'),
                value: s.cloudConsent == CloudMode.ask,
                onChanged: (v) => ctrl.update((x) => x.copyWith(cloudConsent: v ? CloudMode.ask : CloudMode.always)),
              ),
              SwitchListTile(
                title: const Text('İlgili kişisel bilgileri buluta bağlam olarak gönder'),
                subtitle: const Text('Varsayılan kapalı: kişisel hafızan buluta gönderilmez.'),
                value: s.shareFactsWithCloud,
                onChanged: (v) => ctrl.update((x) => x.copyWith(shareFactsWithCloud: v)),
              ),
            ],
            const SectionTitle('Kişisel öğrenme'),
            SwitchListTile(
              title: const Text('Otomatik öğrenme'),
              subtitle: const Text('Konuşmalarından kalıcı bilgileri (meslek, proje, ilgi alanı…) cihazda öğrenir. Sırlar kaydedilmez.'),
              value: s.autoLearn,
              onChanged: (v) => ctrl.update((x) => x.copyWith(autoLearn: v)),
            ),
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Benim Hafızam'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, MemoryScreen.route),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Model her konuşmada yeniden eğitilmez. SAKLAZ öğrendiklerini şifreli yerel hafızada saklar ve her soruda yalnızca ilgili olanları modele bağlam olarak verir.',
                style: TextStyle(color: SaklazColors.textSecondary, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
