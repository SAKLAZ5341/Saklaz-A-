import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';

import 'device_ports.dart';
import 'fact_extractor.dart';
import 'llm.dart';
import 'local_intent_engine.dart';
import 'local_llm.dart';
import 'router.dart';
import 'turkish_time.dart';

// ============================================================================ Agent eylemleri

enum RiskLevel {
  /// Onaysız (okuma, uygulama açma).
  low,

  /// Kısa onay; sesli "evet" yeterli.
  medium,

  /// Açık ekran onayı zorunlu; sesli onay KABUL EDİLMEZ.
  high,
}

sealed class AgentAction {
  const AgentAction();
  RiskLevel get risk;
  String get preview;
}

class SaveNoteAction extends AgentAction {
  const SaveNoteAction(this.text);
  final String text;
  @override
  RiskLevel get risk => RiskLevel.medium;
  @override
  String get preview => 'Not: "$text"';
}

class CreateReminderAction extends AgentAction {
  const CreateReminderAction(this.text, this.at, this.whenText);
  final String text;
  final DateTime at;
  final String whenText;
  @override
  RiskLevel get risk => RiskLevel.medium;
  @override
  String get preview => 'Hatırlatma: "$text" — $whenText';
}

class SetAlarmAction extends AgentAction {
  const SetAlarmAction(this.hour, this.minute, this.whenText);
  final int hour;
  final int minute;
  final String whenText;
  @override
  RiskLevel get risk => RiskLevel.medium;
  @override
  String get preview => 'Alarm: ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} ($whenText)';
}

class AddCalendarEventAction extends AgentAction {
  const AddCalendarEventAction(this.title, this.start, this.whenText);
  final String title;
  final DateTime start;
  final String whenText;
  @override
  RiskLevel get risk => RiskLevel.medium;
  @override
  String get preview => 'Takvim etkinliği: "$title" — $whenText (takvim uygulamasında kaydedeceksin)';
}

class CallAction extends AgentAction {
  const CallAction(this.name, this.phone);
  final String name;
  final String phone;
  @override
  RiskLevel get risk => RiskLevel.medium;
  @override
  String get preview => 'Arama: $name ($phone) — çevirici açılır, aramayı sen başlatırsın';
}

class WhatsAppAction extends AgentAction {
  const WhatsAppAction(this.name, this.phone, this.text);
  final String name;
  final String phone;
  final String text;
  @override
  RiskLevel get risk => RiskLevel.high;
  @override
  String get preview => 'WhatsApp: $name ($phone)\nMesaj: "$text"\nWhatsApp\'ta taslak açılır; GÖNDER\'e sen basarsın.';
}

class ReplyNotificationAction extends AgentAction {
  const ReplyNotificationAction(this.key, this.to, this.text);
  final String key;
  final String to;
  final String text;
  @override
  RiskLevel get risk => RiskLevel.high;
  @override
  String get preview => '$to bildirimine yanıt: "$text"';
}

// ============================================================================ Bekleyen kararlar

sealed class PendingAction {
  const PendingAction();

  /// Sesli "evet/hayır" ile karar verilebilir mi?
  bool get voiceConfirmable;
}

class ConfirmRemember extends PendingAction {
  const ConfirmRemember(this.content);
  final String content;
  @override
  bool get voiceConfirmable => true;
}

class ConfirmCloud extends PendingAction {
  const ConfirmCloud({required this.userText, required this.webSearch, required this.localAlternative});
  final String userText;
  final bool webSearch;
  final bool localAlternative;
  @override
  bool get voiceConfirmable => true;
}

class ConfirmAgentAction extends PendingAction {
  const ConfirmAgentAction(this.action);
  final AgentAction action;
  @override
  bool get voiceConfirmable => action.risk != RiskLevel.high;
}

class AssistantTurn {
  const AssistantTurn(this.text, this.source, {this.pending, this.learned = const []});
  final String text;
  final MessageSource source;
  final PendingAction? pending;

  /// Bu mesajdan otomatik öğrenilen bilgiler (şeffaflık için gösterilir).
  final List<MemoryFact> learned;

  AssistantTurn withLearned(List<MemoryFact> l) => AssistantTurn(text, source, pending: pending, learned: l);
}

