import 'package:saklaz_core/saklaz_core.dart';

import 'conversation_repository.dart';

/// Yalnızca RAM'de tutar; diske yazmaz. Eski mesajlar [maxMessages] ile sınırlanır.
class InMemoryConversationRepository implements ConversationRepository {
  InMemoryConversationRepository({this.maxMessages = 200});

  final int maxMessages;
  final _messages = <ChatMessage>[];

  @override
  bool get isPersistent => false;

  @override
  Future<List<ChatMessage>> all() async => List.unmodifiable(_messages);

  @override
  Future<void> add(ChatMessage message) async {
    _messages.add(message);
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
  }

  @override
  Future<void> clear() async => _messages.clear();
}
