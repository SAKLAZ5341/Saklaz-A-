import 'dart:collection';

enum LogLevel { debug, info, warn, error, audit }

class LogRecord {
  LogRecord({
    required this.level,
    required this.tag,
    required this.message,
    DateTime? time,
    this.error,
  }) : time = time ?? DateTime.now();

  final LogLevel level;
  final String tag;
  final String message;
  final DateTime time;
  final Object? error;

  @override
  String toString() {
    final t = time.toIso8601String();
    final e = error == null ? '' : ' | $error';
    return '$t [${level.name.toUpperCase()}] $tag: $message$e';
  }
}

/// Uygulama genelinde loglama arayüzü.
///
/// KURAL: Kişisel içerik (konuşma metni, e-posta gövdesi, kişi adları)
/// teknik loglara YAZILMAZ. Yalnızca olay türü, süre, hata kodu loglanır.
abstract interface class AppLogger {
  void log(LogLevel level, String tag, String message, {Object? error});
}

extension AppLoggerX on AppLogger {
  void d(String tag, String msg) => log(LogLevel.debug, tag, msg);
  void i(String tag, String msg) => log(LogLevel.info, tag, msg);
  void w(String tag, String msg, {Object? error}) =>
      log(LogLevel.warn, tag, msg, error: error);
  void e(String tag, String msg, {Object? error}) =>
      log(LogLevel.error, tag, msg, error: error);
}

/// Son [capacity] kaydı bellekte tutan logger. İsteğe bağlı olarak her kaydı
/// [sink]'e de iletir (ör. debugPrint). Diske yazmaz.
class MemoryLogger implements AppLogger {
  MemoryLogger({this.capacity = 500, this.sink});

  final int capacity;
  final void Function(LogRecord record)? sink;
  final _records = ListQueue<LogRecord>();

  List<LogRecord> get records => List.unmodifiable(_records);

  @override
  void log(LogLevel level, String tag, String message, {Object? error}) {
    final r = LogRecord(level: level, tag: tag, message: message, error: error);
    _records.addLast(r);
    while (_records.length > capacity) {
      _records.removeFirst();
    }
    sink?.call(r);
  }
}
