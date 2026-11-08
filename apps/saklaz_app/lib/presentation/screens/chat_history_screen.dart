import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:saklaz_core/saklaz_core.dart';

import '../../application/conversation_controller.dart';
import '../../infrastructure/providers.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/common.dart';
import '../widgets/conversation_view.dart';

final _historyQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final _historyProvider = FutureProvider.autoDispose<List<ChatMessage>>((ref) async {
  final repo = ref.watch(memoryProvider).conversations;
  ref.watch(conversationProvider.select((c) => c.messages.length));
  final q = ref.watch(_historyQueryProvider).trim();
  if (q.isEmpty) return (await repo.all()).reversed.toList();
  return repo.search(q, limit: 100);
});

/// Sohbet geçmişi ve geçmiş konuşmalarda arama (FTS5, cihazda).
class ChatHistoryScreen extends ConsumerWidget {
  const ChatHistoryScreen({super.key});
  static const route = '/history';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(_historyProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sohbet Geçmişi'),
        actions: [
          IconButton(
            tooltip: 'Geçmişi temizle',
            icon: const Icon(Icons.delete_outline, color: SaklazColors.danger),
            onPressed: () async {
              if (!await confirmDialog(context, 'Sohbet geçmişi silinsin mi?', 'Bu işlem geri alınamaz. Benim Hafızam\'daki bilgiler silinmez.',
                  action: 'Sil', destructive: true)) {
                return;
              }
              await ref.read(conversationProvider.notifier).clearHistory();
            },
          ),
        ],
      ),
      body: ResponsiveBody(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Geçmiş konuşmalarda ara'),
              onChanged: (v) => ref.read(_historyQueryProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: items.when(
              data: (list) => list.isEmpty
                  ? const Center(child: Text('Sonuç yok.', style: TextStyle(color: SaklazColors.textSecondary)))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: SaklazColors.outline),
                      itemBuilder: (_, i) {
                        final m = list[i];
                        final d = m.createdAt;
                        return ListTile(
                          leading: Icon(m.isUser ? Icons.person_outline : Icons.smart_toy_outlined, color: SaklazColors.textSecondary),
                          title: Text(m.text, maxLines: 4, overflow: TextOverflow.ellipsis),
                          subtitle: Row(children: [
                            if (!m.isUser) ...[SourceBadge(source: m.source), const SizedBox(width: 8)],
                            Text('${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
                                '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 12, color: SaklazColors.textSecondary)),
                          ]),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ]),
      ),
    );
  }
}
