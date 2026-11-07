import 'dart:async';

import 'package:saklaz_voice/saklaz_voice.dart';

import 'generated/saklaz_api.g.dart' as g;

class AndroidMicrophonePermission implements MicrophonePermissionPort {
  AndroidMicrophonePermission({g.PermissionHostApi? api}) : _api = api ?? g.PermissionHostApi();
  final g.PermissionHostApi _api;

  static MicPermission _map(g.MicPermissionState s) => switch (s) {
        g.MicPermissionState.granted => MicPermission.granted,
        g.MicPermissionState.denied => MicPermission.denied,
        g.MicPermissionState.permanentlyDenied => MicPermission.permanentlyDenied,
      };

  @override
  Future<MicPermission> current() async => _map(await _api.getMicrophonePermission());

  @override
  Future<MicPermission> request() async => _map(await _api.requestMicrophonePermission());

  @override
  Future<void> openAppSettings() => _api.openAppSettings();
}

class AndroidSpeechRecognizer implements SpeechRecognizerPort, g.SpeechFlutterApi {
  AndroidSpeechRecognizer({g.SpeechHostApi? api}) : _api = api ?? g.SpeechHostApi() {
    g.SpeechFlutterApi.setUp(this);
  }

  final g.SpeechHostApi _api;
  final _events = StreamController<SpeechEvent>.broadcast();

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<SpeechEngineInfo> engineInfo() async {
    final i = await _api.getEngineInfo();
    return SpeechEngineInfo(available: i.available, onDevice: i.onDevice, engine: i.engineComponent);
  }

  @override
  Future<void> start({required String localeTag, required bool preferOnDevice}) =>
      _api.startListening(localeTag, preferOnDevice);

  @override
  Future<void> stop() => _api.stopListening();

  @override
  Future<void> cancel() => _api.cancel();

  @override
  void onSpeechEvent(g.SpeechEventMessage e) {
    final mapped = switch (e.type) {
      g.SpeechEventType.readyForSpeech => const SpeechReady(),
      g.SpeechEventType.beginningOfSpeech => const SpeechBegan(),
      g.SpeechEventType.rmsChanged => SpeechLevel(e.rmsDb ?? 0),
      g.SpeechEventType.partialResult => SpeechPartial(e.text ?? ''),
      g.SpeechEventType.finalResult => SpeechFinal(e.text ?? ''),
      g.SpeechEventType.endOfSpeech => const SpeechEnded(),
      g.SpeechEventType.error =>
        SpeechError(e.errorCode ?? -1, e.errorMessage ?? 'Konuşma tanıma hatası'),
    };
    _events.add(mapped);
  }
}

class AndroidSpeechSynthesizer implements SpeechSynthesizerPort, g.TtsFlutterApi {
  AndroidSpeechSynthesizer({g.TtsHostApi? api}) : _api = api ?? g.TtsHostApi() {
    g.TtsFlutterApi.setUp(this);
  }

  final g.TtsHostApi _api;
  final _events = StreamController<TtsEvent>.broadcast();

  @override
  Stream<TtsEvent> get events => _events.stream;

  @override
  Future<TtsInitResult> initialize(String localeTag) async {
    final r = await _api.initialize(localeTag);
    return TtsInitResult(ready: r.ready, languageSupported: r.languageSupported, engine: r.engine);
  }

  @override
  Future<void> speak(String utteranceId, String text, {required double rate, required double pitch}) =>
      _api.speak(utteranceId, text, rate, pitch);

  @override
  Future<void> stop() => _api.stop();

  @override
  void onTtsEvent(g.TtsEventMessage e) {
    final kind = switch (e.type) {
      g.TtsEventType.started => TtsEventKind.started,
      g.TtsEventType.done => TtsEventKind.done,
      g.TtsEventType.stopped => TtsEventKind.stopped,
      g.TtsEventType.error => TtsEventKind.error,
    };
    _events.add(TtsEvent(kind, e.utteranceId));
  }
}
