// Composition root: somut uygulamalar YALNIZCA burada bağlanır.
// Testler bu sağlayıcıları ProviderScope.overrides ile sahtelerle değiştirir.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

final loggerProvider = Provider<MemoryLogger>(
  (ref) => MemoryLogger(sink: kDebugMode ? (r) => debugPrint(r.toString()) : null),
);

final assistantPlatformProvider = Provider<AssistantPlatform>((ref) => AndroidAssistantPlatform());

final micPermissionProvider = Provider<MicrophonePermissionPort>((ref) => AndroidMicrophonePermission());

final speechRecognizerProvider = Provider<SpeechRecognizerPort>((ref) => AndroidSpeechRecognizer());

final speechSynthesizerProvider = Provider<SpeechSynthesizerPort>((ref) => AndroidSpeechSynthesizer());

final assistantBrainProvider = Provider<AssistantBrain>((ref) => OfflinePlaceholderBrain());

final conversationRepositoryProvider =
    Provider<ConversationRepository>((ref) => InMemoryConversationRepository());

final voiceSessionProvider = Provider<VoiceSession>((ref) {
  final session = VoiceSession(
    recognizer: ref.watch(speechRecognizerProvider),
    synthesizer: ref.watch(speechSynthesizerProvider),
    permission: ref.watch(micPermissionProvider),
    logger: ref.watch(loggerProvider),
  );
  ref.onDispose(session.dispose);
  return session;
});