/// Sesli onay yanıtlarını tanır.
abstract final class YesNo {
  static bool? parse(String text) {
    final t = normalizeTr(text);
    if (t.isEmpty || t.split(' ').length > 4) return null;
    if (RegExp(r'^(evet|tamam|olur|kaydet|gonder|onayliyorum|onayla|aynen|tabii|tabi|elbette|evet kaydet|evet gonder)\b').hasMatch(t)) return true;
    if (RegExp(r'^(hayir|vazgec|iptal|istemiyorum|gonderme|kaydetme|bosver|yok)\b').hasMatch(t)) return false;
    return null;
  }
}

// ============================================================================ Asistan

/// İki beyinli SAKLAZ asistanı: yerel (kurallar + hafıza + yerel LLM) ve isteğe bağlı bulut.
class SaklazAssistant {
  SaklazAssistant({
    required this.facts,
    required this.cloud,
    required this.localLlm,
    required this.routeContext,
    NoteRepository? notes,
    ReminderRepository? reminders,
    this.device = const NoDevice(),
    this.shareFactsWithCloud = _never,
    this.autoLearn = _always,
    DateTime Function()? clock,
    this.historyTurns = 6,
  })  : notes = notes ?? InMemoryNoteRepository(),
        reminders = reminders ?? InMemoryReminderRepository(),
        _clock = clock ?? DateTime.now,
        intents = LocalIntentEngine(clock: clock);

  final FactRepository facts;
  final NoteRepository notes;
  final ReminderRepository reminders;
  final DevicePorts device;

  /// Etkin bulut sağlayıcısının istemcisi; yoksa null.
  final LlmClient? Function() cloud;
  final LocalLlm localLlm;
  final Future<RouteContext> Function() routeContext;
  final bool Function() shareFactsWithCloud;
  final bool Function() autoLearn;
  final LocalIntentEngine intents;
  final AssistantRouter router = const AssistantRouter();
  final FactExtractor extractor = const FactExtractor();
  final int historyTurns;
  final DateTime Function() _clock;

  static bool _never() => false;
  static bool _always() => true;

  Future<AssistantTurn> respond(String text, List<ChatMessage> history) async {
    final intent = intents.classify(text);
    final learned = await _learn(text, intent);
    var turn = await _handle(intent, text, history);
    if (learned.isNotEmpty && turn.source == MessageSource.system && turn.pending == null) {
      // Yanıt üretilemediyse bile öğrenilenleri bildir.
      turn = AssistantTurn('Not ettim: ${learned.map((f) => '${f.category.label.toLowerCase()} — ${f.text}').join(', ')}.', MessageSource.memory);
    }
    return turn.withLearned(learned);
  }

  /// Otomatik kişisel öğrenme (yalnızca bilgi cümlelerinden, sırlar hariç).
  Future<List<MemoryFact>> _learn(String text, LocalIntent intent) async {
    if (!autoLearn() || intent is! GeneralIntent) return const [];
    final out = <MemoryFact>[];
    for (final f in extractor.extract(text)) {
      final r = await facts.upsert(f.category, f.text, source: FactSource.auto);
      if (r.outcome != UpsertOutcome.duplicate) out.add(r.fact);
    }
    return out;
  }

