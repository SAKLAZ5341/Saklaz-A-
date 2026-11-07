import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';

import 'llm.dart';
import 'local_intent_engine.dart';
import 'local_llm.dart';
import 'router.dart';

/// Kullanıcı kararı gerektiren bekleyen işlem.
sealed class PendingAction {
  const PendingAction();
}

/// "Bunu hafızana kaydedeyim mi?"
class ConfirmRemember extends PendingAction {
  const ConfirmRemember(this.content);
  final String content;
}

/// "Bu soruyu OpenAI'a göndereyim mi?"
class ConfirmCloud extends PendingAction {
  const ConfirmCloud({required this.userText, required this.webSearch, required this.localAlternative});
  final String userText;
  final bool webSearch;
  final bool localAlternative;
}

class AssistantTurn {
  const AssistantTurn(this.text, this.source, {this.pending});
  final String text;
  final MessageSource source;
  final PendingAction? pending;
}

/// İki beyinli SAKLAZ asistanı.
class SaklazAssistant {
  SaklazAssistant({
    required this.facts,
    required this.cloud,
    required this.localLlm,
    required this.routeContext,
    this.shareFactsWithCloud = _never,
    DateTime Function()? clock,
    this.intents = const LocalIntentEngine(),
    this.router = const AssistantRouter(),
    this.search = const MemorySearch(),
    this.historyTurns = 6,
  }) : _clock = clock ?? DateTime.now;

  final FactRepository facts;

  /// Bulut istemcisi; ayarlanmamışsa null.
  final LlmClient? Function() cloud;
  final LocalLlm localLlm;
  final Future<RouteContext> Function() routeContext;

  /// Kişisel bilgilerin buluta bağlam olarak gönderilmesine izin var mı?
  final bool Function() shareFactsWithCloud;
  final LocalIntentEngine intents;
  final AssistantRouter router;
  final MemorySearch search;

  /// Buluta/yerel modele gönderilecek en fazla önceki mesaj sayısı (veri azaltma).
  final int historyTurns;
  final DateTime Function() _clock;

  static bool _never() => false;

  Future<AssistantTurn> respond(String text, List<ChatMessage> history) async {
    final intent = intents.classify(text);
    final decision = router.decide(intent, await routeContext());
    return switch (decision) {
      UseBrain(brain: Brain.localRules) => _rules(intent),
      UseBrain(brain: Brain.memory) => _memory(intent),
      UseBrain(brain: Brain.localLlm) => _local(text, history),
      UseBrain(brain: Brain.cloud) => _cloud(text, history, webSearch: _needsWeb(intent)),
      AskCloudConsent(:final localAlternative) => AssistantTurn(
          _needsWeb(intent)
              ? 'Bu soru güncel bilgi gerektiriyor. Sorunu OpenAI\'a göndermemi onaylıyor musun?'
              : 'Bu soru için bulut zekâsı daha iyi sonuç verir. Sorunu OpenAI\'a göndermemi onaylıyor musun?',
          MessageSource.system,
          pending: ConfirmCloud(userText: text, webSearch: _needsWeb(intent), localAlternative: localAlternative),
        ),
      Unavailable(:final reason) => AssistantTurn(_unavailableText(reason, intent), MessageSource.system),
    };
  }

  /// Kullanıcı bulut iznini onayladığında.
  Future<AssistantTurn> answerWithCloud(ConfirmCloud action, List<ChatMessage> history) =>
      _cloud(action.userText, history, webSearch: action.webSearch);

  /// Kullanıcı bulutu reddettiğinde: yerel model varsa onunla dene.
  Future<AssistantTurn> answerLocally(ConfirmCloud action, List<ChatMessage> history) async {
    final ctx = await routeContext();
    if (ctx.localLlmReady) return _local(action.userText, history);
    return const AssistantTurn('Tamam, buluta göndermedim. Bu soruyu yerelde yanıtlayabilecek bir model bu cihazda henüz hazır değil.', MessageSource.system);
  }

  /// Kullanıcı hafızaya kaydetmeyi onayladığında.
  Future<AssistantTurn> confirmRemember(ConfirmRemember action) async {
    await facts.add(action.content);
    return AssistantTurn('Kaydettim: "${action.content}". Hafıza ekranından istediğin zaman silebilirsin.', MessageSource.memory);
  }

  // --------------------------------------------------------------------------

  bool _needsWeb(LocalIntent i) => i is GeneralIntent && i.needsInternet;

  AssistantTurn _rules(LocalIntent intent) {
    final now = _clock();
    final text = switch (intent) {
      GreetingIntent() => 'Merhaba, ben SAKLAZ. Seni dinliyorum.',
      TimeIntent() => 'Saat şu an ${_two(now.hour)}:${_two(now.minute)}.',
      DateIntent() => 'Bugün ${now.day} ${_months[now.month - 1]} ${now.year}, ${_days[now.weekday - 1]}.',
      IdentityIntent() => 'Ben SAKLAZ, kişisel asistanınım. Basit işleri ve hafızanı cihazda, karmaşık soruları izninle bulutta yanıtlarım.',
      ThanksIntent() => 'Rica ederim.',
      HelpIntent() => 'Saati ve tarihi söyleyebilirim, "hatırla ki ..." diyerek bana bilgi kaydettirebilirsin, '
          'kayıtlı bilgilerini sorabilirsin. İzin verirsen karmaşık soruları OpenAI ile yanıtlarım.',
      _ => 'Anlayamadım.',
    };
    return AssistantTurn(text, MessageSource.localRules);
  }

