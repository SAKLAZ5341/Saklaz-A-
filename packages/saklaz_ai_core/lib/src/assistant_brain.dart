import 'package:saklaz_core/saklaz_core.dart';

/// Kullanıcı mesajına yanıt üreten bileşen. Uygulamalar: yer tutucu (Phase 1),
/// yerel LLM ve bulut LLM (Phase 4).
abstract interface class AssistantBrain {
  /// Bu beynin kullanıcıya gösterilecek adı (ör. "Yerel (AI yok)").
  String get displayName;

  /// Hiçbir veriyi cihaz dışına göndermiyorsa true.
  bool get isOnDevice;

  Future<Result<String>> reply(String userText, List<ChatMessage> history);
}
