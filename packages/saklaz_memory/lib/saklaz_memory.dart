/// SAKLAZ kişisel hafıza katmanı.
///
/// Phase 2: SQLite3MultipleCiphers ile şifreli kalıcı depolama
/// ([EncryptedMemoryDatabase]). Şifreleme doğrulanamazsa veritabanı AÇILMAZ
/// (fail-closed); uygulama bellek içi depolara düşer ve kullanıcıyı uyarır.
library;

export 'src/conversation_repository.dart';
export 'src/encrypted_memory_database.dart';
export 'src/fact_repository.dart';
export 'src/in_memory_conversation_repository.dart';
export 'src/in_memory_stores.dart';
export 'src/memory_search.dart';
export 'src/preferences_store.dart';
