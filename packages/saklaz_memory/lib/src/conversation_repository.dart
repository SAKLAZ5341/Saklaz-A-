import 'package:saklaz_core/saklaz_core.dart';

abstract interface class ConversationRepository {
  /// Kalıcı ve şifreli ise true. Phase 1'deki bellek içi uygulama: false.
  bool get isPersistent;

  Future<List<ChatMessage>> all();
  Future<void> add(ChatMessage message);
  Future<void> clear();
}