  Future<AssistantTurn> _handle(LocalIntent intent, String text, List<ChatMessage> history) async {
    switch (intent) {
      case GreetingIntent() || TimeIntent() || DateIntent() || IdentityIntent() || ThanksIntent() || HelpIntent():
        return _rules(intent);
      case RememberIntent(:final content):
        if (SensitiveFilter.isSensitive(content)) {
          return const AssistantTurn(
            'Bu bir şifre, kart veya kimlik bilgisi gibi görünüyor. Güvenliğin için bunu hafızama kaydetmiyorum; bir parola yöneticisi kullanmanı öneririm.',
            MessageSource.memory,
          );
        }
        return AssistantTurn('Şunu hafızama kaydetmemi ister misin: "$content"', MessageSource.memory, pending: ConfirmRemember(content));
      case MemoryQueryIntent():
        return _memory(intent);
      case NoteIntent(:final text):
        if (text.isEmpty) return const AssistantTurn('Ne not almamı istersin?', MessageSource.localRules);
        return _confirm(SaveNoteAction(text));
      case ListNotesIntent():
        final all = await notes.all();
        if (all.isEmpty) return const AssistantTurn('Kayıtlı notun yok.', MessageSource.localRules);
        return AssistantTurn('Notların: ${all.take(5).map((n) => n.text).join('. ')}.', MessageSource.localRules);
      case ReminderIntent(:final task, :final at):
        if (at == null) return const AssistantTurn('Ne zaman hatırlatayım? Örneğin "yarın sabah 9\'da" veya "10 dakika sonra" diyebilirsin.', MessageSource.localRules);
        if (task.isEmpty) return const AssistantTurn('Neyi hatırlatmamı istersin?', MessageSource.localRules);
        return _confirm(CreateReminderAction(task, at, TurkishTime.format(at, _clock())));
      case ListRemindersIntent():
        final up = await reminders.upcoming(_clock());
        if (up.isEmpty) return const AssistantTurn('Yaklaşan hatırlatman yok.', MessageSource.localRules);
        return AssistantTurn(
          'Yaklaşan hatırlatmaların: ${up.take(5).map((r) => '${TurkishTime.format(r.dueAt, _clock())} ${r.text}').join('; ')}.',
          MessageSource.localRules,
        );
      case AlarmIntent(:final at):
        if (at == null) return const AssistantTurn('Alarmı saat kaça kurayım?', MessageSource.localRules);
        return _confirm(SetAlarmAction(at.hour, at.minute, TurkishTime.format(at, _clock())));
      case CalendarAddIntent(:final title, :final at):
        if (at == null) return const AssistantTurn('Etkinlik ne zaman? Örneğin "yarın 14\'te".', MessageSource.localRules);
        return _confirm(AddCalendarEventAction(title.isEmpty ? 'Etkinlik' : title, at, TurkishTime.format(at, _clock())));
      case CalendarQueryIntent(:final day):
        return _calendar(day);
      case CallIntent(:final target):
        return _contactAction(target, (c) => CallAction(c.name, c.phone));
      case WhatsAppIntent(:final target, :final message):
        if (target.isEmpty) return const AssistantTurn('Kime WhatsApp mesajı göndereyim? Örnek: "Ahmet\'e WhatsApp\'tan: geç kalacağım".', MessageSource.localRules);
        if (message.isEmpty) return const AssistantTurn('Mesajda ne yazsın?', MessageSource.localRules);
        return _contactAction(target, (c) => WhatsAppAction(c.name, c.phone, message));
      case OpenAppIntent(:final name):
        final apps = await device.findApps(name);
        if (apps.isEmpty) return AssistantTurn('"$name" adında bir uygulama bulamadım.', MessageSource.localRules);
        final ok = await device.launchApp(apps.first.packageName);
        return AssistantTurn(ok ? '${apps.first.label} açılıyor.' : '${apps.first.label} açılamadı.', MessageSource.localRules);
      case OpenSettingsIntent(:final target):
        final ok = await device.openSettings(target);
        return AssistantTurn(ok ? 'Ayarlar açılıyor.' : 'Bu ayar ekranı açılamadı.', MessageSource.localRules);
      case NotificationsIntent():
        return _notifications();
      case GeneralIntent():
        return _general(intent, text, history);
    }
  }

  AssistantTurn _confirm(AgentAction a) => AssistantTurn(
        '${a.preview}\nOnaylıyor musun?${a.risk == RiskLevel.high ? ' (Güvenlik için ekrandan onay gerekir.)' : ''}',
        MessageSource.localRules,
        pending: ConfirmAgentAction(a),
      );

