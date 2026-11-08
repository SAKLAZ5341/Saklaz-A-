import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';

import '../../application/settings_controller.dart';
import '../../infrastructure/providers.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/common.dart';
import 'chat_history_screen.dart';

final _memoryQueryProvider = StateProvider.autoDispose<String>((ref) => '');
final _showArchivedProvider = StateProvider.autoDispose<bool>((ref) => false);
final _memoryVersionProvider = StateProvider<int>((ref) => 0);

final memoryFactsProvider = FutureProvider.autoDispose<List<MemoryFact>>((ref) async {
  ref.watch(_memoryVersionProvider);
  final facts = ref.watch(memoryProvider).facts;
  final q = ref.watch(_memoryQueryProvider).trim();
  final archived = ref.watch(_showArchivedProvider);
  if (q.isEmpty) return facts.all(includeArchived: archived);
  return facts.search(q, limit: 50);
});

/// "Benim Hafızam": SAKLAZ'ın öğrendikleri. Görüntüle, ara, düzenle, sil. Hepsi cihazda.
class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});
  static const route = '/memory';

  void _bump(WidgetRef ref) => ref.read(_memoryVersionProvider.notifier).state++;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(FactCategory, String)>(context: context, builder: (_) => const _AddFactDialog());
    if (result == null || result.$2.isEmpty) return;
    final (category, text) = result;
    if (SensitiveFilter.isSensitive(text) && context.mounted) {
      final ok = await confirmDialog(context, 'Hassas bilgi olabilir',
          'Bu bir şifre, kart veya kimlik bilgisi gibi görünüyor. Yine de kaydedilsin mi? (Cihazda şifreli saklanır.)',
          action: 'Yine de kaydet');
      if (!ok) return;
    }
    await ref.read(memoryProvider).facts.upsert(category, text);
    _bump(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(memoryProvider);
    final facts = ref.watch(memoryFactsProvider);
    final autoLearn = ref.watch(settingsProvider.select((s) => s.autoLearn));
    final archived = ref.watch(_showArchivedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Benim Hafızam'),
        actions: [
          IconButton(
            tooltip: 'Sohbet geçmişinde ara',
            icon: const Icon(Icons.manage_search),
            onPressed: () => Navigator.pushNamed(context, ChatHistoryScreen.route),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_add(context, ref)),
        icon: const Icon(Icons.add),
        label: const Text('Bilgi ekle'),
      ),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Card(
              child: ListTile(
                leading: Icon(memory.encrypted ? Icons.lock : Icons.lock_open, color: memory.encrypted ? SaklazColors.listening : SaklazColors.warning),
                title: Text(memory.encrypted ? 'Şifreli ve yalnızca bu telefonda' : 'Şifreleme etkin DEĞİL'),
                subtitle: Text(memory.encrypted
                    ? '${memory.cipherVersion ?? ''} · ChaCha20-Poly1305 · Anahtar: ${memory.hardwareBackedKey ? 'donanım destekli Android Keystore' : 'Android Keystore'}\nHafıza internete gönderilmez.'
                    : 'Kayıtlar yalnızca bellekte. Neden: ${memory.error ?? '-'}'),
              ),
            ),
            SwitchListTile(
              title: const Text('Otomatik öğrenme'),
              subtitle: const Text('Konuşmalarından mesleğin, projelerin, ilgi alanların gibi kalıcı bilgileri öğrenir. Şifre, kart, IBAN gibi sırlar asla otomatik kaydedilmez.'),
              value: autoLearn,
              onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(autoLearn: v)),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Hafızada ara (ör. proje, meslek)'),
              onChanged: (v) => ref.read(_memoryQueryProvider.notifier).state = v,
            ),
            Wrap(children: [
              FilterChip(
                label: const Text('Eski (değişmiş) bilgileri göster'),
                selected: archived,
                onSelected: (v) => ref.read(_showArchivedProvider.notifier).state = v,
              ),
            ]),
            const SizedBox(height: 8),
            facts.when(
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text('Henüz kayıtlı bilgi yok.\nBenimle kendinden bahsederek konuş; seni tanıyacağım.',
                            textAlign: TextAlign.center, style: TextStyle(color: SaklazColors.textSecondary)),
                      ),
                    )
                  : Column(children: [for (final f in list) _FactTile(fact: f, onChanged: () => _bump(ref))]),
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('Okunamadı: $e', style: const TextStyle(color: SaklazColors.danger)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: SaklazColors.danger),
              onPressed: () async {
                if (!await confirmDialog(context, 'Tüm hafıza silinsin mi?',
                    'SAKLAZ\'ın senin hakkında öğrendiği tüm bilgiler kalıcı olarak silinecek. Bu işlem geri alınamaz.',
                    action: 'Hepsini sil', destructive: true)) {
                  return;
                }
                await ref.read(memoryProvider).facts.clear();
                _bump(ref);
              },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Bütün hafızayı temizle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactTile extends ConsumerWidget {
  const _FactTile({required this.fact, required this.onChanged});
  final MemoryFact fact;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(memoryProvider).facts;
    final d = fact.updatedAt;
    final date = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (fact.isActive ? SaklazColors.cyan : SaklazColors.textSecondary).withValues(alpha: 0.15),
          child: Icon(fact.source == FactSource.auto ? Icons.auto_awesome : Icons.edit_note,
              size: 18, color: fact.isActive ? SaklazColors.cyan : SaklazColors.textSecondary),
        ),
        title: Text(fact.text, style: TextStyle(decoration: fact.isActive ? null : TextDecoration.lineThrough)),
        subtitle: Text(
          '${fact.category.label} · ${fact.source == FactSource.auto ? 'otomatik öğrenildi' : 'elle eklendi'} · $date${fact.isActive ? '' : ' · ESKİ'}',
          style: const TextStyle(color: SaklazColors.textSecondary, fontSize: 12),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Düzenle',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final t = await textDialog(context, 'Bilgiyi düzenle', initial: fact.text);
              if (t == null || t.isEmpty) return;
              await repo.update(fact.id, t);
              onChanged();
            },
          ),
          IconButton(
            tooltip: 'Sil',
            icon: const Icon(Icons.delete_outline, color: SaklazColors.danger),
            onPressed: () async {
              if (!await confirmDialog(context, 'Bilgi silinsin mi?', fact.text, action: 'Sil', destructive: true)) return;
              await repo.delete(fact.id);
              onChanged();
            },
          ),
        ]),
      ),
    );
  }
}

/// Denetleyici diyaloğun yaşam döngüsünde imha edilir (kapanış animasyonu güvenli).
class _AddFactDialog extends StatefulWidget {
  const _AddFactDialog();
  @override
  State<_AddFactDialog> createState() => _AddFactDialogState();
}

class _AddFactDialogState extends State<_AddFactDialog> {
  final _ctrl = TextEditingController();
  var _category = FactCategory.other;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Hafızaya bilgi ekle'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<FactCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Kategori'),
            items: [for (final f in FactCategory.values) DropdownMenuItem(value: f, child: Text(f.label))],
            onChanged: (v) => setState(() => _category = v ?? FactCategory.other),
          ),
          const SizedBox(height: 12),
          TextField(controller: _ctrl, autofocus: true, maxLength: 300, decoration: const InputDecoration(hintText: 'Örn: ASEDEN ERP')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, (_category, _ctrl.text.trim())), child: const Text('Kaydet')),
        ],
      );
}
