// ignore_for_file: close_sinks
import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_app/infrastructure/providers.dart';
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
  @override
  Stream<SpeechEvent> get events => controller.stream;
  @override
  Future<SpeechEngineInfo> engineInfo() async => const SpeechEngineInfo(available: true, onDevice: true);
  @override
  Future<void> start({required String localeTag, required bool preferOnDevice}) async => starts++;
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

class FakeTts implements SpeechSynthesizerPort {
  final controller = StreamController<TtsEvent>.broadcast(sync: true);
  final spoken = <String>[];
  @override
  Stream<TtsEvent> get events => controller.stream;
  @override
  Future<TtsInitResult> initialize(String localeTag) async =>
      const TtsInitResult(ready: true, languageSupported: true);
  @override
  Future<void> speak(String id, String text, {required double rate, required double pitch}) async =>
      spoken.add(text);
  @override
  Future<void> stop() async {}
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

class Fakes {
  final platform = FakePlatform();
  final stt = FakeStt();
  final tts = FakeTts();
  final perm = FakePerm();

  List<Override> get overrides => [
        assistantPlatformProvider.overrideWithValue(platform),
        speechRecognizerProvider.overrideWithValue(stt),
        speechSynthesizerProvider.overrideWithValue(tts),
        micPermissionProvider.overrideWithValue(perm),
      ];
}
