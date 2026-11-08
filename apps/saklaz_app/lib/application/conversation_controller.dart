import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../infrastructure/providers.dart';
import 'assistant_provider.dart';
import 'local_ai_controller.dart';
import 'settings_controller.dart';

class ConversationState {
  const ConversationState({
    this.messages = const [],
    this.voice = const VoiceState(),
    this.conversationActive = false,
    this.busy = false,
    this.pending,
    this.lastInvocation,
    this.notice,
    this.externalLaunches = 0,
  });

  /// Asistanın başka bir uygulamayı açtığı işlem sayısı (yan tuş paneli bununla kapanır).
  final int externalLaunches;

  final List<ChatMessage> messages;
  final VoiceState voice;
  final bool conversationActive;
  final bool busy;
  final PendingAction? pending;
  final AssistInvocation? lastInvocation;
  final String? notice;

  ConversationState copyWith({
    List<ChatMessage>? messages,
    VoiceState? voice,
    bool? conversationActive,
    bool? busy,
    PendingAction? pending,
    bool clearPending = false,
    AssistInvocation? lastInvocation,
    String? notice,
    bool clearNotice = false,
    int? externalLaunches,
  }) =>
      ConversationState(
        externalLaunches: externalLaunches ?? this.externalLaunches,
        messages: messages ?? this.messages,
        voice: voice ?? this.voice,
        conversationActive: conversationActive ?? this.conversationActive,
        busy: busy ?? this.busy,
        pending: clearPending ? null : (pending ?? this.pending),
        lastInvocation: lastInvocation ?? this.lastInvocation,
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

/// Ses oturumu + iki beyinli asistan + kalıcı konuşma geçmişi.
///
/// Mikrofon kuralları:
///  * Uygulama açıldığında mikrofon KAPALI.
///  * Yalnızca [startConversation] (kullanıcı eylemi) mikrofonu açar.
///  * [stopConversation] tanımayı ve konuşmayı tamamen sonlandırır.
///  * Uygulama arka plana geçince ([onAppBackgrounded]) konuşma modu kapanır.
class ConversationController extends Notifier<ConversationState> {
  static const _tag = 'Conversation';
  static const maxSilentRetries = 2;
  int _silentRetries = 0;
  int _seq = 0;

  VoiceSession get _voice => ref.read(voiceSessionProvider);
  AppLogger get _log => ref.read(loggerProvider);

  @override
  ConversationState build() {
    final voice = ref.watch(voiceSessionProvider);
    final platform = ref.watch(assistantPlatformProvider);
    final repo = ref.watch(memoryProvider).conversations;

    final subs = <StreamSubscription<Object?>>[
      voice.states.listen((v) => state = state.copyWith(voice: v)),
      voice.transcripts.listen((t) => unawaited(submitText(t, fromVoice: true))),
      voice.errors.listen(_onSpeechError),
      platform.invocations.listen(_onInvocation),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        unawaited(s.cancel());
      }
    });

    Future.microtask(() async {
      state = state.copyWith(messages: await repo.all());
      try {
        final pending = await platform.consumePendingInvocation();
        if (pending != null) _onInvocation(pending);
      } on Object catch (e) {
        _log.w(_tag, 'Bekleyen çağrı okunamadı', error: e);
      }
    });

    return ConversationState(voice: voice.state);
  }

  // ---------------------------------------------------------------- konuşma modu

  Future<void> startConversation() async {
    _silentRetries = 0;
    state = state.copyWith(conversationActive: true, clearNotice: true);
    _log.i(_tag, 'Konuşma modu başladı');
    await _listen();
  }

  Future<void> stopConversation({String? reason}) async {
    final wasActive = state.conversationActive;
    state = state.copyWith(conversationActive: false, notice: reason, clearNotice: reason == null);
    await _voice.cancelListening();
    await _voice.stopSpeaking();
    if (wasActive) _log.i(_tag, 'Konuşma modu durdu');
  }

  Future<void> onAppBackgrounded() async {
    if (state.conversationActive || _voice.state.micActive || _voice.isSpeaking) {
      await stopConversation(reason: 'Uygulama arka plana geçtiği için konuşma durduruldu.');
    }
  }

  /// Bekleyen karar varsa yalnızca sesle onaylanabiliyorsa dinlemeye devam eder.
  Future<void> _listen() async {
    final p = state.pending;
    if (!state.conversationActive || (p != null && !p.voiceConfirmable)) return;
    final r = await _voice.startListening(preferOnDevice: ref.read(settingsProvider).preferOnDeviceRecognition);
    if (!r.isOk) state = state.copyWith(conversationActive: false, notice: r.failureOrNull?.message);
  }

