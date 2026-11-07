import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_memory/saklaz_memory.dart';

import '../../application/conversation_controller.dart';
import '../../infrastructure/providers.dart';
import '../theme/saklaz_theme.dart';

final factsProvider = FutureProvider.autoDispose<List<MemoryFact>>(
  (ref) => ref.watch(memoryProvider).facts.all(),
);

/// Kişisel hafıza: görüntüleme, onaylı ekleme, silme. Hepsi cihazda.
class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});
  static const route = '/memory';

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hafızaya bilgi ekle'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Örn: En sevdiğim renk lacivert'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Kaydet')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.isEmpty) return;
    await ref.read(memoryProvider).facts.add(text);
    ref.invalidate(factsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(memoryProvider);
    final facts = ref.watch(factsProvider);
    final messageCount = ref.watch(conversationProvider.select((c) => c.messages.length));

    return Scaffold(
      appBar: AppBar(title: const Text('Hafıza')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_add(context, ref)),
        icon: const Icon(Icons.add),
        label: const Text('Bilgi ekle'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(memory.encrypted ? Icons.lock : Icons.lock_open,
                      color: memory.encrypted ? SaklazColors.listening : SaklazColors.warning),
                  title: Text(memory.encrypted ? 'Şifreli ve yalnızca bu cihazda' : 'Şifreleme etkin DEĞİL'),
                  subtitle: Text(memory.encrypted
                      ? '${memory.cipherVersion ?? ''} · ChaCha20-Poly1305 · '
                          'Anahtar: ${memory.hardwareBackedKey ? 'donanım destekli Android Keystore' : 'Android Keystore (yazılım)'}'
                      : 'Kayıtlar yalnızca bellekte; uygulama kapanınca silinir. Neden: ${memory.error ?? '-'}'),
                ),
              ),
              const SizedBox(height: 16),
              const Text('KAYITLI BİLGİLER', style: TextStyle(color: SaklazColors.cyan, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Yalnızca senin onayınla eklenir. Sohbette "Hatırla ki ..." diyebilirsin.',
                style: TextStyle(color: SaklazColors.textSecondary),
              ),
              const SizedBox(height: 8),
              facts.when(
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('Henüz kayıtlı bilgi yok.', style: TextStyle(color: SaklazColors.textSecondary))),
                      )
                    : Column(children: [
                        for (final f in list)
                          Card(
                            child: ListTile(
                              title: Text(f.text),
                              subtitle: Text(_date(f.createdAt), style: const TextStyle(color: SaklazColors.textSecondary)),
                              trailing: IconButton(
                                tooltip: 'Sil',
                                icon: const Icon(Icons.delete_outline, color: SaklazColors.danger),
                                onPressed: () async {
                                  if (!await _confirm(context, 'Bilgi silinsin mi?', f.text, 'Sil')) return;
                                  await ref.read(memoryProvider).facts.delete(f.id);
                                  ref.invalidate(factsProvider);
                                },
                              ),
                            ),
                          ),
                        if (list.length > 1)
                          TextButton.icon(
                            onPressed: () async {
                              if (!await _confirm(context, 'Tüm bilgiler silinsin mi?', '${list.length} kayıt kalıcı olarak silinecek.', 'Hepsini sil')) {
                                return;
                              }
                              await ref.read(memoryProvider).facts.clear();
                              ref.invalidate(factsProvider);
                            },
                            icon: const Icon(Icons.delete_sweep_outlined, color: SaklazColors.danger),
                            label: const Text('Tüm bilgileri sil', style: TextStyle(color: SaklazColors.danger)),
                          ),
                      ]),
                loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text('Okunamadı: $e', style: const TextStyle(color: SaklazColors.danger)),
              ),
              const SizedBox(height: 24),
              const Text('KONUŞMA GEÇMİŞİ', style: TextStyle(color: SaklazColors.cyan, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: Text('$messageCount mesaj'),
                  subtitle: const Text('En fazla ${EncryptedMemoryDatabase.maxMessages} mesaj saklanır; eskiler otomatik silinir.'),
                  trailing: TextButton(
                    onPressed: messageCount == 0
                        ? null
                        : () async {
                            if (!await _confirm(context, 'Konuşma geçmişi silinsin mi?', 'Bu işlem geri alınamaz.', 'Sil')) return;
                            await ref.read(conversationProvider.notifier).clearHistory();
                          },
                    child: const Text('Temizle', style: TextStyle(color: SaklazColors.danger)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
