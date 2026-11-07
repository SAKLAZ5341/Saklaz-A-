// ignore_for_file: close_sinks
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_app/infrastructure/providers.dart';
import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

class FakePlatform implements AssistantPlatform {
  FakePlatform({this.held = false, this.pending});
  bool held;
  AssistInvocation? pending;
  int requests = 0;
  int settingsOpened = 0;
  final controller = StreamController<AssistInvocation>.broadcast();

  @override
  Stream<AssistInvocation> get invocations => controller.stream;
  @override
  Future<AssistantRoleStatus> roleStatus() async => AssistantRoleStatus(
        roleAvailable: true,
        roleHeld: held,
        voiceInteractionServiceActive: held,
        sdkInt: 36,
        device: 'samsung SM-F966B',
      );
  @override
  Future<bool> requestRole() async {
    requests++;
    return false; // Gerçek Android davranışı: ROLE_ASSISTANT istenemez.
  }

  @override
  Future<bool> openDefaultAssistantSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<AssistInvocation?> consumePendingInvocation() async {
    final p = pending;
    pending = null;
    return p;
  }
}

class FakeStt implements SpeechRecognizerPort {
  final controller = StreamController<SpeechEvent>.broadcast(sync: true);
  int starts = 0;
  int cancels = 0;
  @override
  Stream<SpeechEvent> get events => controller.stream;
  @override
  Future<SpeechEngineInfo> engineInfo() async => const SpeechEngineInfo(available: true, onDevice: true);
  @override
  Future<void> start({required String localeTag, required bool preferOnDevice}) async => starts++;
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async => cancels++;
}

/// TTS sahtesi: [autoComplete] true ise konuşma hemen "bitti" olayı üretir.
class FakeTts implements SpeechSynthesizerPort {
  final controller = StreamController<TtsEvent>.broadcast(sync: true);
  final spoken = <String>[];
  bool autoComplete = true;
  int stops = 0;
  @override
  Stream<TtsEvent> get events => controller.stream;
  @override
  Future<TtsInitResult> initialize(String localeTag) async => const TtsInitResult(ready: true, languageSupported: true);
  @override
  Future<void> speak(String id, String text, {required double rate, required double pitch}) async {
    spoken.add(text);
    if (autoComplete) scheduleMicrotask(() => controller.add(TtsEvent(TtsEventKind.done, id)));
  }

  @override
  Future<void> stop() async => stops++;
}

class FakePerm implements MicrophonePermissionPort {
  FakePerm([this.state = MicPermission.granted]);
  MicPermission state;
  @override
  Future<MicPermission> current() async => state;
  @override
  Future<MicPermission> request() async => state;
  @override
  Future<void> openAppSettings() async {}
}

class FakeNetwork implements NetworkStatus {
  bool online = true;
  @override
  Future<bool> isOnline() async => online;
}

/// Sahte gateway HTTP katmanı (MOCK — gerçek ağ yok).
class FakeTransport implements HttpTransport {
  final requests = <(String, Uri, String?)>[];
  String replyText = 'Bulut yanıtı';
  @override
  Future<HttpResult> send(String method, Uri url,
      {Map<String, String> headers = const {}, String? body, Duration timeout = const Duration(seconds: 30)}) async {
    requests.add((method, url, body));
    return HttpResult(200, jsonEncode({
      'text': replyText,
      'model': 'm',
      'usage': {'inputTokens': 1, 'outputTokens': 1},
    }));
  }
}

class FakeLocalLlm implements LocalLlm {
  bool ready = false;
  @override
  Future<LocalLlmInfo> info() async => LocalLlmInfo(ready ? LocalLlmState.ready : LocalLlmState.unavailable);
  @override
  Future<LocalLlmInfo> download() => info();
  @override
  Future<Result<String>> generate(String prompt, {int maxOutputTokens = 256, double temperature = 0.3}) async =>
      const Result.ok('yerel model yanıtı');
}

class Fakes {
  Fakes({Map<String, String> prefs = const {}}) : initialPrefs = Map.of(prefs);

  final platform = FakePlatform();
  final stt = FakeStt();
  final tts = FakeTts();
  final perm = FakePerm();
  final network = FakeNetwork();
  final transport = FakeTransport();
  final localLlm = FakeLocalLlm();
  final conversations = InMemoryConversationRepository();
  final facts = InMemoryFactRepository();
  final preferences = InMemoryPreferencesStore();
  final Map<String, String> initialPrefs;

  List<Override> get overrides => [
        assistantPlatformProvider.overrideWithValue(platform),
        speechRecognizerProvider.overrideWithValue(stt),
        speechSynthesizerProvider.overrideWithValue(tts),
        micPermissionProvider.overrideWithValue(perm),
        networkStatusProvider.overrideWithValue(network),
        httpTransportProvider.overrideWithValue(transport),
        localLlmProvider.overrideWithValue(localLlm),
        memoryStoresProvider.overrideWith((ref) async => MemoryStores(
              conversations: conversations,
              facts: facts,
              preferences: preferences,
              initialPreferences: initialPrefs,
              encrypted: true,
              cipherVersion: 'test',
            )),
      ];
}

const gatewayPrefs = {
  'gatewayUrl': 'https://gw.test',
  'gatewayToken': 'skz_test_token_0123456789',
  'cloudMode': 'ask',
};