  void _onSpeechError(SpeechError e) {
    if (!state.conversationActive) return;
    if ((e.code == 6 || e.code == 7) && _silentRetries < maxSilentRetries) {
      _silentRetries++;
      unawaited(_listen());
      return;
    }
    unawaited(stopConversation(
      reason: e.code == 6 || e.code == 7 ? 'Ses algılanmadığı için konuşma durduruldu.' : 'Konuşma durduruldu: ${e.message}',
    ));
  }

  void _onInvocation(AssistInvocation inv) {
    _log.i(_tag, 'Asistan çağrıldı: ${inv.source.name}');
    state = state.copyWith(lastInvocation: inv, clearPending: true, clearNotice: true);
    // Yan tuş paneli: kullanıcı bilinçli olarak çağırdı -> hemen dinle.
    if (ref.read(isOverlayProvider) || ref.read(settingsProvider).listenOnAssistInvoke) unawaited(startConversation());
  }

  // ---------------------------------------------------------------- mesajlar

  Future<void> submitText(String text, {bool fromVoice = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.busy) return;
    _silentRetries = 0;

    // Bekleyen karar + "evet/hayır" yanıtı
    final p = state.pending;
    if (p != null) {
      final yn = YesNo.parse(trimmed);
      if (yn != null) {
        await _addMessage(ChatRole.user, trimmed, MessageSource.user);
        if (fromVoice && !p.voiceConfirmable && yn) {
          await _deliver(const AssistantTurn('Bu işlem için güvenlik gereği ekrandaki "Onayla" düğmesine dokunman gerekiyor.', MessageSource.system), keepPending: true);
          return;
        }
        await resolvePending(accept: yn, alreadyEchoed: true);
        return;
      }
    }

    await _addMessage(ChatRole.user, trimmed, MessageSource.user);
    state = state.copyWith(busy: true, clearPending: true);
    _voice.markThinking();

    AssistantTurn turn;
    try {
      turn = await ref.read(assistantProvider).respond(trimmed, state.messages);
      // "Söylediğimi yap": orta riskli işlemler ayar açıksa sormadan uygulanır.
      if (turn.pending case ConfirmAgentAction(:final action)
          when action.risk != RiskLevel.high && ref.read(settingsProvider).autoConfirmMedium) {
        _log.log(LogLevel.audit, _tag, 'Agent eylemi otomatik uygulandı: ${action.runtimeType}');
        turn = await ref.read(assistantProvider).execute(action);
      }
    } on Object catch (e) {
      _log.e(_tag, 'Asistan hatası', error: e);
      turn = const AssistantTurn('Beklenmeyen bir hata oluştu.', MessageSource.system);
    }
    await _deliver(turn);
  }

  /// Bekleyen işlemi onayla/reddet.
  Future<void> resolvePending({required bool accept, bool preferLocal = false, bool alreadyEchoed = false}) async {
    final p = state.pending;
    if (p == null || state.busy) return;
    state = state.copyWith(clearPending: true, busy: true);
    _voice.markThinking();
    final assistant = ref.read(assistantProvider);
    AssistantTurn turn;
    try {
      turn = switch (p) {
        ConfirmRemember() when accept => await assistant.confirmRemember(p),
        ConfirmRemember() => const AssistantTurn('Tamam, kaydetmedim.', MessageSource.memory),
        ConfirmCloud() when accept => await assistant.answerWithCloud(p, state.messages),
        ConfirmCloud() when preferLocal => await assistant.answerLocally(p, state.messages),
        ConfirmCloud() => const AssistantTurn('Tamam, göndermedim.', MessageSource.system),
        ConfirmAgentAction(:final action) when accept => await assistant.execute(action),
        ConfirmAgentAction() => const AssistantTurn('Tamam, iptal ettim.', MessageSource.localRules),
      };
      if (p is ConfirmAgentAction && accept) _log.log(LogLevel.audit, _tag, 'Agent eylemi onaylandı: ${p.action.runtimeType}');
    } on Object catch (e) {
      _log.e(_tag, 'Bekleyen işlem hatası', error: e);
      turn = AssistantTurn('İşlem tamamlanamadı: ${e is PermissionDenied ? 'izin gerekli' : 'beklenmeyen hata'}.', MessageSource.system);
    }
    await _deliver(turn);
  }

