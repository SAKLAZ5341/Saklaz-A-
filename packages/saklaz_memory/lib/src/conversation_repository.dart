import 'package:saklaz_core/saklaz_core.dart';

abstract interface class ConversationRepository {
  /// Kalıcı ve şifreli ise true.
  bool get isPersistent;

  Future<List<ChatMessage>> all();
  Future<void> add(ChatMessage message);
  Future<void> clear();

  /// Geçmiş konuşmalarda arama (en yeni önce).
  Future<List<ChatMessage>> search(String query, {int limit = 30});
}
