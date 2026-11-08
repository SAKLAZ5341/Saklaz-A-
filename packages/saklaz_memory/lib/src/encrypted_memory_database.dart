import 'package:saklaz_core/saklaz_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'conversation_repository.dart';
import 'fact_repository.dart';
import 'notes_reminders.dart';
import 'preferences_store.dart';

/// Şifreleme doğrulanamadığında fırlatılır. Veritabanı bu durumda AÇILMAZ.
class MemoryEncryptionUnavailable implements Exception {
  MemoryEncryptionUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'MemoryEncryptionUnavailable: $reason';
}

/// SQLite3MultipleCiphers (ChaCha20-Poly1305) ile şifreli tek dosyalık hafıza.
/// FTS5 tam metin arama, Türkçe normalize edilmiş sütunlar üzerinde çalışır.
class EncryptedMemoryDatabase implements ConversationRepository, PreferencesStore {
  EncryptedMemoryDatabase._(this._db, this.cipherVersion);

  final Database _db;
  final String cipherVersion;

  static const schemaVersion = 2;

  static EncryptedMemoryDatabase open(String path, {required String hexKey}) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey)) {
      throw ArgumentError('Anahtar 64 karakter hex olmalı');
    }
    // 1) Şifreleme kütüphanesi kontrolü dosyadan bağımsız (bellek içi bağlantı).
    final probe = sqlite3.openInMemory();
    final version = _cipherVersion(probe);
    probe.close();
    if (version == null) {
      throw MemoryEncryptionUnavailable('Şifreleme destekli SQLite yüklenemedi');
    }
    final db = sqlite3.open(path);
    try {
      // 2) Anahtar, dosyaya yapılan ilk okumadan ÖNCE verilmelidir.
      db.execute("PRAGMA cipher = 'chacha20';");
      db.execute("PRAGMA hexkey = '$hexKey';");
      try {
        db.select('SELECT count(*) FROM sqlite_master;');
      } on SqliteException {
        throw MemoryEncryptionUnavailable('Anahtar geçersiz veya dosya bozuk');
      }
      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('PRAGMA secure_delete = ON;');
      _migrate(db);
      return EncryptedMemoryDatabase._(db, version);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static String? _cipherVersion(Database db) {
    try {
      return db.select('SELECT sqlite3mc_version() AS v;').first['v'] as String?;
    } on SqliteException {
      return null;
    }
  }

  static void _migrate(Database db) {
    final v = db.userVersion;
    if (v < 1) {
      db.execute('''
        CREATE TABLE IF NOT EXISTS messages (
          id TEXT PRIMARY KEY, role TEXT NOT NULL, source TEXT NOT NULL,
          text TEXT NOT NULL, created_at INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS messages_created ON messages(created_at);
        CREATE TABLE IF NOT EXISTS facts (
          id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, created_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      ''');
    }
    if (v < 2) {
      db.execute('''
        ALTER TABLE facts ADD COLUMN category TEXT NOT NULL DEFAULT 'other';
        ALTER TABLE facts ADD COLUMN status TEXT NOT NULL DEFAULT 'active';
        ALTER TABLE facts ADD COLUMN source TEXT NOT NULL DEFAULT 'manual';
        ALTER TABLE facts ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;
        UPDATE facts SET updated_at = created_at WHERE updated_at = 0;
        CREATE VIRTUAL TABLE IF NOT EXISTS facts_fts USING fts5(norm, tokenize = 'unicode61');
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(norm, msg_id UNINDEXED, tokenize = 'unicode61');
        CREATE TABLE IF NOT EXISTS notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, created_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS reminders (
          id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, due_at INTEGER NOT NULL,
          created_at INTEGER NOT NULL, done INTEGER NOT NULL DEFAULT 0);
      ''');
      // Mevcut kayıtları indeksle.
      for (final r in db.select('SELECT id, text FROM facts')) {
        db.execute('INSERT INTO facts_fts(rowid, norm) VALUES (?, ?)', [r['id'], normalizeTr(r['text'] as String)]);
      }
      for (final r in db.select('SELECT id, text FROM messages')) {
        db.execute('INSERT INTO messages_fts(norm, msg_id) VALUES (?, ?)', [normalizeTr(r['text'] as String), r['id']]);
      }
    }
    db.userVersion = schemaVersion;
  }

  void close() => _db.close();

  /// FTS5 sorgusu: normalize anahtar kelimeler, önek eşleşmesi (Türkçe ekler için).
  static String? ftsQuery(String text, {bool all = false}) {
    final words = keywordsTr(text).where((w) => w.length >= 2).toList();
    if (words.isEmpty) return null;
    final terms = words.map((w) {
      // Kök yaklaşımı (Türkçe eklemeli dil): ilk 5 harf önek olarak aranır.
      // projelerim -> proje*, mesleğim -> mesle*, toplantılar -> topla*
      final stem = w.length > 5 ? w.substring(0, 5) : w;
      return '"$stem"*';
    });
    return terms.join(all ? ' AND ' : ' OR ');
  }

  // ---- ConversationRepository ----

  static const maxMessages = 500;

  @override
  bool get isPersistent => true;

  static ChatMessage _msg(Row r) => ChatMessage(
        id: r['id'] as String,
        role: ChatRole.values.byName(r['role'] as String),
        source: MessageSource.values.byName(r['source'] as String),
        text: r['text'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      );

  @override
  Future<List<ChatMessage>> all() async => [
        for (final r in _db.select(
          'SELECT * FROM (SELECT * FROM messages ORDER BY created_at DESC LIMIT ?) ORDER BY created_at ASC',
          [maxMessages],
        ))
          _msg(r),
      ];

  @override
  Future<void> add(ChatMessage m) async {
    _db.execute(
      'INSERT OR REPLACE INTO messages (id, role, source, text, created_at) VALUES (?, ?, ?, ?, ?)',
      [m.id, m.role.name, m.source.name, m.text, m.createdAt.millisecondsSinceEpoch],
    );
    _db.execute('INSERT INTO messages_fts(norm, msg_id) VALUES (?, ?)', [normalizeTr(m.text), m.id]);
    _db.execute(
      'DELETE FROM messages WHERE id NOT IN (SELECT id FROM messages ORDER BY created_at DESC LIMIT ?)',
      [maxMessages],
    );
    _db.execute('DELETE FROM messages_fts WHERE msg_id NOT IN (SELECT id FROM messages)');
  }

  @override
  Future<void> clear() async {
    _db.execute('DELETE FROM messages');
    _db.execute('DELETE FROM messages_fts');
  }

  @override
  Future<List<ChatMessage>> search(String query, {int limit = 30}) async {
    final q = ftsQuery(query, all: true);
    if (q == null) return const [];
    return [
      for (final r in _db.select(
        'SELECT m.* FROM messages_fts f JOIN messages m ON m.id = f.msg_id '
        'WHERE messages_fts MATCH ? ORDER BY m.created_at DESC LIMIT ?',
        [q, limit],
      ))
        _msg(r),
    ];
  }

  late final FactRepository facts = _Facts(_db);
  late final NoteRepository notes = _Notes(_db);
  late final ReminderRepository reminders = _Reminders(_db);

  // ---- PreferencesStore ----

  @override
  Future<Map<String, String>> readAll() async => {
        for (final r in _db.select('SELECT key, value FROM preferences')) r['key'] as String: r['value'] as String,
      };

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _db.execute('DELETE FROM preferences WHERE key = ?', [key]);
    } else {
      _db.execute(
        'INSERT INTO preferences (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value],
      );
    }
  }
}