  Future<AssistantTurn> _contactAction(String target, AgentAction Function(Contact c) build) async {
    final digits = target.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.length >= 7) return _confirm(build(Contact(target, digits)));
    if (!await device.ensurePermission(DevicePermission.contacts)) {
      return const AssistantTurn('Rehberindeki kişiyi bulmam için Rehber izni gerekiyor. İzinler ekranından verebilirsin.', MessageSource.system);
    }
    for (final q in _nameCandidates(target)) {
      final found = await device.searchContacts(q);
      if (found.isNotEmpty) return _confirm(build(found.first));
    }
    return AssistantTurn('Rehberinde "$target" adında bir kişi bulamadım.', MessageSource.localRules);
  }

  /// "Ahmet'e" -> Ahmet, "anneme" -> anne / annem.
  static List<String> _nameCandidates(String raw) {
    final base = raw.split(RegExp(r"['’]")).first.trim();
    final out = <String>{base};
    for (final suf in ['ye', 'ya', 'yi', 'yı', 'yu', 'yü', 'e', 'a', 'i', 'ı', 'u', 'ü', 'me', 'ma', 'mi', 'mı']) {
      if (base.length > suf.length + 2 && base.toLowerCase().endsWith(suf)) out.add(base.substring(0, base.length - suf.length));
    }
    return out.toList();
  }

  Future<AssistantTurn> _calendar(DateTime day) async {
    if (!await device.ensurePermission(DevicePermission.calendar)) {
      return const AssistantTurn('Takvimini okumam için Takvim izni gerekiyor. İzinler ekranından verebilirsin.', MessageSource.system);
    }
    final items = await device.readCalendar(day, day.add(const Duration(days: 1)));
    final label = TurkishTime.format(day, _clock()).split(' ').first;
    if (items.isEmpty) return AssistantTurn('$label için takviminde etkinlik yok.', MessageSource.localRules);
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return AssistantTurn(
      '$label takviminde ${items.length} etkinlik var: ${items.take(6).map((e) => e.allDay ? '${e.title} (tüm gün)' : '${hm(e.start)} ${e.title}').join('; ')}.',
      MessageSource.localRules,
    );
  }

  Future<AssistantTurn> _notifications() async {
    if (!await device.notificationAccess()) {
      await device.openNotificationAccessSettings();
      return const AssistantTurn('Bildirimleri okuyabilmem için açılan ekranda SAKLAZ\'a bildirim erişimi vermelisin.', MessageSource.system);
    }
    final items = await device.recentNotifications(5);
    if (items.isEmpty) return const AssistantTurn('Yeni bildirim yok.', MessageSource.localRules);
    return AssistantTurn(
      'Son bildirimler: ${items.map((n) => '${n.app}, ${n.title}: ${n.text.length > 80 ? '${n.text.substring(0, 80)}…' : n.text}').join('. ')}',
      MessageSource.localRules,
    );
  }

  /// Bekleyen agent eylemini kullanıcı onayından SONRA çalıştırır.
  Future<AssistantTurn> execute(AgentAction a) async {
    switch (a) {
      case SaveNoteAction(:final text):
        await notes.add(text);
        return const AssistantTurn('Notu kaydettim.', MessageSource.localRules);
      case CreateReminderAction(:final text, :final at, :final whenText):
        await device.ensurePermission(DevicePermission.notifications);
        final r = await reminders.add(text, at);
        await device.scheduleReminder(r.id, text, at);
        return AssistantTurn('Tamam, $whenText hatırlatacağım: $text.', MessageSource.localRules);
      case SetAlarmAction(:final hour, :final minute, :final whenText):
        final ok = await device.setAlarm(hour, minute, 'SAKLAZ');
        return AssistantTurn(ok ? 'Alarm $whenText için kuruldu.' : 'Saat uygulaması alarm isteğini kabul etmedi.', MessageSource.localRules);
      case AddCalendarEventAction(:final title, :final start):
        final ok = await device.insertCalendarEvent(title, start, start.add(const Duration(hours: 1)));
        return AssistantTurn(ok ? 'Takvim açıldı; kaydetmek için Kaydet\'e dokun.' : 'Takvim uygulaması açılamadı.', MessageSource.localRules);
      case CallAction(:final name, :final phone):
        final ok = await device.openDialer(phone);
        return AssistantTurn(ok ? '$name için çevirici açıldı.' : 'Çevirici açılamadı.', MessageSource.localRules);
      case WhatsAppAction(:final name, :final phone, :final text):
        final ok = await device.openWhatsApp(phone, text);
        return AssistantTurn(ok ? 'WhatsApp\'ta $name için mesaj taslağı açıldı. Göndermek için GÖNDER\'e dokun.' : 'WhatsApp açılamadı.', MessageSource.localRules);
      case ReplyNotificationAction(:final key, :final text):
        final ok = await device.replyToNotification(key, text);
        return AssistantTurn(ok ? 'Yanıt gönderildi.' : 'Bu bildirime yanıt verilemedi.', MessageSource.localRules);
    }
  }

  Future<AssistantTurn> answerWithCloud(ConfirmCloud action, List<ChatMessage> history) =>
      _cloud(action.userText, history, webSearch: action.webSearch);

  Future<AssistantTurn> answerLocally(ConfirmCloud action, List<ChatMessage> history) async {
    final ctx = await routeContext();
    if (ctx.localLlmReady) return _local(action.userText, history);
    return const AssistantTurn('Tamam, buluta göndermedim. Yerel model henüz yüklü değil.', MessageSource.system);
  }

  Future<AssistantTurn> confirmRemember(ConfirmRemember action) async {
    await facts.upsert(FactCategory.other, action.content);
    return AssistantTurn('Kaydettim: "${action.content}". Benim Hafızam ekranından düzenleyip silebilirsin.', MessageSource.memory);
  }

  // ---------------------------------------------------------------------------

  AssistantTurn _rules(LocalIntent intent) {
    final now = _clock();
    final text = switch (intent) {
      GreetingIntent() => 'Merhaba, ben SAKLAZ. Seni dinliyorum.',
      TimeIntent() => 'Saat şu an ${_two(now.hour)}:${_two(now.minute)}.',
      DateIntent() => 'Bugün ${now.day} ${_months[now.month - 1]} ${now.year}, ${_days[now.weekday - 1]}.',
      IdentityIntent() => 'Ben SAKLAZ, kişisel asistanınım. Telefonunda yerel yapay zekâ ile çalışırım ve seni zamanla tanırım.',
      ThanksIntent() => 'Rica ederim.',
      HelpIntent() => 'Sohbet edebilirim, not alır ve hatırlatma kurarım, alarm ve takvim etkinliği eklerim, '
          'rehberindeki birini arayabilir veya WhatsApp taslağı hazırlayabilirim, bildirimlerini okurum ve seni zamanla tanırım.',
      _ => 'Anlayamadım.',
    };
    return AssistantTurn(text, MessageSource.localRules);
  }

  Future<AssistantTurn> _memory(MemoryQueryIntent q) async {
    final all = await facts.all();
    if (all.isEmpty) {
      return const AssistantTurn('Henüz seninle ilgili kayıtlı bir bilgim yok. Benimle konuştukça seni tanıyacağım.', MessageSource.memory);
    }
    if (q.listAll) {
      final byCat = <FactCategory, List<String>>{};
      for (final f in all) {
        byCat.putIfAbsent(f.category, () => []).add(f.text);
      }
      final parts = byCat.entries.take(8).map((e) => '${e.key.label}: ${e.value.take(3).join(', ')}');
      return AssistantTurn('Senin hakkında bildiklerim — ${parts.join('. ')}.', MessageSource.memory);
    }
    if (q.category != null) {
      final inCat = all.where((f) => f.category == q.category).toList();
      if (inCat.isEmpty) return AssistantTurn('${q.category!.label} hakkında kayıtlı bir bilgim yok.', MessageSource.memory);
      return AssistantTurn('${q.category!.label}: ${inCat.map((f) => f.text).join(', ')}.', MessageSource.memory);
    }
    final found = await facts.search(q.query, limit: 3);
    if (found.isEmpty) return const AssistantTurn('Bununla ilgili kayıtlı bir bilgi bulamadım.', MessageSource.memory);
    return AssistantTurn('Kayıtlarıma göre: ${found.map((f) => f.category == FactCategory.other ? f.text : '${f.category.label}: ${f.text}').join('. ')}.', MessageSource.memory);
  }

  Future<AssistantTurn> _general(GeneralIntent intent, String text, List<ChatMessage> history) async {
    final decision = router.decide(intent, await routeContext());
    return switch (decision) {
      UseBrain(brain: Brain.localLlm) => _local(text, history),
      UseBrain(brain: Brain.cloud) => _cloud(text, history, webSearch: intent.needsInternet),
      UseBrain() => _local(text, history),
      AskCloudConsent(:final localAlternative) => AssistantTurn(
          intent.needsInternet
              ? 'Bu soru güncel bilgi gerektiriyor. Etkin bulut sağlayıcısına göndermemi onaylıyor musun? (Ücret sağlayıcıya göre sana aittir.)'
              : 'Bu soruyu etkin bulut sağlayıcısına göndermemi onaylıyor musun? (Ücret sağlayıcıya göre sana aittir.)',
          MessageSource.system,
          pending: ConfirmCloud(userText: text, webSearch: intent.needsInternet, localAlternative: localAlternative),
        ),
      Unavailable(:final reason) => AssistantTurn(_unavailableText(reason, intent), MessageSource.system),
    };
  }

  List<LlmMessage> _history(List<ChatMessage> history, String text, int turns) {
    final relevant = history.where((m) => m.source != MessageSource.system && m.role != ChatRole.system).toList();
    if (relevant.isNotEmpty && relevant.last.isUser && relevant.last.text == text) relevant.removeLast();
    final tail = relevant.length > turns ? relevant.sublist(relevant.length - turns) : relevant;
    return [
      for (final m in tail) LlmMessage(m.isUser ? LlmRole.user : LlmRole.assistant, m.text),
      LlmMessage(LlmRole.user, text),
    ];
  }

  /// İlgili kayıtlı bilgiler sistem istemine eklenir (yerelde her zaman; bulutta yalnızca izinle).
  Future<String> _instructions(String text, {required bool cloud}) async {
    if (cloud && !shareFactsWithCloud()) return saklazInstructions;
    final relevant = await facts.search(text, limit: 4);
    if (relevant.isEmpty) return saklazInstructions;
    return '$saklazInstructions\nSeninle konuşan kişi hakkında hafızandaki bilgiler (bunlar KULLANICIYA aittir, sana değil):\n'
        '${relevant.map((f) => '- ${f.category.label}: ${f.text}').join('\n')}\n'
        "Kullanıcıya 'sen' diye hitap et. Örnek: 'Sen ... üzerinde çalışıyorsun.'";
  }

  Future<AssistantTurn> _local(String text, List<ChatMessage> history) async {
    final r = await LocalLlmClient(localLlm).complete(LlmRequest(
      instructions: await _instructions(text, cloud: false),
      messages: _history(history, text, 6),
      maxOutputTokens: 384,
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
      instructions: await _instructions(text, cloud: true),
      messages: _history(history, text, historyTurns),
      webSearch: webSearch,
    ));
    return r.fold(
      (reply) => AssistantTurn(cleanModelText(reply.text), MessageSource.cloud),
      (f) => AssistantTurn('Bulut sağlayıcısına ulaşılamadı: ${f.message}', MessageSource.system),
    );
  }

  String _unavailableText(UnavailableReason r, LocalIntent? intent) {
    final web = intent is GeneralIntent && intent.needsInternet;
    return switch (r) {
      UnavailableReason.offline => web
          ? 'Bu soru güncel bilgi gerektiriyor ama şu an internet bağlantısı yok. Yerel özellikler çalışmaya devam ediyor.'
          : 'Yerel model henüz yüklü değil ve internet bağlantısı yok. Ayarlar > Model Yönetimi\'nden bir model indirebilirsin.',
      UnavailableReason.cloudNotConfigured || UnavailableReason.cloudDisabled => web
          ? 'Bu soru güncel internet bilgisi gerektiriyor. Yerel model internete erişemez; istersen Ayarlar > API Sağlayıcıları\'ndan bir bulut sağlayıcısı etkinleştirebilirsin.'
          : 'Yerel model henüz yüklü değil. Ayarlar > Model Yönetimi\'nden bir model indirip yükleyebilirsin.',
      UnavailableReason.noLocalModel => 'Yerel model henüz yüklü değil. Ayarlar > Model Yönetimi\'nden bir model indirip yükleyebilirsin.',
    };
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static const _months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  static const _days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
}
