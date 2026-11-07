import 'package:saklaz_memory/saklaz_memory.dart';
import 'package:test/test.dart';

void main() {
  final facts = [
    MemoryFact(id: 1, text: 'Doğum günüm 12 Mart', createdAt: DateTime(2026)),
    MemoryFact(id: 2, text: 'Arabamın plakası 34 ABC 123', createdAt: DateTime(2026)),
    MemoryFact(id: 3, text: 'En sevdiğim renk lacivert', createdAt: DateTime(2026)),
  ];
  const s = MemorySearch();

  test('anahtar kelimeyle bulur (Türkçe karakterden bağımsız)', () {
    expect(s.search('doğum günüm ne zaman', facts).first.id, 1);
    expect(s.search('PLAKASI neydi', facts).first.id, 2);
  });

  test('kök eşleşmesi: arabam -> arabamın', () {
    expect(s.search('arabam', facts).first.id, 2);
  });

  test('ilgisiz sorguda boş döner', () {
    expect(s.search('hava durumu', facts), isEmpty);
    expect(s.search('ne', facts), isEmpty);
  });
}
