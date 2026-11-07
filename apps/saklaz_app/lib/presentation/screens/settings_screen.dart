import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_integrations/saklaz_integrations.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../../application/assistant_provider.dart';
import '../../application/local_ai_controller.dart';
import '../../application/settings_controller.dart';
import '../../infrastructure/providers.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/saklaz_logo.dart';
import 'memory_screen.dart';
import 'permissions_screen.dart';

final speechEngineInfoProvider = FutureProvider.autoDispose<SpeechEngineInfo>(
  (ref) => ref.watch(speechRecognizerProvider).engineInfo(),
);

final deviceCapabilityProvider = FutureProvider.autoDispose<DeviceCapability?>((ref) async {
  final llm = ref.watch(localLlmProvider);
  return llm is AndroidLocalLlm ? llm.deviceCapability() : null;
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  static const route = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final engine = ref.watch(speechEngineInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const _Section('Ses'),
              SwitchListTile(
                title: const Text('Yanıtları sesli oku'),
                subtitle: const Text('Dinlemeden bağımsızdır; ana ekrandan da açılıp kapatılabilir.'),
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
              _SliderTile('Konuşma hızı', s.speechRate, 0.5, 1.8, (v) => ctrl.update((x) => x.copyWith(speechRate: v))),
              _SliderTile('Ses tonu', s.speechPitch, 0.6, 1.6, (v) => ctrl.update((x) => x.copyWith(speechPitch: v))),
              const _Section('Yerel zekâ'),
              const _LocalAiCard(),
              const _Section('Bulut zekâsı (OpenAI)'),
              const _CloudSettings(),
              const _Section('Gizlilik ve hafıza'),
              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('Hafıza'),
                subtitle: const Text('Kayıtlı bilgiler ve konuşma geçmişi'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, MemoryScreen.route),
              ),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Asistan izinleri'),
                subtitle: const Text('Varsayılan asistan rolü, mikrofon, yan tuş'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, PermissionsScreen.route),
              ),
              const _Section('Entegrasyonlar (planlanan)'),
              for (final i in plannedIntegrations)
                ListTile(
                  leading: const Icon(Icons.extension_outlined),
                  title: Text(i.displayName),
                  subtitle: Text(i.description),
                  trailing: const Text('Sonraki faz', style: TextStyle(color: SaklazColors.textSecondary)),
                ),
              const SizedBox(height: 24),
              const Center(child: SaklazWordmark(height: 22)),
              const SizedBox(height: 8),
              const Center(child: Text('Sürüm 0.2.0 · Phase 2', style: TextStyle(color: SaklazColors.textSecondary))),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalAiCard extends ConsumerWidget {
  const _LocalAiCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final info = ref.watch(localAiProvider);
    final cap = ref.watch(deviceCapabilityProvider);

    final status = info.when(
      data: (i) => switch (i.state) {
        LocalLlmState.ready => 'Gemini Nano hazır${i.modelName == null ? '' : ' (${i.modelName})'}',
        LocalLlmState.downloadable => 'Gemini Nano bu cihazda destekleniyor, indirilmemiş',
        LocalLlmState.downloading => 'Gemini Nano indiriliyor…',
        LocalLlmState.unavailable => 'Gemini Nano bu cihazda kullanılamıyor',
        LocalLlmState.error => 'Hata: ${i.detail ?? '-'}',
      },
      loading: () => 'Kontrol ediliyor…',
      error: (e, _) => 'Okunamadı',
    );

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Cihaz içi dil modelini kullan'),
          subtitle: Text('$status\nTürkçe kalitesi deneyseldir; cihazda test edilmelidir.'),
          isThreeLine: true,
          value: s.useLocalLlm,
          onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(useLocalLlm: v)),
        ),
        ListTile(
          leading: const Icon(Icons.developer_board),
          title: const Text('Cihaz kapasitesi'),
          subtitle: Text(cap.when(
            data: (c) => c == null
                ? 'Bu platformda ölçülemiyor'
                : '${c.soc} · RAM ${(c.totalRamMb / 1024).toStringAsFixed(1)} GB (boş ${(c.availableRamMb / 1024).toStringAsFixed(1)} GB)\n'
                    'Gemini Nano sistemde (AICore) çalışır, uygulama belleğine yüklenmez. '
                    '${c.canHostOwnSmallModel ? 'Ayrı ~1 GB\'lık küçük model de kaldırabilir (bu sürümde yüklenmedi).' : 'Ayrı bir model yüklemek bu cihazı zorlar; yüklenmeyecek.'}',
            loading: () => 'Ölçülüyor…',
            error: (e, _) => 'Ölçülemedi',
          )),
          isThreeLine: true,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            OutlinedButton.icon(
              onPressed: () => unawaited(ref.read(localAiProvider.notifier).refresh()),
              icon: const Icon(Icons.refresh),
              label: const Text('Yeniden kontrol et'),
            ),
            const SizedBox(width: 8),
            if (info.value?.state == LocalLlmState.downloadable)
              FilledButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Yerel model indirilsin mi?'),
                      content: const Text('Gemini Nano sistem tarafından (Google AICore) indirilir. '
                          'Boyutu cihaz ve sürüme göre değişir; Wi-Fi önerilir.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('İndir')),
                      ],
                    ),
                  );
                  if (ok ?? false) await ref.read(localAiProvider.notifier).download();
                },
                icon: const Icon(Icons.download),
                label: const Text('Modeli indir'),
              ),
          ]),
        ),
      ],
    );
  }
}

