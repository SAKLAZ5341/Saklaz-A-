import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../infrastructure/providers.dart';
import 'assistant_provider.dart';
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
  });

  final List<ChatMessage> messages;
  final VoiceState voice;

  /// "Konuşmayı Başlat" ile açılan sürekli konuşma modu.
  final bool conversationActive;

  /// Yanıt hazırlanıyor.
  final bool busy;

  /// Kullanıcı kararı bekleyen işlem (hafızaya kayıt / bulut izni).
  final PendingAction? pending;
  final AssistInvocation? lastInvocation;

  /// Konuşma modunun neden durduğu gibi kısa bilgi.
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
  }) =>
      ConversationState(
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

  /// Art arda sessizlik/anlaşılamama hatasında konuşma modu kapanır.
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
      voice.transcripts.listen((t) => unawaited(submitText(t))),
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
    if (wasActive) _log.i(_tag, 'Konuşma modu durdu${reason == null ? '' : ': $reason'}');
  }

  /// Uygulama arka plana geçti: mikrofon güvenlik gereği kapanır.
  Future<void> onAppBackgrounded() async {
    if (state.conversationActive || _voice.state.micActive || _voice.isSpeaking) {
      await stopConversation(reason: 'Uygulama arka plana geçtiği için konuşma durduruldu.');
    }
  }

  Future<void> _listen() async {
    if (!state.conversationActive || state.pending != null) return;
    final r = await _voice.startListening(preferOnDevice: ref.read(settingsProvider).preferOnDeviceRecognition);
    if (!r.isOk) {
      state = state.copyWith(conversationActive: false, notice: r.failureOrNull?.message);
    }
  }

  void _onSpeechError(SpeechError e) {
    if (!state.conversationActive) return;
    // 6: ERROR_SPEECH_TIMEOUT, 7: ERROR_NO_MATCH -> birkaç kez yeniden dinle.
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
    state = state.copyWith(lastInvocation: inv);
    if (ref.read(settingsProvider).listenOnAssistInvoke) unawaited(startConversation());
  }

  // ---------------------------------------------------------------- mesajlar

  Future<void> submitText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.busy) return;
    _silentRetries = 0;
    final repo = ref.read(memoryProvider).conversations;
    await repo.add(_msg(ChatRole.user, trimmed, MessageSource.user));
    state = state.copyWith(messages: await repo.all(), busy: true, clearPending: true);
    _voice.markThinking();

    AssistantTurn turn;
    try {
      turn = await ref.read(assistantProvider).respond(trimmed, state.messages);
    } on Object catch (e) {
      _log.e(_tag, 'Asistan hatası', error: e);
      turn = const AssistantTurn('Beklenmeyen bir hata oluştu.', MessageSource.system);
    }
    await _deliver(turn);
  }

  /// Bekleyen işlemi onayla/reddet.
  Future<void> resolvePending({required bool accept, bool preferLocal = false}) async {
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
        ConfirmCloud() => const AssistantTurn('Tamam, buluta göndermedim.', MessageSource.system),
      };
    } on Object catch (e) {
      _log.e(_tag, 'Bekleyen işlem hatası', error: e);
      turn = const AssistantTurn('Beklenmeyen bir hata oluştu.', MessageSource.system);
    }
    await _deliver(turn);
  }

  Future<void> _deliver(AssistantTurn turn) async {
    final repo = ref.read(memoryProvider).conversations;
    await repo.add(_msg(ChatRole.assistant, turn.text, turn.source));
    state = state.copyWith(messages: await repo.all(), busy: false, pending: turn.pending);

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
    // Konuşma modu sürüyorsa ve karar bekleyen işlem yoksa tekrar dinle.
    if (state.conversationActive && state.pending == null) await _listen();
  }

  /// Bir yanıtı tekrar sesli dinlet (sesli yanıt kapalı olsa bile kullanıcı ister).
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

final conversationProvider =
    NotifierProvider<ConversationController, ConversationState>(ConversationController.new);
