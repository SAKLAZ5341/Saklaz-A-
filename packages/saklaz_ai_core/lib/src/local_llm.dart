import 'package:saklaz_core/saklaz_core.dart';

import 'llm.dart';

enum LocalLlmState { unavailable, downloadable, downloading, ready, error }

class LocalLlmInfo {
  const LocalLlmInfo(this.state, {this.modelName, this.detail});
  final LocalLlmState state;
  final String? modelName;
  final String? detail;
}

/// Cihaz içi dil modeli (Android: Gemini Nano / ML Kit Prompt API).
abstract interface class LocalLlm {
  Future<LocalLlmInfo> info();

  /// Kullanıcı açıkça isterse modeli indirir (sistem yönetir).
  Future<LocalLlmInfo> download();

  Future<Result<String>> generate(String prompt, {int maxOutputTokens = 256, double temperature = 0.3});
}

/// Yerel model olmayan ortamlar (testler, Windows) için.
class NoLocalLlm implements LocalLlm {
  const NoLocalLlm();
  @override
  Future<LocalLlmInfo> info() async => const LocalLlmInfo(LocalLlmState.unavailable);
  @override
  Future<LocalLlmInfo> download() async => const LocalLlmInfo(LocalLlmState.unavailable);
  @override
  Future<Result<String>> generate(String prompt, {int maxOutputTokens = 256, double temperature = 0.3}) async =>
      const Result.err(Failure('local-model-unavailable', 'Yerel model yok.'));
}

/// [LocalLlm]'i [LlmClient] arayüzüne uyarlar (mesaj geçmişi -> tek istem).
class LocalLlmClient implements LlmClient {
  const LocalLlmClient(this.llm);
  final LocalLlm llm;

  @override
  Future<Result<LlmReply>> complete(LlmRequest request) async {
    final b = StringBuffer()
      ..writeln(request.instructions)
      ..writeln();
    for (final m in request.messages) {
      b.writeln('${m.role == LlmRole.user ? 'Kullanıcı' : 'SAKLAZ'}: ${m.text}');
    }
    b.write('SAKLAZ:');
    final r = await llm.generate(b.toString(), maxOutputTokens: request.maxOutputTokens.clamp(16, 512));
    return r.fold(
      (text) => text.trim().isEmpty
          ? const Result.err(Failure('empty', 'Yerel model boş yanıt verdi.'))
          : Result.ok(LlmReply(text: text.trim(), model: 'yerel')),
      Result.err,
    );
  }
}
