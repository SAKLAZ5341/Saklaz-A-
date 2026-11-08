import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';

import '../../application/local_ai_controller.dart';
import '../../application/model_catalog.dart';
import '../../application/settings_controller.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/common.dart';

/// Model Yönetimi: indirme (bütünlük doğrulamalı), yükleme, silme, bellek.
class ModelScreen extends ConsumerWidget {
  const ModelScreen({super.key});
  static const route = '/models';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(localAiProvider);
    final ctrl = ref.read(localAiProvider.notifier);
    final s = ref.watch(settingsProvider);
    final cap = ai.capability;

    final (status, color) = switch (ai.llm.state) {
      LocalLlmState.ready => ('Hazır — ${ai.llm.modelName} (${ai.llm.backend ?? '?'}${ai.llm.detail == null ? '' : ', ${ai.llm.detail}'})', SaklazColors.listening),
      LocalLlmState.loading => ('Yükleniyor: ${ai.llm.modelName ?? ''}', SaklazColors.cyan),
      LocalLlmState.notLoaded => ('Model belleğe yüklü değil', SaklazColors.warning),
      LocalLlmState.noModel => ('Henüz model indirilmedi. Yerel AI için aşağıdan bir model indir.', SaklazColors.warning),
      LocalLlmState.failed => ('Yüklenemedi: ${ai.llm.detail ?? ''}', SaklazColors.danger),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Yönetimi'),
        actions: [IconButton(tooltip: 'Yenile', onPressed: () => unawaited(ctrl.refresh()), icon: const Icon(Icons.refresh))],
      ),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.psychology, color: color),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Yerel AI motoru: LiteRT-LM', style: TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                  const SizedBox(height: 8),
                  Text(status, style: TextStyle(color: color)),
                  if (cap != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${cap.soc.isEmpty ? 'Cihaz' : cap.soc} · RAM ${(cap.totalRamMb / 1024).toStringAsFixed(1)} GB '
                      '(boş ${(cap.availableRamMb / 1024).toStringAsFixed(1)} GB) · Boş depolama ${(cap.freeStorageMb / 1024).toStringAsFixed(1)} GB',
                      style: const TextStyle(color: SaklazColors.textSecondary),
                    ),
                  ],
                  if (ai.ready)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => unawaited(ctrl.unload()),
                        icon: const Icon(Icons.eject),
                        label: const Text('Belleği boşalt'),
                      ),
                    ),
                ]),
              ),
            ),
            SwitchListTile(
              title: const Text('GPU hızlandırma'),
              subtitle: const Text('Önce GPU denenir; desteklenmezse CPU kullanılır. Değişiklik bir sonraki yüklemede geçerli.'),
              value: s.preferGpu,
              onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(preferGpu: v)),
            ),
            const SectionTitle('İndirilebilir modeller'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Modeller APK\'da yoktur; yalnızca istediğinde Hugging Face\'ten (HTTPS) indirilir, SHA-256 ile doğrulanır '
                've telefonda saklanır. Wi-Fi önerilir. İndirme kesilirse kaldığı yerden devam eder.',
                style: TextStyle(color: SaklazColors.textSecondary, height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            for (final m in modelCatalog) _ModelCard(spec: m),
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard({required this.spec});
  final ModelSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(localAiProvider);
    final ctrl = ref.read(localAiProvider.notifier);
    final installed = ai.isInstalled(spec);
    final dl = ai.downloads[spec.id];
    final running = dl != null && (dl.phase == DownloadPhase.running || dl.phase == DownloadPhase.verifying);
    final active = ai.llm.modelName == spec.fileName && ai.ready;
    final loading = ai.llm.modelName == spec.fileName && ai.llm.state == LocalLlmState.loading;
    final cap = ai.capability;
    final lowRam = cap != null && cap.totalRamMb < spec.minRamMb;
    final lowDisk = cap != null && cap.freeStorageMb * 1024 * 1024 < spec.sizeBytes + 300 * 1024 * 1024;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: active ? SaklazColors.listening : SaklazColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(spec.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            if (active) const StatusPill(icon: Icons.check_circle, label: 'Kullanımda', color: SaklazColors.listening),
          ]),
          const SizedBox(height: 6),
          Text(spec.description, style: const TextStyle(color: SaklazColors.textSecondary)),
          const SizedBox(height: 6),
          Text('${spec.sizeLabel} · Lisans: ${spec.license} · ${spec.licenseUrl}', style: const TextStyle(color: SaklazColors.textSecondary, fontSize: 12)),
          if (lowRam)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Bu cihazın RAM\'i bu model için düşük; telefonu zorlayabilir.', style: TextStyle(color: SaklazColors.warning)),
            ),
          if (dl?.phase == DownloadPhase.failed)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(dl!.error ?? 'İndirme başarısız', style: const TextStyle(color: SaklazColors.danger))),
          if (running) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: dl.phase == DownloadPhase.verifying ? null : dl.fraction),
            const SizedBox(height: 4),
            Text(
              dl.phase == DownloadPhase.verifying
                  ? 'Bütünlük doğrulanıyor (SHA-256)…'
                  : '${(dl.received / 1e6).round()} / ${(dl.total / 1e6).round()} MB (%${(dl.fraction * 100).round()})',
              style: const TextStyle(color: SaklazColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!installed && !running)
              FilledButton.icon(
                onPressed: lowDisk
                    ? null
                    : () async {
                        final ok = await confirmDialog(context, '${spec.name} indirilsin mi?',
                            '${spec.sizeLabel} indirilecek (Hugging Face, HTTPS). Mobil veri kullanıyorsan ücret doğabilir.\nLisans: ${spec.license}.',
                            action: 'İndir');
                        if (ok) await ctrl.download(spec);
                      },
                icon: const Icon(Icons.download),
                label: Text(lowDisk ? 'Yetersiz depolama' : 'İndir'),
              ),
            if (running) OutlinedButton.icon(onPressed: () => unawaited(ctrl.cancel(spec)), icon: const Icon(Icons.close), label: const Text('Durdur')),
            if (installed && !active)
              FilledButton.icon(
                onPressed: loading ? null : () => unawaited(ctrl.load(spec)),
                icon: loading ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
                label: Text(loading ? 'Yükleniyor…' : 'Yükle ve kullan'),
              ),
            if (installed)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: SaklazColors.danger),
                onPressed: () async {
                  if (await confirmDialog(context, 'Model silinsin mi?', '${spec.name} telefondan silinecek (${spec.sizeLabel}).', action: 'Sil', destructive: true)) {
                    await ctrl.delete(spec);
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Sil'),
              ),
          ]),
        ]),
      ),
    );
  }
}
