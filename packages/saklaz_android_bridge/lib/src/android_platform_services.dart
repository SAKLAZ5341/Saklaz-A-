import 'dart:async';

import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_core/saklaz_core.dart';

import 'generated/saklaz_api.g.dart' as g;

// ============================================================================ Anahtar kasası / ağ

class DatabaseKey {
  const DatabaseKey({required this.hexKey, required this.hardwareBacked, required this.directory});
  final String hexKey;
  final bool hardwareBacked;
  final String directory;
}

abstract interface class KeyVault {
  Future<DatabaseKey> databaseKey();
}

class AndroidKeyVault implements KeyVault {
  AndroidKeyVault({g.KeyVaultHostApi? api}) : _api = api ?? g.KeyVaultHostApi();
  final g.KeyVaultHostApi _api;

  @override
  Future<DatabaseKey> databaseKey() async {
    final m = await _api.getOrCreateDatabaseKey();
    return DatabaseKey(hexKey: m.hexKey, hardwareBacked: m.hardwareBacked, directory: m.databaseDirectory);
  }
}

abstract interface class NetworkStatus {
  Future<bool> isOnline();
}

class AndroidNetworkStatus implements NetworkStatus {
  AndroidNetworkStatus({g.NetworkHostApi? api}) : _api = api ?? g.NetworkHostApi();
  final g.NetworkHostApi _api;
  @override
  Future<bool> isOnline() => _api.isOnline();
}

/// API anahtarları: Android Keystore AES-GCM ile şifreli.
abstract interface class SecretStore {
  Future<void> put(String name, String value);
  Future<String?> get(String name);
  Future<void> delete(String name);
  Future<bool> has(String name);
}

class AndroidSecretStore implements SecretStore {
  AndroidSecretStore({g.SecretsHostApi? api}) : _api = api ?? g.SecretsHostApi();
  final g.SecretsHostApi _api;
  @override
  Future<void> put(String name, String value) => _api.put(name, value);
  @override
  Future<String?> get(String name) => _api.get(name);
  @override
  Future<void> delete(String name) => _api.delete(name);
  @override
  Future<bool> has(String name) => _api.has(name);
}

class InMemorySecretStore implements SecretStore {
  final _m = <String, String>{};
  @override
  Future<void> put(String name, String value) async => _m[name] = value;
  @override
  Future<String?> get(String name) async => _m[name];
  @override
  Future<void> delete(String name) async => _m.remove(name);
  @override
  Future<bool> has(String name) async => _m.containsKey(name);
}

// ============================================================================ Model yönetimi

class DeviceCapability {
  const DeviceCapability({
    required this.totalRamMb,
    required this.availableRamMb,
    required this.lowRamDevice,
    required this.soc,
    required this.abis,
    required this.freeStorageMb,
  });
  final int totalRamMb;
  final int availableRamMb;
  final bool lowRamDevice;
  final String soc;
  final List<String> abis;
  final int freeStorageMb;
}

/// İndirilebilir model tanımı (Hugging Face, lisans ve SHA-256 doğrulanmış).
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
    required this.fileName,
    required this.sha256,
    required this.sizeBytes,
    required this.license,
    required this.licenseUrl,
    required this.minRamMb,
    this.recommended = false,
  });
  final String id;
  final String name;
  final String description;
  final String url;
  final String fileName;
  final String sha256;
  final int sizeBytes;
  final String license;
  final String licenseUrl;
  final int minRamMb;
  final bool recommended;

  String get sizeLabel => '${(sizeBytes / 1e6).round()} MB';
}

enum DownloadPhase { idle, running, verifying, completed, failed, cancelled }

class DownloadStatus {
  const DownloadStatus(this.phase, {this.received = 0, this.total = 0, this.error});
  final DownloadPhase phase;
  final int received;
  final int total;
  final String? error;
  double get fraction => total == 0 ? 0 : (received / total).clamp(0, 1).toDouble();
}

abstract interface class ModelManager {
  Future<DeviceCapability> capability();
  Future<Set<String>> installedFiles();
  Stream<(String id, DownloadStatus status)> get progress;
  Future<void> download(ModelSpec spec);
  Future<void> cancel(String id);
  Future<void> delete(ModelSpec spec);
}

class AndroidModelManager implements ModelManager, g.ModelFlutterApi {
  AndroidModelManager({g.ModelHostApi? api}) : _api = api ?? g.ModelHostApi() {
    g.ModelFlutterApi.setUp(this);
  }
  final g.ModelHostApi _api;
  final _progress = StreamController<(String, DownloadStatus)>.broadcast();

  @override
  Stream<(String, DownloadStatus)> get progress => _progress.stream;

