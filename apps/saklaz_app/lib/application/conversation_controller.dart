import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../infrastructure/providers.dart';
import 'settings_controller.dart';

class ConversationState {
  const ConversationState({
    this.messages = const [],
    this.voice = const VoiceState(),
    this.lastInvocation,
  });

  final List<ChatMessage> messages;
  final VoiceState voice;
  final AssistInvocation? lastInvocation;

  ConversationState copyWith({
    List<ChatMessage>? messages,
    VoiceState? voice,
    AssistInvocation? lastInvocation,
  }) =>
      ConversationState(
        messages: messages ?? this.messages,
        voice: voice ?? this.voice,
        lastInvocation: lastInvocation ?? this.lastInvocation,
      );
}

/// Ses oturumu, asistan beyni ve konuşma geçmişini birleştiren uygulama servisi.
class ConversationController extends Notifier<ConversationState> {
  static const _tag = 'Conversation';
  int _seq = 0;

  VoiceSession get _voice => ref.read(voiceSessionProvider);

  @override
  ConversationState build() {
    final voice = ref.watch(voiceSessionProvider);
    final platform = ref.watch(assistantPlatformProvider);

    final subs = <StreamSubscription<Object?>>[
      voice.states.listen((v) => state = state.copyWith(voice: v)),
      voice.transcripts.listen(submitText),
      platform.invocations.listen(_onInvocation),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        unawaited(s.cancel());
      }
    });

    // Soğuk açılış: yan tuşla açıldıysa bekleyen çağrıyı al.
    Future.microtask(() async {
      try {
        final pending = await platform.consumePendingInvocation();
        if (pending != null) _onInvocation(pending);
      } on Object catch (e) {
        ref.read(loggerProvider).w(_tag, 'Bekleyen çağrı okunamadı', error: e);
      }
    });

    return ConversationState(voice: voice.state);
  }

  void _onInvocation(AssistInvocation inv) {
    ref.read(loggerProvider).i(_tag, 'Asistan çağrıldı: ${inv.source.name}');
    state = state.copyWith(lastInvocation: inv);
    if (ref.read(settingsProvider).listenOnAssistInvoke) {
      unawaited(startListening());
    }
  }

  Future<void> startListening() async {
    await _voice.startListening(
      preferOnDevice: ref.read(settingsProvider).preferOnDeviceRecognition,
    );
  }

  Future<void> stopListening() => _voice.stopListening();
  Future<void> cancelListening() => _voice.cancelListening();
  Future<void> stopSpeaking() => _voice.stopSpeaking();

  /// Mikrofon düğmesi: kapalıysa açar, açıksa kapatır, konuşuyorsa susturur.
  Future<void> toggleMic() async {
    switch (_voice.state.phase) {
      case VoicePhase.listening:
        await stopListening();
      case VoicePhase.speaking:
        await stopSpeaking();
      case VoicePhase.idle || VoicePhase.thinking:
        await startListening();
      case VoicePhase.requestingPermission:
        break;
    }
  }

  Future<void> submitText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final repo = ref.read(conversationRepositoryProvider);
    final brain = ref.read(assistantBrainProvider);

    await repo.add(_msg(ChatRole.user, trimmed));
    state = state.copyWith(messages: await repo.all());

    _voice.markThinking();
    final result = await brain.reply(trimmed, state.messages);
    final reply = result.fold((v) => v, (f) => 'Bir sorun oluştu: ${f.message}');
    await repo.add(_msg(ChatRole.assistant, reply));
    state = state.copyWith(messages: await repo.all());

    final settings = ref.read(settingsProvider);
    if (settings.voiceReplies) {
      try {
        await _voice.speak(reply, rate: settings.speechRate, pitch: settings.speechPitch);
      } on Object catch (e) {
        ref.read(loggerProvider).w(_tag, 'Sesli yanıt başarısız', error: e);
        _voice.markIdle();
      }
    } else {
      _voice.markIdle();
    }
  }

  Future<void> clearHistory() async {
    await ref.read(conversationRepositoryProvider).clear();
    state = state.copyWith(messages: const []);
  }

  ChatMessage _msg(ChatRole role, String text) => ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
        role: role,
        text: text,
        createdAt: DateTime.now(),
      );
}

final conversationProvider =
    NotifierProvider<ConversationController, ConversationState>(ConversationController.new);
