import 'package:saklaz_core/saklaz_core.dart';

import 'llm.dart';

enum LocalLlmState {
  /// Hiç model indirilmemiş.
  noModel,

  /// Model indirildi ama belleğe yüklenmedi.
  notLoaded,
  loading,
  ready,
  failed,
}

class LocalLlmInfo {
  const LocalLlmInfo(this.state, {this.modelName, this.backend, this.detail});
  final LocalLlmState state;
  final String? modelName;
  final String? backend;
  final String? detail;
}

/// Cihaz içi dil modeli (Android: LiteRT-LM + indirilen .litertlm modeli).
abstract interface class LocalLlm {
  Future<LocalLlmInfo> info();

  Future<Result<String>> chat({
    required String system,
    required List<LlmMessage> history,
    required String user,
    int maxOutputTokens = 384,
  });
}

/// Yerel model olmayan ortamlar (testler) için.
class NoLocalLlm implements LocalLlm {
  const NoLocalLlm();
  @override
  Future<LocalLlmInfo> info() async => const LocalLlmInfo(LocalLlmState.noModel);
  @override
  Future<Result<String>> chat({
    required String system,
    required List<LlmMessage> history,
    required String user,
    int maxOutputTokens = 384,
  }) async =>
      const Result.err(Failure('local-model-unavailable', 'Yerel model yok.'));
}

/// [LocalLlm]'i [LlmClient] arayüzüne uyarlar.
class LocalLlmClient implements LlmClient {
  const LocalLlmClient(this.llm);
  final LocalLlm llm;

  @override
  Future<Result<LlmReply>> complete(LlmRequest request) async {
    final msgs = request.messages;
    if (msgs.isEmpty) return const Result.err(Failure('empty', 'Boş istek'));
    final r = await llm.chat(
      system: request.instructions,
      history: msgs.sublist(0, msgs.length - 1),
      user: msgs.last.text,
      maxOutputTokens: request.maxOutputTokens.clamp(32, 1024),
    );
    return r.fold(
      (text) {
        final clean = cleanModelText(text);
        return clean.isEmpty
            ? const Result.err(Failure('empty', 'Yerel model boş yanıt verdi.'))
            : Result.ok(LlmReply(text: clean, model: 'yerel'));
      },
      Result.err,
    );
  }
}

/// Model çıktısını sesli okumaya uygun düz metne çevirir:
/// `<think>` blokları, markdown işaretleri ve fazla boşluklar temizlenir.
String cleanModelText(String text) {
  var t = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
  t = t.replaceAll(RegExp(r'</?think>'), '');
  t = t.replaceAll(RegExp(r'\*\*|__|`{1,3}'), '');
  t = t.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '');
  t = t.replaceAll(RegExp(r'(?<=\s|^)\*(?=\S)|(?<=\S)\*(?=\s|$)'), '');
  t = t.replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}
