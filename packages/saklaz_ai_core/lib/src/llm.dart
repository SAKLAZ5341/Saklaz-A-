import 'package:saklaz_core/saklaz_core.dart';

enum LlmRole { user, assistant }

class LlmMessage {
  const LlmMessage(this.role, this.text);
  final LlmRole role;
  final String text;

  Map<String, Object?> toJson() => {'role': role.name, 'text': text};
}

class LlmRequest {
  const LlmRequest({
    required this.instructions,
    required this.messages,
    this.maxOutputTokens = 400,
    this.webSearch = false,
  });

  final String instructions;
  final List<LlmMessage> messages;
  final int maxOutputTokens;
  final bool webSearch;
}

class LlmReply {
  const LlmReply({required this.text, this.model, this.inputTokens, this.outputTokens, this.costUsd});
  final String text;
  final String? model;
  final int? inputTokens;
  final int? outputTokens;
  final double? costUsd;
}

abstract interface class LlmClient {
  Future<Result<LlmReply>> complete(LlmRequest request);
}

/// SAKLAZ'ın kişiliği. Yanıtlar sesli okunacağı için düz metin istenir.
const saklazInstructions =
    'Sen SAKLAZ adında Türkçe konuşan kişisel bir asistansın. '
    'Kısa, net ve doğal Türkçe yanıt ver. Yanıtın sesli okunabileceği için '
    'markdown, madde işareti, tablo veya emoji kullanma. Emin olmadığın bilgiyi '
    'uydurma; bilmiyorsan söyle. Kullanıcı adına hiçbir işlem yaptığını iddia etme.';