  @override
  Future<DeviceCapability> capability() async {
    final d = await _api.getDeviceCapability();
    return DeviceCapability(
      totalRamMb: d.totalRamMb,
      availableRamMb: d.availableRamMb,
      lowRamDevice: d.lowRamDevice,
      soc: '${d.socManufacturer} ${d.socModel}'.trim(),
      abis: d.abis,
      freeStorageMb: d.freeStorageMb,
    );
  }

  @override
  Future<Set<String>> installedFiles() async => {for (final m in await _api.listInstalled()) m.fileName};

  @override
  Future<void> download(ModelSpec s) => _api.startDownload(
        g.ModelSpecMessage(id: s.id, url: s.url, fileName: s.fileName, sha256: s.sha256, sizeBytes: s.sizeBytes),
      );

  @override
  Future<void> cancel(String id) => _api.cancelDownload(id);

  @override
  Future<void> delete(ModelSpec spec) => _api.deleteModel(spec.fileName);

  @override
  void onDownloadProgress(g.DownloadProgressMessage p) {
    final phase = switch (p.state) {
      g.DownloadState.running => DownloadPhase.running,
      g.DownloadState.verifying => DownloadPhase.verifying,
      g.DownloadState.completed => DownloadPhase.completed,
      g.DownloadState.failed => DownloadPhase.failed,
      g.DownloadState.cancelled => DownloadPhase.cancelled,
    };
    _progress.add((p.id, DownloadStatus(phase, received: p.receivedBytes, total: p.totalBytes, error: p.error)));
  }
}

// ============================================================================ Yerel LLM (LiteRT-LM)

/// Gerçek yerel LLM: LiteRT-LM motoru, indirilen .litertlm modeliyle cihazda çalışır.
class AndroidLocalLlm implements LocalLlm {
  AndroidLocalLlm({g.LocalLlmHostApi? api}) : _api = api ?? g.LocalLlmHostApi();
  final g.LocalLlmHostApi _api;

  /// Hiç model kurulu değilse uygulama katmanı bunu true yapar.
  bool noModelInstalled = false;

  static LocalLlmInfo _map(g.LlmStatusMessage s) => LocalLlmInfo(
        switch (s.state) {
          g.LlmEngineState.notLoaded => LocalLlmState.notLoaded,
          g.LlmEngineState.loading => LocalLlmState.loading,
          g.LlmEngineState.ready => LocalLlmState.ready,
          g.LlmEngineState.failed => LocalLlmState.failed,
        },
        modelName: s.fileName,
        backend: s.backend,
        detail: s.error ?? (s.loadMillis == null ? null : '${(s.loadMillis! / 1000).toStringAsFixed(1)} sn'),
      );

  @override
  Future<LocalLlmInfo> info() async {
    final s = _map(await _api.status());
    if (s.state == LocalLlmState.notLoaded && noModelInstalled) return const LocalLlmInfo(LocalLlmState.noModel);
    return s;
  }

  Future<LocalLlmInfo> load(String fileName, {required bool preferGpu}) async =>
      _map(await _api.load(fileName, preferGpu, 4096));

  Future<void> unload() => _api.unload();

  Future<void> cancel() => _api.cancel();

  @override
  Future<Result<String>> chat({
    required String system,
    required List<LlmMessage> history,
    required String user,
    int maxOutputTokens = 384,
  }) async {
    try {
      final r = await _api.generate(
        system,
        [for (final m in history) g.ChatTurnMessage(fromUser: m.role == LlmRole.user, text: m.text)],
        user,
        maxOutputTokens,
      );
      return Result.ok(r.text);
    } on Object catch (e) {
      return Result.err(Failure('local-model', 'Yerel model hatası', cause: e));
    }
  }
}

// ============================================================================ Telefon portları

class AndroidDevicePorts implements DevicePorts {
  AndroidDevicePorts({
    g.RuntimePermissionHostApi? perms,
    g.PhoneActionsHostApi? phone,
    g.AppsHostApi? apps,
    g.NotificationsHostApi? notifications,
    g.ReminderHostApi? reminders,
  })  : _perms = perms ?? g.RuntimePermissionHostApi(),
        _phone = phone ?? g.PhoneActionsHostApi(),
        _apps = apps ?? g.AppsHostApi(),
        _notif = notifications ?? g.NotificationsHostApi(),
        _rem = reminders ?? g.ReminderHostApi();

  final g.RuntimePermissionHostApi _perms;
  final g.PhoneActionsHostApi _phone;
  final g.AppsHostApi _apps;
  final g.NotificationsHostApi _notif;
  final g.ReminderHostApi _rem;

  static g.RuntimePermission _p(DevicePermission p) => switch (p) {
        DevicePermission.contacts => g.RuntimePermission.contacts,
        DevicePermission.calendar => g.RuntimePermission.calendar,
        DevicePermission.notifications => g.RuntimePermission.notifications,
      };

  Future<bool> hasPermission(DevicePermission p) async => await _perms.check(_p(p)) == g.MicPermissionState.granted;

