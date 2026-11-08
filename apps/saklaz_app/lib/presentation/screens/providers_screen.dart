import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';

import '../../application/assistant_provider.dart';
import '../../application/settings_controller.dart';
import '../../infrastructure/providers.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/common.dart';

final _hasKeyProvider = FutureProvider.autoDispose.family<bool, ProviderKind>(
  (ref, k) => ref.watch(secretStoreProvider).has(k.secretName),
);

/// API Sağlayıcıları. HEPSİ varsayılan olarak pasif; anahtarlar Keystore'da şifreli.
class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});
  static const route = '/providers';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Sağlayıcıları')),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'SAKLAZ API anahtarı olmadan, tamamen yerel çalışır. Bulut sağlayıcıları isteğe bağlıdır ve varsayılan olarak kapalıdır.\n\n'
                  '• Ücretler sağlayıcıya göre SANA aittir; SAKLAZ ücretsiz kullanım veya abonelik sağlamaz.\n'
                  '• Bir sağlayıcıyı etkinleştirmek veri göndermez; ayrıca Yapay Zekâ Ayarları\'ndan "aktif zekâ" olarak seçmen gerekir.\n'
                  '• Kişisel hafızan buluta gönderilmez (ayrı bir izinle açılmadıkça).\n'
                  '• API anahtarları Android Keystore ile şifrelenip yalnızca bu telefonda saklanır.',
                  style: TextStyle(color: SaklazColors.textSecondary, height: 1.45),
                ),
              ),
            ),
            for (final k in ProviderKind.values) _ProviderCard(kind: k),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends ConsumerStatefulWidget {
  const _ProviderCard({required this.kind});
  final ProviderKind kind;
  @override
  ConsumerState<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends ConsumerState<_ProviderCard> {
  late final TextEditingController _url;
  late final TextEditingController _model;
  final _key = TextEditingController();
  String? _result;
  bool _ok = false;
  bool _testing = false;

  ProviderKind get k => widget.kind;

  @override
  void initState() {
    super.initState();
    final p = ref.read(settingsProvider).provider(k);
    _url = TextEditingController(text: p.baseUrl);
    _model = TextEditingController(text: p.model);
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = ref.read(settingsProvider).provider(k);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(providerUpdate: p.copyWith(baseUrl: _url.text.trim(), model: _model.text.trim())));
    if (_key.text.trim().isNotEmpty) {
      await ref.read(secretStoreProvider).put(k.secretName, _key.text.trim());
      _key.clear();
      ref.invalidate(_hasKeyProvider(k));
    }
    ref.invalidate(activeCloudClientProvider);
  }

  /// GERÇEK bağlantı testi. Kullanıcı düğmeye bastığında yapılır; otomatik değil.
  Future<void> _test() async {
    await _save();
    setState(() {
      _testing = true;
      _result = null;
    });
    final p = ref.read(settingsProvider).provider(k);
    final key = await ref.read(secretStoreProvider).get(k.secretName) ?? '';
    final transport = ref.read(httpTransportProvider);
    String msg;
    var ok = false;
    if (k == ProviderKind.gateway) {
      final c = GatewayClient(GatewayConfig(baseUrl: p.effectiveBaseUrl, deviceToken: key), transport);
      final st = await c.status();
      msg = st.fold((v) {
        ok = v.upstreamConfigured;
        return 'Gateway erişilebilir, token geçerli. Model: ${v.defaultModel}. ${v.upstreamConfigured ? '' : 'UYARI: Sunucuda OpenAI anahtarı yok.'}';
      }, (f) => f.message);
    } else {
      final r = await testProviderConnection(baseUrl: p.effectiveBaseUrl, apiKey: key, transport: transport);
      ok = r.isOk;
      msg = r.fold((v) => v, (f) => f.message);
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = msg;
      _ok = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(settingsProvider.select((s) => s.provider(k)));
    final hasKey = ref.watch(_hasKeyProvider(k)).value ?? false;
    final keyLabel = k == ProviderKind.gateway ? 'Cihaz tokenı' : 'API anahtarı';

    return Card(
      child: ExpansionTile(
        title: Text(k.label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${p.enabled ? 'Etkin' : 'Pasif'} · ${hasKey ? '$keyLabel kayıtlı' : '$keyLabel yok'}',
          style: TextStyle(color: p.enabled ? SaklazColors.magenta : SaklazColors.textSecondary),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Etkinleştir'),
            subtitle: const Text('Etkin olsa bile yalnızca "aktif zekâ" seçilirse ve izin verirsen kullanılır.'),
            value: p.enabled,
            onChanged: (v) {
              ref.read(settingsProvider.notifier).update((s) => s.copyWith(
                    providerUpdate: p.copyWith(enabled: v),
                    clearActiveProvider: !v && s.activeProvider == k,
                  ));
              ref.invalidate(activeCloudClientProvider);
            },
          ),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: 'API Base URL', hintText: k.defaultBaseUrl.isEmpty ? 'https://...' : k.defaultBaseUrl),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _model,
            decoration: InputDecoration(
              labelText: 'Model adı',
              hintText: k.defaultModel.isEmpty ? 'Sağlayıcının güncel model adını gir' : k.defaultModel,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _key,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: hasKey ? '$keyLabel (kayıtlı — değiştirmek için yeni gir)' : keyLabel,
              helperText: 'Keystore ile şifrelenir; loglara ve yedeklere yazılmaz.',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () => unawaited(_save()), icon: const Icon(Icons.save_outlined), label: const Text('Kaydet')),
            OutlinedButton.icon(
              onPressed: _testing ? null : () => unawaited(_test()),
              icon: _testing ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check),
              label: const Text('Bağlantıyı test et'),
            ),
            if (hasKey)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: SaklazColors.danger),
                onPressed: () async {
                  await ref.read(secretStoreProvider).delete(k.secretName);
                  ref.invalidate(_hasKeyProvider(k));
                  ref.invalidate(activeCloudClientProvider);
                },
                child: Text('$keyLabel sil'),
              ),
          ]),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_result!, style: TextStyle(color: _ok ? SaklazColors.listening : SaklazColors.warning)),
            ),
        ],
      ),
    );
  }
}
