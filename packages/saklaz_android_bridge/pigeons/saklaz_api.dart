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

// ---------------------------------------------------------------------------
// Anahtar kasası (Phase 2): veritabanı anahtarı Android Keystore ile sarılır
// ---------------------------------------------------------------------------

class DatabaseKeyMessage {
  DatabaseKeyMessage({
    required this.hexKey,
    required this.hardwareBacked,
    required this.databaseDirectory,
  });

  /// 256-bit rastgele anahtar (hex). Diske yalnızca Keystore ile şifreli yazılır.
  String hexKey;

  /// Sarma anahtarı donanım destekli (TEE/StrongBox) ise true.
  bool hardwareBacked;

  /// Yedeklenmeyen uygulama özel dizini (noBackupFilesDir).
  String databaseDirectory;
}

@HostApi()
abstract class KeyVaultHostApi {
  DatabaseKeyMessage getOrCreateDatabaseKey();
}

// ---------------------------------------------------------------------------
// Ağ durumu
// ---------------------------------------------------------------------------

@HostApi()
abstract class NetworkHostApi {
  /// Doğrulanmış (VALIDATED) internet bağlantısı varsa true.
  bool isOnline();
}

// ---------------------------------------------------------------------------
// Yerel LLM (LiteRT-LM) + model yönetimi
// ---------------------------------------------------------------------------

class DeviceCapabilityMessage {
  DeviceCapabilityMessage({
    required this.totalRamMb,
    required this.availableRamMb,
    required this.lowRamDevice,
    required this.socManufacturer,
    required this.socModel,
    required this.abis,
    required this.sdkInt,
    required this.freeStorageMb,
  });
  int totalRamMb;
  int availableRamMb;
  bool lowRamDevice;
  String socManufacturer;
  String socModel;
  List<String> abis;
  int sdkInt;
  int freeStorageMb;
}

class ModelSpecMessage {
  ModelSpecMessage({
    required this.id,
    required this.url,
    required this.fileName,
    required this.sha256,
    required this.sizeBytes,
  });
  String id;
  String url;
  String fileName;
  String sha256;
  int sizeBytes;
}

class InstalledModelMessage {
  InstalledModelMessage({required this.fileName, required this.sizeBytes});
  String fileName;
  int sizeBytes;
}

enum DownloadState { running, verifying, completed, failed, cancelled }

class DownloadProgressMessage {
  DownloadProgressMessage({
    required this.id,
    required this.state,
    required this.receivedBytes,
    required this.totalBytes,
  });
  String id;
  DownloadState state;
  int receivedBytes;
  int totalBytes;
  String? error;
}

enum LlmEngineState { notLoaded, loading, ready, failed }

class LlmStatusMessage {
  LlmStatusMessage({required this.state});
  LlmEngineState state;
  String? fileName;
  String? backend;
  String? error;
  int? loadMillis;
}

class ChatTurnMessage {
  ChatTurnMessage({required this.fromUser, required this.text});
  bool fromUser;
  String text;
}

class LlmReplyMessage {
  LlmReplyMessage({required this.text, required this.millis});
  String text;
  int millis;
}

@HostApi()
abstract class ModelHostApi {
  DeviceCapabilityMessage getDeviceCapability();
  List<InstalledModelMessage> listInstalled();

  /// İndirmeyi başlatır (kaldığı yerden devam eder). İlerleme ModelFlutterApi ile gelir.
  /// Bitince SHA-256 doğrulanır; eşleşmezse dosya silinir.
  void startDownload(ModelSpecMessage spec);
  void cancelDownload(String id);
  void deleteModel(String fileName);
}

@FlutterApi()
abstract class ModelFlutterApi {
  void onDownloadProgress(DownloadProgressMessage progress);
}

@HostApi()
abstract class LocalLlmHostApi {
  LlmStatusMessage status();

  /// Modeli belleğe yükler. preferGpu ise önce GPU denenir, olmazsa CPU.
  @async
  LlmStatusMessage load(String fileName, bool preferGpu, int maxTokens);

  void unload();

  @async
  LlmReplyMessage generate(String systemPrompt, List<ChatTurnMessage> history, String userText, int maxOutputTokens);

  void cancel();
}

// ---------------------------------------------------------------------------
// Gizli anahtarlar (API anahtarları) — Android Keystore AES-GCM
// ---------------------------------------------------------------------------

@HostApi()
abstract class SecretsHostApi {
  void put(String name, String value);
  String? get(String name);
  void delete(String name);
  bool has(String name);
}

// ---------------------------------------------------------------------------
// Uygulamalar ve ayarlar
// ---------------------------------------------------------------------------

class AppMessage {
  AppMessage({required this.label, required this.packageName});
  String label;
  String packageName;
}

enum SettingsPage { wifi, bluetooth, display, sound, battery, location, apps, notifications, appDetails, main }

