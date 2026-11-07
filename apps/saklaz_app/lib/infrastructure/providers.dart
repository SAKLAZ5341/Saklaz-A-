// Composition root: somut uygulamalar YALNIZCA burada bağlanır.
// Testler bu sağlayıcıları ProviderScope.overrides ile sahtelerle değiştirir.
import 'dart:io';

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

// ---- Platform (Android) ----

final assistantPlatformProvider = Provider<AssistantPlatform>((ref) => AndroidAssistantPlatform());
final micPermissionProvider = Provider<MicrophonePermissionPort>((ref) => AndroidMicrophonePermission());
final speechRecognizerProvider = Provider<SpeechRecognizerPort>((ref) => AndroidSpeechRecognizer());
final speechSynthesizerProvider = Provider<SpeechSynthesizerPort>((ref) => AndroidSpeechSynthesizer());
final keyVaultProvider = Provider<KeyVault>((ref) => AndroidKeyVault());
final networkStatusProvider = Provider<NetworkStatus>((ref) => AndroidNetworkStatus());
final localLlmProvider = Provider<LocalLlm>((ref) => AndroidLocalLlm());
final httpTransportProvider = Provider<HttpTransport>((ref) => IoHttpTransport());

// ---- Hafıza ----

/// Açılmış hafıza depoları ve şifreleme durumu.
class MemoryStores {
  const MemoryStores({
    required this.conversations,
    required this.facts,
    required this.preferences,
    required this.initialPreferences,
    required this.encrypted,
    this.cipherVersion,
    this.hardwareBackedKey = false,
    this.error,
  });

  final ConversationRepository conversations;
  final FactRepository facts;
  final PreferencesStore preferences;
  final Map<String, String> initialPreferences;

  /// Şifreli kalıcı depolama etkin mi? false ise her şey yalnızca RAM'de.
  final bool encrypted;
  final String? cipherVersion;
  final bool hardwareBackedKey;

  /// Şifreli depolama açılamadıysa nedeni (kullanıcıya gösterilir).
  final String? error;

  static MemoryStores inMemory({String? error}) => MemoryStores(
        conversations: InMemoryConversationRepository(),
        facts: InMemoryFactRepository(),
        preferences: InMemoryPreferencesStore(),
        initialPreferences: const {},
        encrypted: false,
        error: error,
      );
}

/// Şifreli hafızayı açar. Şifreleme doğrulanamazsa diske HİÇBİR ŞEY yazmaz
/// (fail-closed) ve bellek içi depolarla devam eder.
final memoryStoresProvider = FutureProvider<MemoryStores>((ref) async {
  final log = ref.read(loggerProvider);
  try {
    final key = await ref.read(keyVaultProvider).databaseKey();
    final db = EncryptedMemoryDatabase.open('${key.directory}${Platform.pathSeparator}saklaz_memory.db', hexKey: key.hexKey);
    ref.onDispose(db.close);
    log.i('Memory', 'Şifreli hafıza açıldı (${db.cipherVersion}, donanım anahtarı=${key.hardwareBacked})');
    return MemoryStores(
      conversations: db,
      facts: db.facts,
      preferences: db,
      initialPreferences: await db.readAll(),
      encrypted: true,
      cipherVersion: db.cipherVersion,
      hardwareBackedKey: key.hardwareBacked,
    );
  } on Object catch (e) {
    log.e('Memory', 'Şifreli hafıza açılamadı; bellek içi moda geçildi', error: e);
    return MemoryStores.inMemory(error: e is MemoryEncryptionUnavailable ? e.reason : 'Hafıza açılamadı');
  }
});

/// Bootstrap tamamlandıktan sonra eşzamanlı erişim.
final memoryProvider = Provider<MemoryStores>((ref) => ref.watch(memoryStoresProvider).requireValue);

// ---- Ses ----

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
