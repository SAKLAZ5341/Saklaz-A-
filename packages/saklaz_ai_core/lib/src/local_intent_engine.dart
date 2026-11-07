import 'package:saklaz_core/saklaz_core.dart';

/// Kullanıcı ifadesinin yerel olarak sınıflandırılması. Ağ kullanmaz.
sealed class LocalIntent {
  const LocalIntent();
}

class GreetingIntent extends LocalIntent {
  const GreetingIntent();
}

class TimeIntent extends LocalIntent {
  const TimeIntent();
}

class DateIntent extends LocalIntent {
  const DateIntent();
}

class IdentityIntent extends LocalIntent {
  const IdentityIntent();
}

class ThanksIntent extends LocalIntent {
  const ThanksIntent();
}

class HelpIntent extends LocalIntent {
  const HelpIntent();
}

/// "Hatırla ki ..." — kaydetmeden önce kullanıcı onayı gerekir.
class RememberIntent extends LocalIntent {
  const RememberIntent(this.content);
  final String content;
}

/// "Benim X neydi?" — yerel hafıza araması.
class MemoryQueryIntent extends LocalIntent {
  const MemoryQueryIntent(this.query, {this.listAll = false});
  final String query;
  final bool listAll;
}

/// Kurallarla karşılanamayan genel istek.
class GeneralIntent extends LocalIntent {
  const GeneralIntent(this.text, {required this.complex, required this.needsInternet});
  final String text;

  /// Uzun / analiz gerektiren istek.
  final bool complex;

  /// Güncel bilgi gerektiren istek (hava, haber, kur...).
  final bool needsInternet;
}

class LocalIntentEngine {
  const LocalIntentEngine();

  static final _rememberPrefix = RegExp(
    r'^\s*(?:(?:bunu|şunu|sunu)\s+)?(?:hatırla|hatirla|aklında tut|aklinda tut|kaydet|not et|unutma)\s*(?:ki|:|,)?\s*',
    caseSensitive: false,
  );
  static final _rememberSuffix = RegExp(
    r'\s*[,.]?\s*(?:bunu\s+)?(?:hatırla|hatirla|aklında tut|aklinda tut|unutma)\s*[.!]*\s*$',
    caseSensitive: false,
  );

  LocalIntent classify(String text) {
    final raw = text.trim();
    final t = normalizeTr(raw);
    final words = t.isEmpty ? const <String>[] : t.split(' ');

    // --- Hafızaya kaydetme ---
    final pre = _rememberPrefix.firstMatch(raw);
    if (pre != null && raw.length - pre.end >= 3) {
      return RememberIntent(_clean(raw.substring(pre.end)));
    }
    final suf = _rememberSuffix.firstMatch(raw);
    if (suf != null && suf.start >= 3 && !t.contains('hatirliyor musun')) {
      return RememberIntent(_clean(raw.substring(0, suf.start)));
    }

    // --- Hafıza sorgusu ---
    if (_any(t, ['hakkimda ne biliyorsun', 'neler hatirliyorsun', 'hafizanda ne var', 'neleri biliyorsun'])) {
      return MemoryQueryIntent(raw, listAll: true);
    }
    if (_any(t, ['hatirliyor musun', 'neydi', 'kacti', 'ne zamandi', 'nerdeydi', 'neredeydi']) ||
        (words.contains('benim') && _any(t, [' ne', 'nedir', 'kac']))) {
      return MemoryQueryIntent(raw);
    }

    // --- Basit yerel komutlar ---
    if (words.length <= 6) {
      if (_any(t, ['merhaba', 'selam', 'gunaydin', 'iyi aksamlar', 'iyi geceler', 'hey saklaz', 'naber'])) {
        return const GreetingIntent();
      }
      if (_any(t, ['saat kac', 'saati soyle', 'saat ne'])) return const TimeIntent();
      if (_any(t, ['bugun gunlerden ne', 'tarih ne', 'bugunun tarihi', 'bugun ayin kaci', 'hangi gundeyiz'])) {
        return const DateIntent();
      }
      if (_any(t, ['kimsin', 'adin ne', 'sen nesin'])) return const IdentityIntent();
      if (_any(t, ['tesekkur', 'sag ol', 'sagol', 'eyvallah'])) return const ThanksIntent();
      if (_any(t, ['neler yapabilirsin', 'ne yapabilirsin', 'yardim'])) return const HelpIntent();
    }

    return GeneralIntent(
      raw,
      needsInternet: _any(t, _internetKeywords),
      complex: words.length > 14 || _any(t, _complexKeywords),
    );
  }

  static String _clean(String s) => s.trim().replaceAll(RegExp(r'^[,:;\s]+|[.!\s]+$'), '');

  static bool _any(String t, List<String> patterns) => patterns.any(t.contains);

  static const _internetKeywords = [
    'hava durumu', 'hava nasil', 'yagmur yagacak', 'haber', 'son dakika', 'doviz', 'dolar', 'euro',
    'kur ', 'borsa', 'bitcoin', 'mac skoru', 'mac sonucu', 'trafik', 'internette ara', 'internetten',
    'guncel', 'bugun ne oldu', 'secim sonuc',
  ];

  static const _complexKeywords = [
    'analiz', 'karsilastir', 'acikla', 'neden', 'nasil yapilir', 'ozetle', 'yaz ', 'e posta yaz',
    'plan', 'strateji', 'oner', 'degerlendir', 'kod', 'hesapla', 'cevir', 'tercume',
  ];
}
