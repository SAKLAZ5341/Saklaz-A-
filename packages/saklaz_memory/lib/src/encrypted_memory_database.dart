import 'package:saklaz_core/saklaz_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'conversation_repository.dart';
import 'fact_repository.dart';
import 'preferences_store.dart';

/// Şifreleme doğrulanamadığında fırlatılır. Veritabanı bu durumda AÇILMAZ.
class MemoryEncryptionUnavailable implements Exception {
  MemoryEncryptionUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'MemoryEncryptionUnavailable: $reason';
}

/// SQLite3MultipleCiphers (ChaCha20-Poly1305) ile şifreli tek dosyalık hafıza.
///
/// Anahtar dışarıdan verilir (Android'de Keystore ile sarılı rastgele 256-bit).
/// Açılışta şunlar doğrulanır:
///  1. Bağlı kütüphane gerçekten SQLite3MultipleCiphers mi?
///  2. Anahtar doğru mu? (yanlış anahtarla şema okunamaz)
class EncryptedMemoryDatabase
    implements ConversationRepository, PreferencesStore {
  EncryptedMemoryDatabase._(this._db, this.cipherVersion);

  final Database _db;

  /// Örn. "SQLite3 Multiple Ciphers 2.x" — kullanıcıya bilgi olarak gösterilir.
  final String cipherVersion;

  static const schemaVersion = 1;

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
      final row = db.select('SELECT sqlite3mc_version() AS v;').first;
      return row['v'] as String?;
    } on SqliteException {
      return null;
    }
  }

  static void _migrate(Database db) {
    if (db.userVersion >= schemaVersion) return;
    db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        role TEXT NOT NULL,
        source TEXT NOT NULL,
        text TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS messages_created ON messages(created_at);
      CREATE TABLE IF NOT EXISTS facts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS preferences (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
    db.userVersion = schemaVersion;
  }

  void close() => _db.close();

  // ---- ConversationRepository ----

  static const maxMessages = 500;

  @override
  bool get isPersistent => true;

  @override
  Future<List<ChatMessage>> all() async {
    final rows = _db.select(
      'SELECT * FROM (SELECT * FROM messages ORDER BY created_at DESC LIMIT ?) ORDER BY created_at ASC',
      [maxMessages],
    );
    return [
      for (final r in rows)
        ChatMessage(
          id: r['id'] as String,
          role: ChatRole.values.byName(r['role'] as String),
          source: MessageSource.values.byName(r['source'] as String),
          text: r['text'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        ),
    ];
  }

  @override
  Future<void> add(ChatMessage m) async {
    _db.execute(
      'INSERT OR REPLACE INTO messages (id, role, source, text, created_at) VALUES (?, ?, ?, ?, ?)',
      [m.id, m.role.name, m.source.name, m.text, m.createdAt.millisecondsSinceEpoch],
    );
    _db.execute(
      'DELETE FROM messages WHERE id NOT IN (SELECT id FROM messages ORDER BY created_at DESC LIMIT ?)',
      [maxMessages],
    );
  }

  @override
  Future<void> clear() async => _db.execute('DELETE FROM messages');

  // ---- FactRepository: all/add/clear adları konuşma deposuyla çakıştığı için ayrı nesne ----

  late final FactRepository facts = _Facts(_db);

  // ---- PreferencesStore ----

  @override
  Future<Map<String, String>> readAll() async => {
        for (final r in _db.select('SELECT key, value FROM preferences'))
          r['key'] as String: r['value'] as String,
      };

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _db.execute('DELETE FROM preferences WHERE key = ?', [key]);
    } else {
      _db.execute(
        'INSERT INTO preferences (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value],
      );
    }
  }
}

class _Facts implements FactRepository {
  _Facts(this._db);
  final Database _db;

  @override
  Future<List<MemoryFact>> all() async => [
        for (final r in _db.select('SELECT id, text, created_at FROM facts ORDER BY created_at DESC, id DESC'))
          MemoryFact(
            id: r['id'] as int,
            text: r['text'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
          ),
      ];

  @override
  Future<MemoryFact> add(String text) async {
    final now = DateTime.now();
    _db.execute('INSERT INTO facts (text, created_at) VALUES (?, ?)', [text, now.millisecondsSinceEpoch]);
    return MemoryFact(id: _db.lastInsertRowId, text: text, createdAt: now);
  }

  @override
  Future<void> delete(int id) async => _db.execute('DELETE FROM facts WHERE id = ?', [id]);

  @override
  Future<void> clear() async => _db.execute('DELETE FROM facts');
}
