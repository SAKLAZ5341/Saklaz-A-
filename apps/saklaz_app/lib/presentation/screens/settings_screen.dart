import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_integrations/saklaz_integrations.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../../application/conversation_controller.dart';
import '../../application/settings_controller.dart';
import '../../infrastructure/providers.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/saklaz_logo.dart';
import 'permissions_screen.dart';

final speechEngineInfoProvider = FutureProvider.autoDispose<SpeechEngineInfo>(
  (ref) => ref.watch(speechRecognizerProvider).engineInfo(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  static const route = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final brain = ref.watch(assistantBrainProvider);
    final repo = ref.watch(conversationRepositoryProvider);
    final engine = ref.watch(speechEngineInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const _Section('Ses'),
              SwitchListTile(
                title: const Text('Yanıtları sesli oku'),
                value: s.voiceReplies,
                onChanged: (v) => ctrl.update((x) => x.copyWith(voiceReplies: v)),
              ),
              SwitchListTile(
                title: const Text('Yan tuşla açılınca dinlemeye başla'),
                subtitle: const Text('Kapalıysa mikrofon yalnızca düğmeye basınca açılır.'),
                value: s.listenOnAssistInvoke,
                onChanged: (v) => ctrl.update((x) => x.copyWith(listenOnAssistInvoke: v)),
              ),
              SwitchListTile(
                title: const Text('Cihaz üzerinde tanımayı tercih et'),
                subtitle: Text(engine.when(
                  data: (e) => e.onDevice
                      ? 'Cihaz içi tanıyıcı mevcut (Türkçe dil paketi gerekebilir).'
                      : 'Cihaz içi tanıyıcı yok; sistem motoru: ${e.engine ?? "bulunamadı"}',
                  loading: () => 'Kontrol ediliyor…',
                  error: (e, _) => 'Tanıma motoru okunamadı',
                )),
                value: s.preferOnDeviceRecognition,
                onChanged: (v) => ctrl.update((x) => x.copyWith(preferOnDeviceRecognition: v)),
              ),
              ListTile(
                title: const Text('Konuşma hızı'),
                subtitle: Slider(
                  value: s.speechRate,
                  min: 0.5,
                  max: 1.8,
                  divisions: 13,
                  label: s.speechRate.toStringAsFixed(1),
                  onChanged: (v) => ctrl.update((x) => x.copyWith(speechRate: v)),
                ),
              ),
              ListTile(
                title: const Text('Ses tonu'),
                subtitle: Slider(
                  value: s.speechPitch,
                  min: 0.6,
                  max: 1.6,
                  divisions: 10,
                  label: s.speechPitch.toStringAsFixed(1),
                  onChanged: (v) => ctrl.update((x) => x.copyWith(speechPitch: v)),
                ),
              ),
              const _Section('Asistan'),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Asistan izinleri'),
                subtitle: const Text('Varsayılan asistan rolü, mikrofon, yan tuş'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, PermissionsScreen.route),
              ),
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: const Text('Zekâ motoru'),
                subtitle: Text('${brain.displayName} · Yerel AI ve bulut zekâsı Phase 4\'te'),
              ),
              const _Section('Gizlilik'),
              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('Konuşma geçmişi'),
                subtitle: Text(repo.isPersistent
                    ? 'Cihazda şifreli saklanıyor'
                    : 'Yalnızca bellekte; uygulama kapanınca silinir (şifreli kalıcı hafıza Phase 2)'),
                trailing: TextButton(
                  onPressed: () => ref.read(conversationProvider.notifier).clearHistory(),
                  child: const Text('Temizle'),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.cloud_off),
                title: Text('Veri paylaşımı'),
                subtitle: Text('Bu sürüm hiçbir veriyi cihaz dışına göndermez. API anahtarı içermez.'),
              ),
              const _Section('Entegrasyonlar (planlanan)'),
              for (final i in plannedIntegrations)
                ListTile(
                  leading: const Icon(Icons.extension_outlined),
                  title: Text(i.displayName),
                  subtitle: Text(i.description),
                  trailing: const Text('Phase 5', style: TextStyle(color: SaklazColors.textSecondary)),
                ),
              const SizedBox(height: 24),
              const Center(child: SaklazWordmark(height: 22)),
              const SizedBox(height: 8),
              const Center(
                child: Text('Sürüm 0.1.0 · Phase 1', style: TextStyle(color: SaklazColors.textSecondary)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(color: SaklazColors.cyan, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w700),
        ),
      );
}
