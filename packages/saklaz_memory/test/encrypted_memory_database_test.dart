import 'dart:io';
import 'dart:convert';

import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';
import 'package:test/test.dart';

const keyA = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const keyB = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('saklaz_mem_');
    path = '${dir.path}${Platform.pathSeparator}memory.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ChatMessage msg(String id, String text) => ChatMessage(
        id: id,
        role: ChatRole.user,
        text: text,
        createdAt: DateTime(2026, 11, 8, 10),
        source: MessageSource.user,
      );

  test('SQLite3MultipleCiphers yüklü ve sürüm bildiriyor', () {
    final db = EncryptedMemoryDatabase.open(path, hexKey: keyA);
    expect(db.cipherVersion, contains('Multiple Ciphers'));
    db.close();
  });

  test('veriler kalıcı; doğru anahtarla geri okunur', () async {
    var db = EncryptedMemoryDatabase.open(path, hexKey: keyA);
    await db.add(msg('1', 'Merhaba SAKLAZ'));
    await db.facts.add('Doğum günüm 12 Mart');
    await db.write('voiceReplies', 'false');
    db.close();

    db = EncryptedMemoryDatabase.open(path, hexKey: keyA);
    expect((await db.all()).single.text, 'Merhaba SAKLAZ');
    expect((await db.facts.all()).single.text, 'Doğum günüm 12 Mart');
    expect(await db.readAll(), {'voiceReplies': 'false'});
    db.close();
  });

  test('dosyada düz metin YOK (şifreleme gerçekten uygulanıyor)', () async {
    final db = EncryptedMemoryDatabase.open(path, hexKey: keyA);
    await db.facts.add('GIZLI_BILGI_ARANACAK_DIZE');
    await db.add(msg('1', 'GIZLI_MESAJ_ARANACAK_DIZE'));
    db.close();
    final raw = latin1.decode(File(path).readAsBytesSync());
    expect(raw.contains('GIZLI_BILGI'), isFalse);
    expect(raw.contains('GIZLI_MESAJ'), isFalse);
    expect(raw.contains('CREATE TABLE'), isFalse);
    expect(raw.startsWith('SQLite format 3'), isFalse);
  });

  test('yanlış anahtarla açılmaz (fail-closed)', () async {
    final db = EncryptedMemoryDatabase.open(path, hexKey: keyA);
    await db.add(msg('1', 'x'));
    db.close();
    expect(
      () => EncryptedMemoryDatabase.open(path, hexKey: keyB),
      throwsA(isA<MemoryEncryptionUnavailable>().having((e) => e.reason, 'reason', contains('Anahtar'))),
    );
  });

  test('geçersiz anahtar biçimi reddedilir', () {
    expect(() => EncryptedMemoryDatabase.open(path, hexKey: 'kisa'), throwsArgumentError);
  });

  test('bilgi silme ve tercih silme', () async {
    final db = EncryptedMemoryDatabase.open(path, hexKey: keyA);
    final a = await db.facts.add('bir');
    await db.facts.add('iki');
    await db.facts.delete(a.id);
    expect((await db.facts.all()).map((f) => f.text), ['iki']);
    await db.facts.clear();
    expect(await db.facts.all(), isEmpty);
    await db.write('k', 'v');
    await db.write('k', null);
    expect(await db.readAll(), isEmpty);
    await db.add(msg('1', 'a'));
    await db.clear();
    expect(await db.all(), isEmpty);
    db.close();
  });
}