@HostApi()
abstract class AppsHostApi {
  List<AppMessage> findApps(String query, int limit);
  bool launchApp(String packageName);
  bool openSettings(SettingsPage page);
}

// ---------------------------------------------------------------------------
// Phase 3: Çalışma zamanı izinleri (rehber, takvim, bildirim)
// ---------------------------------------------------------------------------

enum RuntimePermission { contacts, calendar, notifications }

@HostApi()
abstract class RuntimePermissionHostApi {
  MicPermissionState check(RuntimePermission permission);

  @async
  MicPermissionState request(RuntimePermission permission);
}

// ---------------------------------------------------------------------------
// Phase 3: Telefon işlemleri (Agent). HEPSİ kullanıcı onayından SONRA çağrılır.
// ---------------------------------------------------------------------------

class ContactMessage {
  ContactMessage({required this.name, required this.phone});
  String name;
  String phone;
}

class CalendarEventMessage {
  CalendarEventMessage({
    required this.title,
    required this.beginMillis,
    required this.endMillis,
    required this.allDay,
  });
  String title;
  int beginMillis;
  int endMillis;
  bool allDay;
  String? location;
}

@HostApi()
abstract class PhoneActionsHostApi {
  /// READ_CONTACTS gerekir.
  List<ContactMessage> searchContacts(String query, int limit);

  /// Çevirici uygulamasını numarayla açar (arama kullanıcı tarafından başlatılır).
  bool openDialer(String phone);

  /// WhatsApp'ı hazır mesajla açar; gönder tuşuna kullanıcı basar.
  bool openWhatsApp(String phone, String text);

  /// Saat uygulamasında alarm kurar (AlarmClock.ACTION_SET_ALARM).
  bool setAlarm(int hour, int minute, String label);

  /// Takvim uygulamasında doldurulmuş etkinlik ekranını açar; kaydı kullanıcı yapar.
  bool insertCalendarEvent(String title, int beginMillis, int endMillis);

  /// READ_CALENDAR gerekir.
  List<CalendarEventMessage> readCalendar(int fromMillis, int toMillis);
}

// ---------------------------------------------------------------------------
// Phase 3: Hatırlatıcı zamanlayıcı (AlarmManager + bildirim)
// ---------------------------------------------------------------------------

class ReminderCapabilityMessage {
  ReminderCapabilityMessage({required this.exactAlarms, required this.notifications});

  /// Tam zamanlı alarm izni (Android 14+ ayarlardan verilir).
  bool exactAlarms;
  bool notifications;
}

@HostApi()
abstract class ReminderHostApi {
  ReminderCapabilityMessage capability();
  void schedule(int id, String text, int atMillis);
  void cancel(int id);
  void openExactAlarmSettings();
}

// ---------------------------------------------------------------------------
// Geliştirme kolaylığı: YALNIZCA debug yapısında adb ile gateway ayarı aktarımı
// ---------------------------------------------------------------------------

class DevConfigMessage {
  String? gatewayUrl;
  String? gatewayToken;
}

@HostApi()
abstract class DevConfigHostApi {
  DevConfigMessage? consumeDevConfig();
}

// ---------------------------------------------------------------------------
// Dosya okuma ve fotoğraf analizi (cihaz içi)
// ---------------------------------------------------------------------------

class DocumentResultMessage {
  DocumentResultMessage({required this.kind, required this.text, required this.labels});

  /// "image", "pdf", "text"
  String kind;
  String? name;

  /// OCR veya dosya metni (en fazla ~20.000 karakter).
  String text;

  /// Fotoğraf için cihaz içi görüntü etiketleri (ör. "Kedi 0.92").
  List<String> labels;
}

@HostApi()
abstract class FileHostApi {
  /// Kullanıcı dosya seçer (metin, PDF, görsel). Vazgeçerse null.
  @async
  DocumentResultMessage? pickAndRead();

  /// Kamera veya galeri: görüntü -> OCR + etiketler.
  @async
  DocumentResultMessage? captureImage(bool fromCamera);
}

// ---------------------------------------------------------------------------
// Bildirimler (NotificationListenerService) — yalnızca kullanıcı erişim verirse
// ---------------------------------------------------------------------------

class NotificationMessage {
  NotificationMessage({
    required this.key,
    required this.appName,
    required this.packageName,
    required this.title,
    required this.text,
    required this.postedMillis,
    required this.canReply,
  });
  String key;
  String appName;
  String packageName;
  String title;
  String text;
  int postedMillis;
  bool canReply;
}

@HostApi()
abstract class NotificationsHostApi {
  bool isAccessGranted();
  void openAccessSettings();
  List<NotificationMessage> recent(int limit);

  /// Bildirimdeki "Yanıtla" eylemiyle yanıt gönderir. YALNIZCA kullanıcı onayından sonra.
  bool reply(String key, String text);
}