class _Facts implements FactRepository {
  _Facts(this._db);
  final Database _db;

  static MemoryFact _fact(Row r) => MemoryFact(
        id: r['id'] as int,
        category: FactCategory.values.asNameMap()[r['category']] ?? FactCategory.other,
        text: r['text'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
        status: r['status'] == 'archived' ? FactStatus.archived : FactStatus.active,
        source: r['source'] == 'auto' ? FactSource.auto : FactSource.manual,
      );

  void _index(int id, FactCategory cat, String text) {
    _db.execute('DELETE FROM facts_fts WHERE rowid = ?', [id]);
    _db.execute('INSERT INTO facts_fts(rowid, norm) VALUES (?, ?)', [id, normalizeTr('${cat.label} $text')]);
  }

  @override
  Future<List<MemoryFact>> all({bool includeArchived = false}) async => [
        for (final r in _db.select(
          'SELECT * FROM facts ${includeArchived ? '' : "WHERE status = 'active'"} ORDER BY updated_at DESC, id DESC',
        ))
          _fact(r),
      ];

  @override
  Future<List<MemoryFact>> search(String query, {int limit = 5}) async {
    final q = EncryptedMemoryDatabase.ftsQuery(query);
    if (q == null) return const [];
    return [
      for (final r in _db.select(
        "SELECT f.* FROM facts_fts JOIN facts f ON f.id = facts_fts.rowid "
        "WHERE facts_fts MATCH ? AND f.status = 'active' ORDER BY bm25(facts_fts) LIMIT ?",
        [q, limit],
      ))
        _fact(r),
    ];
  }

  @override
  Future<UpsertResult> upsert(FactCategory category, String text, {FactSource source = FactSource.manual}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final active = [
      for (final r in _db.select("SELECT * FROM facts WHERE status = 'active' AND category = ?", [category.name])) _fact(r),
    ];
    for (final f in active) {
      if (FactRules.sameMeaning(f.text, text)) {
        _db.execute('UPDATE facts SET updated_at = ? WHERE id = ?', [now, f.id]);
        return UpsertResult(UpsertOutcome.duplicate, f.copyWith(updatedAt: DateTime.fromMillisecondsSinceEpoch(now)));
      }
    }
    final replaced = <MemoryFact>[];
    if (category.singleValued) {
      for (final f in active) {
        _db.execute("UPDATE facts SET status = 'archived', updated_at = ? WHERE id = ?", [now, f.id]);
        replaced.add(f.copyWith(status: FactStatus.archived));
      }
    }
    _db.execute(
      'INSERT INTO facts (text, created_at, category, status, source, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [text, now, category.name, 'active', source.name, now],
    );
    final id = _db.lastInsertRowId;
    _index(id, category, text);
    final at = DateTime.fromMillisecondsSinceEpoch(now);
    return UpsertResult(
      replaced.isEmpty ? UpsertOutcome.added : UpsertOutcome.replaced,
      MemoryFact(id: id, category: category, text: text, createdAt: at, updatedAt: at, source: source),
      replaced: replaced,
    );
  }

  @override
  Future<MemoryFact> add(String text) async => (await upsert(FactCategory.other, text)).fact;

  @override
  Future<void> update(int id, String text) async {
    final rows = _db.select('SELECT category FROM facts WHERE id = ?', [id]);
    if (rows.isEmpty) return;
    final cat = FactCategory.values.asNameMap()[rows.first['category']] ?? FactCategory.other;
    _db.execute('UPDATE facts SET text = ?, updated_at = ? WHERE id = ?', [text, DateTime.now().millisecondsSinceEpoch, id]);
    _index(id, cat, text);
  }

  @override
  Future<void> delete(int id) async {
    _db.execute('DELETE FROM facts WHERE id = ?', [id]);
    _db.execute('DELETE FROM facts_fts WHERE rowid = ?', [id]);
  }

  @override
  Future<void> clear() async {
    _db.execute('DELETE FROM facts');
    _db.execute('DELETE FROM facts_fts');
  }
}

class _Notes implements NoteRepository {
  _Notes(this._db);
  final Database _db;

