import 'dart:io';

import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const key = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('saklaz_v2_');
    path = '${dir.path}${Platform.pathSeparator}m.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // Aynı senaryolar hem şifreli SQLite hem bellek içi depo için çalışır.
  for (final kind in ['sqlite3mc', 'bellek']) {
    group('FactRepository ($kind)', () {
      late FactRepository facts;
      EncryptedMemoryDatabase? db;

      setUp(() {
        if (kind == 'sqlite3mc') {
          db = EncryptedMemoryDatabase.open(path, hexKey: key);
          facts = db!.facts;
        } else {
          facts = InMemoryFactRepository();
        }
      });
      tearDown(() => db?.close());

      test('aynı bilgi tekrar eklenmez (yinelenme)', () async {
        await facts.upsert(FactCategory.project, 'ASEDEN ERP');
        final r = await facts.upsert(FactCategory.project, 'aseden erp');
        expect(r.outcome, UpsertOutcome.duplicate);
        expect(await facts.all(), hasLength(1));
      });

      test('tek değerli kategoride çelişki: yeni bilgi güncel, eski arşivde', () async {
        await facts.upsert(FactCategory.profession, 'muhasebeci', source: FactSource.auto);
        final r = await facts.upsert(FactCategory.profession, 'satınalma yöneticisi', source: FactSource.auto);
        expect(r.outcome, UpsertOutcome.replaced);
        expect(r.replaced.single.text, 'muhasebeci');
        final active = await facts.all();
        expect(active.single.text, 'satınalma yöneticisi');
        final everything = await facts.all(includeArchived: true);
        expect(everything.where((f) => !f.isActive).single.text, 'muhasebeci');
      });

      test('çok değerli kategoride birden fazla bilgi tutulur', () async {
        await facts.upsert(FactCategory.project, 'ASEDEN ERP');
        await facts.upsert(FactCategory.project, 'Depo otomasyonu');
        expect((await facts.all()).map((f) => f.text), containsAll(['ASEDEN ERP', 'Depo otomasyonu']));
      });

      test('arama: Türkçe ek ve kategori adı ile bulur', () async {
        await facts.upsert(FactCategory.project, 'ASEDEN ERP');
        await facts.upsert(FactCategory.profession, 'satınalma yöneticisi');
        await facts.upsert(FactCategory.preference, 'en sevdiği renk lacivert');
        expect((await facts.search('projelerim neler')).first.text, 'ASEDEN ERP');
        expect((await facts.search('mesleğim ne')).first.text, 'satınalma yöneticisi');
        expect((await facts.search('lacivert')).first.category, FactCategory.preference);
      });

      test('düzenleme ve silme', () async {
        final f = (await facts.upsert(FactCategory.interest, 'satranç')).fact;
        await facts.update(f.id, 'satranç ve go');
        expect((await facts.all()).single.text, 'satranç ve go');
        expect((await facts.search('go')).single.id, f.id);
        await facts.delete(f.id);
        expect(await facts.all(), isEmpty);
        expect(await facts.search('satranç'), isEmpty);
      });
    });
  }

  test('geçmiş konuşma araması (FTS5)', () async {
    final db = EncryptedMemoryDatabase.open(path, hexKey: key);
    await db.add(ChatMessage(id: '1', role: ChatRole.user, text: 'Yarınki tedarikçi toplantısı', createdAt: DateTime(2026, 1, 1)));
    await db.add(ChatMessage(id: '2', role: ChatRole.user, text: 'Hava nasıl', createdAt: DateTime(2026, 1, 2)));
    expect((await db.search('tedarikçi')).single.id, '1');
    expect((await db.search('toplantılar')).single.id, '1');
    db.close();
  });

  test('notlar ve hatırlatıcılar kalıcı', () async {
    var db = EncryptedMemoryDatabase.open(path, hexKey: key);
    await db.notes.add('Süt al');
    await db.reminders.add('İlaç', DateTime.now().add(const Duration(hours: 1)));
    db.close();
    db = EncryptedMemoryDatabase.open(path, hexKey: key);
    expect((await db.notes.all()).single.text, 'Süt al');
    expect((await db.reminders.upcoming(DateTime.now())).single.text, 'İlaç');
    db.close();
  });

  test('v1 veritabanı kayıpsız v2\'ye taşınır', () async {
    // v1 şemasını elle oluştur (Phase 2 sürümü).
    final raw = sqlite3.open(path)
      ..execute("PRAGMA cipher = 'chacha20';")
      ..execute("PRAGMA hexkey = '$key';")
      ..execute('''
        CREATE TABLE messages (id TEXT PRIMARY KEY, role TEXT NOT NULL, source TEXT NOT NULL, text TEXT NOT NULL, created_at INTEGER NOT NULL);
        CREATE TABLE facts (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, created_at INTEGER NOT NULL);
        CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO facts (text, created_at) VALUES ('Doğum günüm 12 Mart', 1000);
        INSERT INTO messages VALUES ('m1', 'user', 'user', 'Eski mesaj', 1000);
      ''')
      ..userVersion = 1;
    raw.close();
    final db = EncryptedMemoryDatabase.open(path, hexKey: key);
    final f = (await db.facts.all()).single;
    expect(f.text, 'Doğum günüm 12 Mart');
    expect(f.category, FactCategory.other);
    expect((await db.facts.search('doğum günüm')).single.id, f.id);
    expect((await db.search('eski')).single.id, 'm1');
    db.close();
  });
}
