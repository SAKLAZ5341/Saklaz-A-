import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../../application/settings_controller.dart';
import '../../infrastructure/providers.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/common.dart';
import '../widgets/saklaz_logo.dart';
import 'ai_settings_screen.dart';
import 'chat_history_screen.dart';
import 'memory_screen.dart';
import 'model_screen.dart';
import 'notes_screen.dart';
import 'permissions_screen.dart';
import 'providers_screen.dart';

final speechEngineInfoProvider = FutureProvider.autoDispose<SpeechEngineInfo>(
  (ref) => ref.watch(speechRecognizerProvider).engineInfo(),
);

/// Uygulama Ayarları (merkez).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  static const route = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final engine = ref.watch(speechEngineInfoProvider);

    Widget nav(IconData icon, String title, String subtitle, String route) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pushNamed(context, route),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SectionTitle('Yapay zekâ'),
            nav(Icons.psychology_outlined, 'Yapay Zekâ Ayarları', 'Aktif zekâ (varsayılan: yerel), öğrenme', AiSettingsScreen.route),
            nav(Icons.download_for_offline_outlined, 'Model Yönetimi', 'Yerel modeli indir ve yönet', ModelScreen.route),
            nav(Icons.key_outlined, 'API Sağlayıcıları', 'İsteğe bağlı, varsayılan pasif', ProvidersScreen.route),
            const SectionTitle('Kişisel'),
            nav(Icons.memory, 'Benim Hafızam', 'Öğrenilen bilgiler: gör, ara, düzenle, sil', MemoryScreen.route),
            nav(Icons.forum_outlined, 'Sohbet Geçmişi', 'Geçmiş konuşmalarda ara', ChatHistoryScreen.route),
            nav(Icons.sticky_note_2_outlined, 'Notlar ve Hatırlatmalar', 'Kayıtlı notlar, yaklaşan hatırlatmalar', NotesScreen.route),
            const SectionTitle('Ses'),
            SwitchListTile(
              title: const Text('Yanıtları sesli oku'),
              value: s.voiceReplies,
              onChanged: (v) => ctrl.update((x) => x.copyWith(voiceReplies: v)),
            ),
            SwitchListTile(
              title: const Text('Yan tuşla açılınca konuşmayı başlat'),
              subtitle: const Text('Varsayılan kapalı: mikrofon yalnızca "Konuşmayı Başlat" ile açılır.'),
              value: s.listenOnAssistInvoke,
              onChanged: (v) => ctrl.update((x) => x.copyWith(listenOnAssistInvoke: v)),
            ),
            SwitchListTile(
              title: const Text('Cihaz üzerinde ses tanımayı tercih et'),
              subtitle: Text(engine.when(
                data: (e) => e.onDevice ? 'Cihaz içi tanıyıcı mevcut (Türkçe dil paketi gerekebilir).' : 'Sistem motoru: ${e.engine ?? "bulunamadı"}',
                loading: () => 'Kontrol ediliyor…',
                error: (e, _) => 'Tanıma motoru okunamadı',
              )),
              value: s.preferOnDeviceRecognition,
              onChanged: (v) => ctrl.update((x) => x.copyWith(preferOnDeviceRecognition: v)),
            ),
            _SliderTile('Konuşma hızı', s.speechRate, 0.5, 1.8, (v) => ctrl.update((x) => x.copyWith(speechRate: v))),
            _SliderTile('Ses tonu', s.speechPitch, 0.6, 1.6, (v) => ctrl.update((x) => x.copyWith(speechPitch: v))),
            const SectionTitle('Telefon'),
            nav(Icons.verified_user_outlined, 'İzinler', 'Asistan rolü, mikrofon, rehber, takvim, bildirimler', PermissionsScreen.route),
            const SizedBox(height: 24),
            const Center(child: SaklazWordmark(height: 22)),
            const SizedBox(height: 8),
            const Center(child: Text('Sürüm 1.0.0 · Yerel AI: LiteRT-LM', style: TextStyle(color: SaklazColors.textSecondary))),
          ],
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile(this.title, this.value, this.min, this.max, this.onChanged);
  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        subtitle: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) * 10).round(),
          label: value.toStringAsFixed(1),
          onChanged: onChanged,
        ),
      );
}