  @override
  Future<List<Note>> all() async => [
        for (final r in _db.select('SELECT * FROM notes ORDER BY created_at DESC, id DESC'))
          Note(id: r['id'] as int, text: r['text'] as String, createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int)),
      ];

  @override
  Future<Note> add(String text) async {
    final now = DateTime.now();
    _db.execute('INSERT INTO notes (text, created_at) VALUES (?, ?)', [text, now.millisecondsSinceEpoch]);
    return Note(id: _db.lastInsertRowId, text: text, createdAt: now);
  }

  @override
  Future<void> delete(int id) async => _db.execute('DELETE FROM notes WHERE id = ?', [id]);
}

class _Reminders implements ReminderRepository {
  _Reminders(this._db);
  final Database _db;

  static Reminder _r(Row r) => Reminder(
        id: r['id'] as int,
        text: r['text'] as String,
        dueAt: DateTime.fromMillisecondsSinceEpoch(r['due_at'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        done: (r['done'] as int) == 1,
      );

  @override
  Future<List<Reminder>> all() async => [for (final r in _db.select('SELECT * FROM reminders ORDER BY due_at ASC')) _r(r)];

  @override
  Future<List<Reminder>> upcoming(DateTime now) async => [
        for (final r in _db.select(
          'SELECT * FROM reminders WHERE done = 0 AND due_at > ? ORDER BY due_at ASC',
          [now.millisecondsSinceEpoch],
        ))
          _r(r),
      ];

  @override
  Future<Reminder> add(String text, DateTime dueAt) async {
    final now = DateTime.now();
    _db.execute(
      'INSERT INTO reminders (text, due_at, created_at) VALUES (?, ?, ?)',
      [text, dueAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch],
    );
    return Reminder(id: _db.lastInsertRowId, text: text, dueAt: dueAt, createdAt: now);
  }

  @override
  Future<void> markDone(int id) async => _db.execute('UPDATE reminders SET done = 1 WHERE id = ?', [id]);

  @override
  Future<void> delete(int id) async => _db.execute('DELETE FROM reminders WHERE id = ?', [id]);
}
