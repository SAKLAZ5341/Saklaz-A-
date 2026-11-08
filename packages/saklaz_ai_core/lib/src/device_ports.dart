/// Agent'ın telefonla etkileşim portları. Android uygulaması köprü paketindedir.
library;

class Contact {
  const Contact(this.name, this.phone);
  final String name;
  final String phone;
}

class CalendarItem {
  const CalendarItem({required this.title, required this.start, required this.end, required this.allDay, this.location});
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
}

class AppInfo {
  const AppInfo(this.label, this.packageName);
  final String label;
  final String packageName;
}

class NotificationItem {
  const NotificationItem({
    required this.key,
    required this.app,
    required this.title,
    required this.text,
    required this.posted,
    required this.canReply,
  });
  final String key;
  final String app;
  final String title;
  final String text;
  final DateTime posted;
  final bool canReply;
}

enum DevicePermission { contacts, calendar, notifications }

enum SettingsTarget { wifi, bluetooth, display, sound, battery, location, apps, notifications, main }

class PermissionDenied implements Exception {
  const PermissionDenied(this.permission);
  final DevicePermission permission;
}

abstract interface class DevicePorts {
  /// İzin yoksa ister. Verildiyse true.
  Future<bool> ensurePermission(DevicePermission p);

  Future<List<Contact>> searchContacts(String query);
  Future<bool> openDialer(String phone);
  Future<bool> openWhatsApp(String phone, String text);
  Future<bool> setAlarm(int hour, int minute, String label);
  Future<bool> insertCalendarEvent(String title, DateTime start, DateTime end);
  Future<List<CalendarItem>> readCalendar(DateTime from, DateTime to);
  Future<List<AppInfo>> findApps(String query);
  Future<bool> launchApp(String packageName);
  Future<bool> openSettings(SettingsTarget target);
  Future<bool> notificationAccess();
  Future<void> openNotificationAccessSettings();
  Future<List<NotificationItem>> recentNotifications(int limit);
  Future<bool> replyToNotification(String key, String text);

  /// Hatırlatıcıyı sistem alarmına kurar (bildirim izni gerekebilir).
  Future<void> scheduleReminder(int id, String text, DateTime at);
  Future<void> cancelReminder(int id);
}

/// Telefon özelliği olmayan ortamlar (testler) için.
class NoDevice implements DevicePorts {
  const NoDevice();
  @override
  Future<bool> ensurePermission(DevicePermission p) async => false;
  @override
  Future<List<Contact>> searchContacts(String query) async => const [];
  @override
  Future<bool> openDialer(String phone) async => false;
  @override
  Future<bool> openWhatsApp(String phone, String text) async => false;
  @override
  Future<bool> setAlarm(int hour, int minute, String label) async => false;
  @override
  Future<bool> insertCalendarEvent(String title, DateTime start, DateTime end) async => false;
  @override
  Future<List<CalendarItem>> readCalendar(DateTime from, DateTime to) async => const [];
  @override
  Future<List<AppInfo>> findApps(String query) async => const [];
  @override
  Future<bool> launchApp(String packageName) async => false;
  @override
  Future<bool> openSettings(SettingsTarget target) async => false;
  @override
  Future<bool> notificationAccess() async => false;
  @override
  Future<void> openNotificationAccessSettings() async {}
  @override
  Future<List<NotificationItem>> recentNotifications(int limit) async => const [];
  @override
  Future<bool> replyToNotification(String key, String text) async => false;
  @override
  Future<void> scheduleReminder(int id, String text, DateTime at) async {}
  @override
  Future<void> cancelReminder(int id) async {}
}