class _CloudSettings extends ConsumerStatefulWidget {
  const _CloudSettings();
  @override
  ConsumerState<_CloudSettings> createState() => _CloudSettingsState();
}

class _CloudSettingsState extends ConsumerState<_CloudSettings> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final TextEditingController _model;
  String? _testResult;
  bool _testOk = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _url = TextEditingController(text: s.gatewayUrl);
    _token = TextEditingController(text: s.gatewayToken);
    _model = TextEditingController(text: s.cloudModel);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _model.dispose();
    super.dispose();
  }

  void _save() => ref.read(settingsProvider.notifier).update(
        (x) => x.copyWith(gatewayUrl: _url.text.trim(), gatewayToken: _token.text.trim(), cloudModel: _model.text.trim()),
      );

  /// GERÇEK bağlantı testi: /health ve kimlik doğrulamalı /v1/status.
  /// OpenAI'a istek göndermez (ücretsiz). Başarı yalnızca sunucu yanıt verirse gösterilir.
  Future<void> _test() async {
    _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final client = ref.read(gatewayClientProvider);
    String result;
    var ok = false;
    if (client == null) {
      result = 'Adres ve token (en az 16 karakter) gerekli.';
    } else {
      final health = await client.health();
      if (!health.isOk) {
        result = health.failureOrNull!.message;
      } else {
        final st = await client.status();
        result = st.fold(
          (v) {
            ok = v.upstreamConfigured;
            return 'Gateway ${health.valueOrNull} erişilebilir, token geçerli.\n'
                'Model: ${v.defaultModel} · Bugün ${v.requestsToday}/${v.dailyRequestLimit} istek · '
                '\$${v.costTodayUsd.toStringAsFixed(4)} / \$${v.dailyBudgetUsd.toStringAsFixed(2)}\n'
                '${v.upstreamConfigured ? 'OpenAI anahtarı sunucuda tanımlı.' : 'UYARI: Sunucuda OpenAI anahtarı tanımlı DEĞİL.'}';
          },
          (f) => f.message,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
      _testOk = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final https = s.gatewayConfig.isHttps || s.gatewayUrl.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Buluta ne zaman gönderilsin?', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<CloudMode>(
            segments: const [
              ButtonSegment(value: CloudMode.off, label: Text('Asla'), icon: Icon(Icons.cloud_off)),
              ButtonSegment(value: CloudMode.ask, label: Text('Her seferinde sor'), icon: Icon(Icons.help_outline)),
              ButtonSegment(value: CloudMode.always, label: Text('Sormadan'), icon: Icon(Icons.cloud_done_outlined)),
            ],
            selected: {s.cloudMode},
            onSelectionChanged: (v) => ctrl.update((x) => x.copyWith(cloudMode: v.first)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Gateway adresi', hintText: 'https://saklaz-gateway.ornek.com'),
            onEditingComplete: _save,
          ),
          if (!https)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 8),
              child: Text('HTTP yalnızca geliştirme (debug) sürümünde çalışır; yayın sürümü HTTPS ister.',
                  style: TextStyle(color: SaklazColors.warning, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Cihaz tokenı',
              helperText: 'Gateway\'in ürettiği token. OpenAI anahtarı DEĞİLDİR; şifreli hafızada saklanır.',
            ),
            onEditingComplete: _save,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            decoration: const InputDecoration(labelText: 'Model (boş = gateway varsayılanı)'),
            onEditingComplete: _save,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('İlgili kişisel bilgileri bağlam olarak gönder'),
            subtitle: const Text('Kapalıyken hafızandaki bilgiler buluta hiç gönderilmez.'),
            value: s.shareFactsWithCloud,
            onChanged: (v) => ctrl.update((x) => x.copyWith(shareFactsWithCloud: v)),
          ),
          const SizedBox(height: 4),
          Row(children: [
            FilledButton.icon(
              onPressed: _testing ? null : () => unawaited(_test()),
              icon: _testing
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_check),
              label: const Text('Kaydet ve bağlantıyı test et'),
            ),
          ]),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_testResult!, style: TextStyle(color: _testOk ? SaklazColors.listening : SaklazColors.warning, height: 1.4)),
            ),
        ],
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