  Future<AssistantTurn> _memory(LocalIntent intent) async {
    switch (intent) {
      case RememberIntent(:final content):
        return AssistantTurn(
          'Şunu hafızama kaydetmemi ister misin: "$content"',
          MessageSource.memory,
          pending: ConfirmRemember(content),
        );
      case MemoryQueryIntent(:final query, :final listAll):
        final all = await facts.all();
        if (all.isEmpty) {
          return const AssistantTurn('Hafızamda henüz senin hakkında kayıtlı bir bilgi yok. "Hatırla ki ..." diyerek ekleyebilirsin.', MessageSource.memory);
        }
        final found = listAll ? all.take(5).toList() : search.search(query, all, limit: 3);
        if (found.isEmpty) {
          return const AssistantTurn('Bununla ilgili kayıtlı bir bilgi bulamadım.', MessageSource.memory);
        }
        final joined = found.map((f) => f.text).join('. ');
        return AssistantTurn(listAll ? 'Hatırladıklarım: $joined.' : 'Kayıtlarıma göre: $joined.', MessageSource.memory);
      default:
        return const AssistantTurn('Anlayamadım.', MessageSource.memory);
    }
  }

  List<LlmMessage> _history(List<ChatMessage> history, String text) {
    final relevant = history
        .where((m) => m.role != ChatRole.system && m.source != MessageSource.system)
        .toList();
    // Son kullanıcı mesajı zaten text; tekrar eklenmesin.
    if (relevant.isNotEmpty && relevant.last.isUser && relevant.last.text == text) relevant.removeLast();
    final tail = relevant.length > historyTurns ? relevant.sublist(relevant.length - historyTurns) : relevant;
    return [
      for (final m in tail) LlmMessage(m.isUser ? LlmRole.user : LlmRole.assistant, m.text),
      LlmMessage(LlmRole.user, text),
    ];
  }

  Future<String> _withFacts(String base, String text, {required bool cloud}) async {
    if (cloud && !shareFactsWithCloud()) return base;
    final relevant = search.search(text, await facts.all(), limit: 3);
    if (relevant.isEmpty) return base;
    return '$base\nKullanıcı hakkında kayıtlı bilgiler: ${relevant.map((f) => f.text).join('; ')}.';
  }

  Future<AssistantTurn> _local(String text, List<ChatMessage> history) async {
    final client = LocalLlmClient(localLlm);
    // Küçük cihaz modelinin bağlam penceresi dar: son 5 mesaj.
    final msgs = _history(history, text);
    final r = await client.complete(LlmRequest(
      instructions: await _withFacts(saklazInstructions, text, cloud: false),
      messages: msgs.length > 5 ? msgs.sublist(msgs.length - 5) : msgs,
      maxOutputTokens: 256,
    ));
    return r.fold(
      (reply) => AssistantTurn(reply.text, MessageSource.localLlm),
      (f) => AssistantTurn('Yerel model yanıt veremedi: ${f.message}', MessageSource.system),
    );
  }

  Future<AssistantTurn> _cloud(String text, List<ChatMessage> history, {required bool webSearch}) async {
    final client = cloud();
    if (client == null) return AssistantTurn(_unavailableText(UnavailableReason.cloudNotConfigured, null), MessageSource.system);
    final r = await client.complete(LlmRequest(
      instructions: await _withFacts(saklazInstructions, text, cloud: true),
      messages: _history(history, text),
      webSearch: webSearch,
    ));
    return r.fold(
      (reply) => AssistantTurn(reply.text, MessageSource.cloud),
      (f) => AssistantTurn('Bulut zekâsına ulaşılamadı: ${f.message}', MessageSource.system),
    );
  }

  String _unavailableText(UnavailableReason r, LocalIntent? intent) {
    final web = intent is GeneralIntent && intent.needsInternet;
    return switch (r) {
      UnavailableReason.offline => web
          ? 'Bu soru güncel bilgi gerektiriyor ama şu an internet bağlantısı yok. Saat, tarih ve hafıza gibi yerel özellikler çalışmaya devam ediyor.'
          : 'Şu an internet bağlantısı yok ve bu cihazda yerel dil modeli hazır değil. Yerel komutlar ve hafıza çalışıyor.',
      UnavailableReason.cloudNotConfigured => 'Bu soru için bulut zekâsı gerekiyor ama SAKLAZ Gateway henüz ayarlanmadı. Ayarlar > Bulut zekâsı bölümünden ekleyebilirsin.',
      UnavailableReason.cloudDisabled => 'Bulut zekâsı ayarlarda kapalı ve bu soruyu yerelde yanıtlayabilecek model hazır değil.',
      UnavailableReason.noLocalModel => 'Bu soruyu yanıtlamak için yerel dil modeli veya bulut bağlantısı gerekiyor; ikisi de şu an kullanılamıyor.',
    };
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static const _months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  static const _days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
}
