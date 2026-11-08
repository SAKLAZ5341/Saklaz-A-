/// SAKLAZ kişisel hafıza katmanı.
///
/// SQLite3MultipleCiphers ile şifreli kalıcı depolama ([EncryptedMemoryDatabase]),
/// FTS5 tam metin arama, kategorili kişisel bilgiler (çelişki yönetimiyle),
/// notlar ve hatırlatıcılar. Şifreleme doğrulanamazsa veritabanı AÇILMAZ.
library;

export 'src/conversation_repository.dart';
export 'src/encrypted_memory_database.dart';
export 'src/fact_repository.dart';
export 'src/in_memory_conversation_repository.dart';
export 'src/in_memory_stores.dart';
export 'src/memory_search.dart';
export 'src/notes_reminders.dart';
export 'src/preferences_store.dart';
