import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';
import 'package:test/test.dart';

ChatMessage m(int i) => ChatMessage(
      id: '$i',
      role: ChatRole.user,
      text: 'mesaj $i',
      createdAt: DateTime(2026),
    );

void main() {
  test('ekler, sınırlar ve temizler', () async {
    final repo = InMemoryConversationRepository(maxMessages: 3);
    for (var i = 0; i < 5; i++) {
      await repo.add(m(i));
    }
    expect((await repo.all()).map((e) => e.id), ['2', '3', '4']);
    expect(repo.isPersistent, isFalse);
    await repo.clear();
    expect(await repo.all(), isEmpty);
  });
}
