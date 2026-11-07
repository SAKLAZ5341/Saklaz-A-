import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:test/test.dart';

void main() {
  final brain = OfflinePlaceholderBrain(clock: () => DateTime(2026, 11, 7, 9, 5));

  Future<String> ask(String s) async => (await brain.reply(s, const [])).valueOrNull!;

  test('Türkçe karakterleri sadeleştirir', () {
    expect(OfflinePlaceholderBrain.normalize('SAAT KAÇ?  Şimdi!'), 'saat kac simdi');
    expect(OfflinePlaceholderBrain.normalize('Günaydın'), 'gunaydin');
  });

  test('selamlaşmaya yanıt verir', () async {
    expect(await ask('Merhaba SAKLAZ'), contains('SAKLAZ'));
  });

  test('saati yerel saatten söyler', () async {
    expect(await ask('Saat kaç?'), 'Saat şu an 09:05.');
  });

  test('tarihi Türkçe söyler', () async {
    expect(await ask('Bugün günlerden ne?'), 'Bugün 7 Kasım 2026, Cumartesi.');
  });

  test('bilinmeyen isteklerde AI olmadığını dürüstçe söyler', () async {
    expect(await ask('Yarın hava nasıl olacak'), contains('henüz bağlı değil'));
  });

  test('cihaz üzerinde çalışır', () {
    expect(brain.isOnDevice, isTrue);
  });
}
