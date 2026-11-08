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

/// Sahte bulut HTTP katmanı (MOCK — gerçek ağ yok). Chat Completions biçiminde yanıtlar.
class FakeTransport implements HttpTransport {
  final requests = <(String, Uri, String?)>[];
  String replyText = 'Bulut yanıtı';
  @override
  Future<HttpResult> send(String method, Uri url,
      {Map<String, String> headers = const {}, String? body, Duration timeout = const Duration(seconds: 30)}) async {
    requests.add((method, url, body));
    return HttpResult(200, jsonEncode({
      'choices': [
        {'message': {'content': replyText}},
      ],
    }));
  }
}

/// Sahte yerel model (MOCK). Gerçek motor ayrıca gerçek modelle doğrulanmıştır.
class FakeLocalLlm implements LocalLlm {
  bool ready = false;
  final systems = <String>[];
  @override
  Future<LocalLlmInfo> info() async => LocalLlmInfo(ready ? LocalLlmState.ready : LocalLlmState.noModel, modelName: ready ? 'fake.litertlm' : null);
  @override
  Future<Result<String>> chat({required String system, required List<LlmMessage> history, required String user, int maxOutputTokens = 384}) async {
    systems.add(system);
    return const Result.ok('yerel model yanıtı');
  }
}

class FakeModelManager implements ModelManager {
  final controller = StreamController<(String, DownloadStatus)>.broadcast();
  final downloads = <String>[];
  Set<String> installed = {};
  @override
  Future<DeviceCapability> capability() async =>
      const DeviceCapability(totalRamMb: 11800, availableRamMb: 6000, lowRamDevice: false, soc: 'Qualcomm SM8750', abis: ['arm64-v8a'], freeStorageMb: 200000);
  @override
  Future<Set<String>> installedFiles() async => installed;
  @override
  Stream<(String, DownloadStatus)> get progress => controller.stream;
  @override
  Future<void> download(ModelSpec spec) async => downloads.add(spec.id);
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> delete(ModelSpec spec) async => installed.remove(spec.fileName);
}

class FakeDevice extends NoDevice {
  final calls = <String>[];
  @override
  Future<bool> ensurePermission(DevicePermission p) async => true;
  @override
  Future<List<Contact>> searchContacts(String query) async => query == 'Ahmet' ? const [Contact('Ahmet', '05321112233')] : const [];
  @override
  Future<bool> openWhatsApp(String phone, String text) async {
    calls.add('wa:$phone:$text');
    return true;
  }

  @override
  Future<void> scheduleReminder(int id, String text, DateTime at) async => calls.add('rem:$text');
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
  final models = FakeModelManager();
  final device = FakeDevice();
  final secrets = InMemorySecretStore();
  final conversations = InMemoryConversationRepository();
  final facts = InMemoryFactRepository();
  final notes = InMemoryNoteRepository();
  final reminders = InMemoryReminderRepository();
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
        modelManagerProvider.overrideWithValue(models),
        devicePortsProvider.overrideWithValue(device),
        secretStoreProvider.overrideWithValue(secrets),
        memoryStoresProvider.overrideWith((ref) async => MemoryStores(
              conversations: conversations,
              facts: facts,
              notes: notes,
              reminders: reminders,
              preferences: preferences,
              initialPreferences: initialPrefs,
              encrypted: true,
              cipherVersion: 'test',
            )),
      ];
}

/// DeepSeek etkin + aktif + "her seferinde sor" (anahtar ayrıca secrets'a konur).
Map<String, String> cloudPrefs() => {
      'activeProvider': 'deepseek',
      'cloudConsent': 'ask',
      'providers': jsonEncode({
        'deepseek': {'enabled': true, 'baseUrl': '', 'model': ''},
      }),
    };