  /// Seçilen dosya veya fotoğrafı yerel olarak analiz ettir (metin/etiketler cihazda çıkarıldı).
  Future<void> analyzeDocument(DocumentContent doc) async {
    final name = doc.name ?? (doc.kind == 'image' ? 'Fotoğraf' : 'Belge');
    final body = doc.text.trim();
    final excerpt = body.length > 3000 ? '${body.substring(0, 3000)}…' : body;
    final String prompt;
    if (doc.kind == 'image') {
      prompt = 'Bir fotoğraf paylaştım. Cihaz içi görüntü analizi şunları buldu: '
          '${doc.labels.isEmpty ? 'belirgin nesne yok' : doc.labels.join(', ')}.'
          '${excerpt.isEmpty ? '' : ' Fotoğraftaki yazı: "$excerpt".'} Bunu kısaca Türkçe açıkla.';
    } else {
      if (excerpt.isEmpty) {
        await _addMessage(ChatRole.user, '📄 $name', MessageSource.user);
        await _deliver(const AssistantTurn('Bu dosyadan okunabilir metin çıkarılamadı.', MessageSource.system));
        return;
      }
      prompt = 'Şu belgeyi kısaca özetle ve önemli noktalarını söyle:\n$excerpt';
    }
    await _addMessage(ChatRole.user, '${doc.kind == 'image' ? '🖼' : '📄'} $name\n${excerpt.length > 300 ? '${excerpt.substring(0, 300)}…' : excerpt}', MessageSource.user);
    state = state.copyWith(busy: true, clearPending: true);
    _voice.markThinking();
    AssistantTurn turn;
    try {
      turn = await ref.read(assistantProvider).respond(prompt, const []);
    } on Object catch (e) {
      _log.e(_tag, 'Belge analizi hatası', error: e);
      turn = const AssistantTurn('Belge analiz edilemedi.', MessageSource.system);
    }
    await _deliver(turn);
  }

  Future<void> _addMessage(ChatRole role, String text, MessageSource source) async {
    final repo = ref.read(memoryProvider).conversations;
    await repo.add(_msg(role, text, source));
    state = state.copyWith(messages: await repo.all());
  }

  Future<void> _deliver(AssistantTurn turn, {bool keepPending = false}) async {
    final repo = ref.read(memoryProvider).conversations;
    final pending = keepPending ? state.pending : turn.pending;
    await repo.add(_msg(ChatRole.assistant, turn.text, turn.source));
    if (turn.learned.isNotEmpty) {
      await repo.add(_msg(
        ChatRole.system,
        '🧠 Hafızama ekledim: ${turn.learned.map((f) => '${f.category.label} — ${f.text}').join('; ')}',
        MessageSource.memory,
      ));
    }
    state = state.copyWith(messages: await repo.all(), busy: false, pending: pending, clearPending: pending == null);
    unawaited(ref.read(localAiProvider.notifier).syncStatus());
    if (turn.openedExternalApp) {
      // Başka bir uygulama açıldı: mikrofonu kapat, panel kapanabilir.
      state = state.copyWith(externalLaunches: state.externalLaunches + 1, conversationActive: false);
      await _voice.cancelListening();
      _voice.markIdle();
      return;
    }

    final s = ref.read(settingsProvider);
    if (s.voiceReplies) {
      try {
        await _voice.speakToEnd(turn.text, rate: s.speechRate, pitch: s.speechPitch);
      } on Object catch (e) {
        _log.w(_tag, 'Sesli yanıt başarısız', error: e);
        _voice.markIdle();
      }
    } else {
      _voice.markIdle();
    }
    if (state.conversationActive) await _listen();
  }

  Future<void> replay(ChatMessage m) async {
    if (state.voice.micActive) await _voice.cancelListening();
    final s = ref.read(settingsProvider);
    await _voice.speak(m.text, rate: s.speechRate, pitch: s.speechPitch);
  }

  Future<void> stopSpeaking() => _voice.stopSpeaking();

  Future<void> clearHistory() async {
    await ref.read(memoryProvider).conversations.clear();
    state = state.copyWith(messages: const [], clearPending: true);
  }

  ChatMessage _msg(ChatRole role, String text, MessageSource source) => ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
        role: role,
        text: text,
        source: source,
        createdAt: DateTime.now(),
      );
}

final conversationProvider = NotifierProvider<ConversationController, ConversationState>(ConversationController.new);
