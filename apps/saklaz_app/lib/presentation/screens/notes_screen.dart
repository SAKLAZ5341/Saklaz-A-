import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';

import '../../infrastructure/providers.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/common.dart';

final _notesVersion = StateProvider<int>((ref) => 0);
final _notesProvider = FutureProvider.autoDispose<List<Note>>((ref) {
  ref.watch(_notesVersion);
  return ref.watch(memoryProvider).notes.all();
});
final _remindersProvider = FutureProvider.autoDispose<List<Reminder>>((ref) {
  ref.watch(_notesVersion);
  return ref.watch(memoryProvider).reminders.all();
});

/// Notlar ve hatırlatmalar (şifreli hafızada; hatırlatmalar sistem alarmıyla bildirilir).
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});
  static const route = '/notes';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(_notesProvider);
    final reminders = ref.watch(_remindersProvider);
    final now = DateTime.now();
    void bump() => ref.read(_notesVersion.notifier).state++;

    return Scaffold(
      appBar: AppBar(title: const Text('Notlar ve Hatırlatmalar')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Not ekle'),
        onPressed: () async {
          final t = await textDialog(context, 'Yeni not');
          if (t == null || t.isEmpty) return;
          await ref.read(memoryProvider).notes.add(t);
          bump();
        },
      ),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            const SectionTitle('Hatırlatmalar'),
            const Text('Sesle ekle: "Yarın sabah 9\'da toplantıyı hatırlat"', style: TextStyle(color: SaklazColors.textSecondary)),
            reminders.when(
              data: (list) => list.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('Hatırlatma yok.', style: TextStyle(color: SaklazColors.textSecondary)))
                  : Column(children: [
                      for (final r in list)
                        Card(
                          child: ListTile(
                            leading: Icon(r.done || r.dueAt.isBefore(now) ? Icons.alarm_off : Icons.alarm,
                                color: r.done || r.dueAt.isBefore(now) ? SaklazColors.textSecondary : SaklazColors.cyan),
                            title: Text(r.text),
                            subtitle: Text(TurkishTime.format(r.dueAt, now)),
                            trailing: IconButton(
                              tooltip: 'Sil',
                              icon: const Icon(Icons.delete_outline, color: SaklazColors.danger),
                              onPressed: () async {
                                await ref.read(devicePortsProvider).cancelReminder(r.id);
                                await ref.read(memoryProvider).reminders.delete(r.id);
                                bump();
                              },
                            ),
                          ),
                        ),
                    ]),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
            ),
            const SectionTitle('Notlar'),
            notes.when(
              data: (list) => list.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('Not yok. "Not al: ..." diyebilirsin.', style: TextStyle(color: SaklazColors.textSecondary)))
                  : Column(children: [
                      for (final n in list)
                        Card(
                          child: ListTile(
                            title: Text(n.text),
                            subtitle: Text(TurkishTime.format(n.createdAt, now)),
                            trailing: IconButton(
                              tooltip: 'Sil',
                              icon: const Icon(Icons.delete_outline, color: SaklazColors.danger),
                              onPressed: () async {
                                if (!await confirmDialog(context, 'Not silinsin mi?', n.text, action: 'Sil', destructive: true)) return;
                                await ref.read(memoryProvider).notes.delete(n.id);
                                bump();
                              },
                            ),
                          ),
                        ),
                    ]),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
            ),
          ],
        ),
      ),
    );
  }
}
