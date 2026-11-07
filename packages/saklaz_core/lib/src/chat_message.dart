enum ChatRole { user, assistant, system }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;

  bool get isUser => role == ChatRole.user;
}
