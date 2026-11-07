enum ChatRole { user, assistant, system }

/// Yanıtın nereden geldiği (kullanıcıya şeffaflık için arayüzde gösterilir).
enum MessageSource {
  user,

  /// Kural tabanlı yerel motor (AI değil).
  localRules,

  /// Yerel kişisel hafıza.
  memory,

  /// Cihaz üzerindeki yerel dil modeli.
  localLlm,

  /// OpenAI (SAKLAZ Gateway üzerinden).
  cloud,

  /// Sistem bildirimi / hata.
  system,
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.source = MessageSource.user,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final MessageSource source;

  bool get isUser => role == ChatRole.user;
}
