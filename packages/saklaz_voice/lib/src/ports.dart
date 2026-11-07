/// Platform katmanının (Android/Windows) uygulaması gereken arayüzler.
library;

enum MicPermission { granted, denied, permanentlyDenied }

abstract interface class MicrophonePermissionPort {
  Future<MicPermission> current();
  Future<MicPermission> request();
  Future<void> openAppSettings();
}

sealed class SpeechEvent {
  const SpeechEvent();
}

class SpeechReady extends SpeechEvent {
  const SpeechReady();
}

class SpeechBegan extends SpeechEvent {
  const SpeechBegan();
}

/// Mikrofon ses seviyesi (dB, yaklaşık -2..10 aralığı).
class SpeechLevel extends SpeechEvent {
  const SpeechLevel(this.rmsDb);
  final double rmsDb;
}

class SpeechPartial extends SpeechEvent {
  const SpeechPartial(this.text);
  final String text;
}

class SpeechFinal extends SpeechEvent {
  const SpeechFinal(this.text);
  final String text;
}

class SpeechEnded extends SpeechEvent {
  const SpeechEnded();
}

class SpeechError extends SpeechEvent {
  const SpeechError(this.code, this.message);
  final int code;
  final String message;
}

class SpeechEngineInfo {
  const SpeechEngineInfo({
    required this.available,
    required this.onDevice,
    this.engine,
  });
  final bool available;
  final bool onDevice;
  final String? engine;
}

abstract interface class SpeechRecognizerPort {
  Stream<SpeechEvent> get events;
  Future<SpeechEngineInfo> engineInfo();
  Future<void> start({required String localeTag, required bool preferOnDevice});
  Future<void> stop();
  Future<void> cancel();
}

class TtsInitResult {
  const TtsInitResult({
    required this.ready,
    required this.languageSupported,
    this.engine,
  });
  final bool ready;
  final bool languageSupported;
  final String? engine;
}

enum TtsEventKind { started, done, stopped, error }

class TtsEvent {
  const TtsEvent(this.kind, this.utteranceId);
  final TtsEventKind kind;
  final String utteranceId;
}

abstract interface class SpeechSynthesizerPort {
  Stream<TtsEvent> get events;
  Future<TtsInitResult> initialize(String localeTag);
  Future<void> speak(
    String utteranceId,
    String text, {
    required double rate,
    required double pitch,
  });
  Future<void> stop();
}
