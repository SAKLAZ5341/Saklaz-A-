// SAKLAZ AI — Kotlin <-> Dart köprü sözleşmesi (tek kaynak).
//
// Kod üretmek için (packages/saklaz_android_bridge klasöründe):
//   dart run pigeon --input pigeons/saklaz_api.dart
//
// Üretilen dosyalar elle DÜZENLENMEZ.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/saklaz_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        '../../apps/saklaz_app/android/app/src/main/kotlin/com/saklaz/assistant/bridge/SaklazApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.saklaz.assistant.bridge'),
    dartPackageName: 'saklaz_android_bridge',
  ),
)
// ---------------------------------------------------------------------------
// Asistan rolü
// ---------------------------------------------------------------------------

/// RoleManager'dan okunan gerçek durum. Uygulama bu değerleri tahmin etmez.
class AssistantRoleStatusMessage {
  AssistantRoleStatusMessage({
    required this.roleAvailable,
    required this.roleHeld,
    required this.voiceInteractionServiceActive,
    required this.sdkInt,
    required this.manufacturer,
    required this.model,
  });

  /// RoleManager.isRoleAvailable(ROLE_ASSISTANT)
  bool roleAvailable;

  /// RoleManager.isRoleHeld(ROLE_ASSISTANT)
  bool roleHeld;

  /// VoiceInteractionService.isActiveService(context, bizimServis)
  bool voiceInteractionServiceActive;

  int sdkInt;
  String manufacturer;
  String model;
}

enum RoleRequestOutcome {
  /// Rol alındı.
  granted,

  /// Kullanıcı reddetti veya sistem diyalog göstermedi (ROLE_ASSISTANT
  /// AOSP'de "requestable=false" olduğundan genellikle bu döner).
  notGranted,
}

@HostApi()
abstract class AssistantRoleHostApi {
  AssistantRoleStatusMessage getStatus();

  /// RoleManager.createRequestRoleIntent ile istek dener.
  @async
  RoleRequestOutcome requestRole();

  /// Varsayılan uygulamalar ayarlarını açar (kullanıcı "Dijital asistan
  /// uygulaması"nı buradan seçer). Açılabildiyse true.
  bool openDefaultAssistantSettings();
}

// ---------------------------------------------------------------------------
// Asistan çağrısı (yan tuş / ASSIST intent / VoiceInteractionSession)
// ---------------------------------------------------------------------------

enum AssistLaunchSource {
  /// VoiceInteractionSession.onShow (yan tuş, ana ekran tuşu uzun basma vb.)
  voiceInteractionSession,

  /// android.intent.action.ASSIST intent'i
  assistIntent,
}

class AssistLaunchMessage {
  AssistLaunchMessage({required this.source, required this.timestampMillis});
  AssistLaunchSource source;
  int timestampMillis;
}

@HostApi()
abstract class AssistLaunchHostApi {
  /// Dart hazır olmadan önce gelen (soğuk açılış) çağrıyı bir kez teslim eder.
  AssistLaunchMessage? consumePendingLaunch();
}

@FlutterApi()
abstract class AssistLaunchFlutterApi {
  void onAssistInvoked(AssistLaunchMessage launch);
}

// ---------------------------------------------------------------------------
// Mikrofon izni
// ---------------------------------------------------------------------------

enum MicPermissionState { granted, denied, permanentlyDenied }

@HostApi()
abstract class PermissionHostApi {
  MicPermissionState getMicrophonePermission();

  @async
  MicPermissionState requestMicrophonePermission();

  void openAppSettings();
}

// ---------------------------------------------------------------------------
// Konuşma tanıma (STT)
// ---------------------------------------------------------------------------

enum SpeechEventType {
  readyForSpeech,
  beginningOfSpeech,
  rmsChanged,
  partialResult,
  finalResult,
  endOfSpeech,
  error,
}

class SpeechEventMessage {
  SpeechEventMessage({required this.type});
  SpeechEventType type;
  String? text;
  double? rmsDb;
  int? errorCode;
  String? errorMessage;
}

class SpeechEngineInfoMessage {
  SpeechEngineInfoMessage({
    required this.available,
    required this.onDevice,
  });
  bool available;

  /// Cihaz üzerinde (çevrimdışı) tanıyıcı kullanılacaksa true.
  bool onDevice;

  /// Kullanılacak tanıma servisinin bileşen adı (bilgi amaçlı).
  String? engineComponent;
}

@HostApi()
abstract class SpeechHostApi {
  SpeechEngineInfoMessage getEngineInfo();

  /// Mikrofon YALNIZCA bu çağrıyla açılır. İzin yoksa hata döner.
  void startListening(String localeTag, bool preferOnDevice);

  void stopListening();

  void cancel();
}

@FlutterApi()
abstract class SpeechFlutterApi {
  void onSpeechEvent(SpeechEventMessage event);
}

// ---------------------------------------------------------------------------
// Konuşma sentezi (TTS)
// ---------------------------------------------------------------------------

class TtsInitResultMessage {
  TtsInitResultMessage({required this.ready, required this.languageSupported});
  bool ready;
  bool languageSupported;
  String? engine;
}

enum TtsEventType { started, done, stopped, error }

class TtsEventMessage {
  TtsEventMessage({required this.type, required this.utteranceId});
  TtsEventType type;
  String utteranceId;
}

@HostApi()
abstract class TtsHostApi {
  @async
  TtsInitResultMessage initialize(String localeTag);

  void speak(String utteranceId, String text, double rate, double pitch);

  void stop();
}

@FlutterApi()
abstract class TtsFlutterApi {
  void onTtsEvent(TtsEventMessage event);
}