  @override
  Future<bool> ensurePermission(DevicePermission p) async {
    if (await hasPermission(p)) return true;
    return await _perms.request(_p(p)) == g.MicPermissionState.granted;
  }

  @override
  Future<List<Contact>> searchContacts(String query) async =>
      [for (final c in await _phone.searchContacts(query, 5)) Contact(c.name, c.phone)];

  @override
  Future<bool> openDialer(String phone) => _phone.openDialer(phone);

  @override
  Future<bool> openWhatsApp(String phone, String text) => _phone.openWhatsApp(phone, text);

  @override
  Future<bool> setAlarm(int hour, int minute, String label) => _phone.setAlarm(hour, minute, label);

  @override
  Future<bool> insertCalendarEvent(String title, DateTime start, DateTime end) =>
      _phone.insertCalendarEvent(title, start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);

  @override
  Future<List<CalendarItem>> readCalendar(DateTime from, DateTime to) async => [
        for (final e in await _phone.readCalendar(from.millisecondsSinceEpoch, to.millisecondsSinceEpoch))
          CalendarItem(
            title: e.title,
            start: DateTime.fromMillisecondsSinceEpoch(e.beginMillis),
            end: DateTime.fromMillisecondsSinceEpoch(e.endMillis),
            allDay: e.allDay,
            location: e.location,
          ),
      ];

  @override
  Future<List<AppInfo>> findApps(String query) async => [for (final a in await _apps.findApps(query, 5)) AppInfo(a.label, a.packageName)];

  @override
  Future<bool> launchApp(String packageName) => _apps.launchApp(packageName);

  @override
  Future<bool> openSettings(SettingsTarget target) => _apps.openSettings(switch (target) {
        SettingsTarget.wifi => g.SettingsPage.wifi,
        SettingsTarget.bluetooth => g.SettingsPage.bluetooth,
        SettingsTarget.display => g.SettingsPage.display,
        SettingsTarget.sound => g.SettingsPage.sound,
        SettingsTarget.battery => g.SettingsPage.battery,
        SettingsTarget.location => g.SettingsPage.location,
        SettingsTarget.apps => g.SettingsPage.apps,
        SettingsTarget.notifications => g.SettingsPage.notifications,
        SettingsTarget.main => g.SettingsPage.main,
      });

  Future<bool> openAppDetails() => _apps.openSettings(g.SettingsPage.appDetails);

  @override
  Future<bool> notificationAccess() => _notif.isAccessGranted();

  @override
  Future<void> openNotificationAccessSettings() => _notif.openAccessSettings();

  @override
  Future<List<NotificationItem>> recentNotifications(int limit) async => [
        for (final n in await _notif.recent(limit))
          NotificationItem(
            key: n.key,
            app: n.appName,
            title: n.title,
            text: n.text,
            posted: DateTime.fromMillisecondsSinceEpoch(n.postedMillis),
            canReply: n.canReply,
          ),
      ];

  @override
  Future<bool> replyToNotification(String key, String text) => _notif.reply(key, text);

  @override
  Future<void> scheduleReminder(int id, String text, DateTime at) => _rem.schedule(id, text, at.millisecondsSinceEpoch);

  @override
  Future<void> cancelReminder(int id) => _rem.cancel(id);

  Future<({bool exact, bool notifications})> reminderCapability() async {
    final c = await _rem.capability();
    return (exact: c.exactAlarms, notifications: c.notifications);
  }

  Future<void> openExactAlarmSettings() => _rem.openExactAlarmSettings();
}

// ============================================================================ Dosya / fotoğraf

class DocumentContent {
  const DocumentContent({required this.kind, required this.text, required this.labels, this.name});
  final String kind;
  final String? name;
  final String text;
  final List<String> labels;
}

abstract interface class DocumentReader {
  Future<DocumentContent?> pickFile();
  Future<DocumentContent?> captureImage({required bool fromCamera});
}

class AndroidDocumentReader implements DocumentReader {
  AndroidDocumentReader({g.FileHostApi? api}) : _api = api ?? g.FileHostApi();
  final g.FileHostApi _api;

  static DocumentContent? _map(g.DocumentResultMessage? m) =>
      m == null ? null : DocumentContent(kind: m.kind, name: m.name, text: m.text, labels: m.labels);

  @override
  Future<DocumentContent?> pickFile() async => _map(await _api.pickAndRead());

  @override
  Future<DocumentContent?> captureImage({required bool fromCamera}) async => _map(await _api.captureImage(fromCamera));
}

/// Debug yapısında adb ile aktarılan gateway ayarı.
Future<({String? url, String? token})?> consumeDevConfig() async {
  try {
    final m = await g.DevConfigHostApi().consumeDevConfig();
    return m == null ? null : (url: m.gatewayUrl, token: m.gatewayToken);
  } on Object {
    return null;
  }
}
