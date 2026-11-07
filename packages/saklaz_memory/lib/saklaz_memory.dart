/// SAKLAZ hafıza katmanı.
///
/// Phase 1: Yalnızca arayüz + bellek içi (RAM) uygulama. Hiçbir şey diske
/// yazılmaz; uygulama kapanınca konuşma geçmişi silinir. Şifreli kalıcı
/// depolama (drift + SQLCipher, anahtar Android Keystore'da) Phase 2'de.
library;

export 'src/conversation_repository.dart';
export 'src/in_memory_conversation_repository.dart';
