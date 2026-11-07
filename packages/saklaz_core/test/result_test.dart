import 'package:saklaz_core/saklaz_core.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('ok değeri taşır', () {
      const r = Result<int>.ok(42);
      expect(r.isOk, isTrue);
      expect(r.valueOrNull, 42);
      expect(r.failureOrNull, isNull);
      expect(r.fold((v) => v + 1, (_) => 0), 43);
    });

    test('err hatayı taşır', () {
      const r = Result<int>.err(Failure('x', 'Hata'));
      expect(r.isOk, isFalse);
      expect(r.valueOrNull, isNull);
      expect(r.failureOrNull?.code, 'x');
      expect(r.fold((v) => 'ok', (f) => f.message), 'Hata');
    });
  });

  group('MemoryLogger', () {
    test('kapasiteyi aşınca en eski kaydı atar', () {
      final logs = <LogRecord>[];
      final logger = MemoryLogger(capacity: 2, sink: logs.add);
      logger.i('t', 'bir');
      logger.i('t', 'iki');
      logger.w('t', 'üç');
      expect(logger.records.map((r) => r.message), ['iki', 'üç']);
      expect(logs, hasLength(3));
      expect(logger.records.last.level, LogLevel.warn);
    });
  });
}
