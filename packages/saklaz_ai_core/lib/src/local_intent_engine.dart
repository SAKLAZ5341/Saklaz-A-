import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';

import 'device_ports.dart';
import 'turkish_time.dart';

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

/// "Hatırla ki ..." — açık kayıt isteği (onaylı).
class RememberIntent extends LocalIntent {
  const RememberIntent(this.content);
  final String content;
}

/// "Benim mesleğim ne?" — yerel hafıza araması.
class MemoryQueryIntent extends LocalIntent {
  const MemoryQueryIntent(this.query, {this.listAll = false, this.category});
  final String query;
  final bool listAll;
  final FactCategory? category;
}

class NoteIntent extends LocalIntent {
  const NoteIntent(this.text);
  final String text;
}

class ListNotesIntent extends LocalIntent {
  const ListNotesIntent();
}

class ReminderIntent extends LocalIntent {
  const ReminderIntent(this.task, this.at);
  final String task;

  /// null: zaman anlaşılamadı.
  final DateTime? at;
}

class ListRemindersIntent extends LocalIntent {
  const ListRemindersIntent();
}

class AlarmIntent extends LocalIntent {
  const AlarmIntent(this.at);
  final DateTime? at;
}

class CalendarAddIntent extends LocalIntent {
  const CalendarAddIntent(this.title, this.at);
  final String title;
  final DateTime? at;
}

class CalendarQueryIntent extends LocalIntent {
  const CalendarQueryIntent(this.day);
  final DateTime day;
}

class CallIntent extends LocalIntent {
  const CallIntent(this.target);
  final String target;
}

class WhatsAppIntent extends LocalIntent {
  const WhatsAppIntent(this.target, this.message);
  final String target;
  final String message;
}

class OpenAppIntent extends LocalIntent {
  const OpenAppIntent(this.name);
  final String name;
}

class OpenSettingsIntent extends LocalIntent {
  const OpenSettingsIntent(this.target);
  final SettingsTarget target;
}

class NotificationsIntent extends LocalIntent {
  const NotificationsIntent();
}

/// Kurallarla karşılanamayan genel istek.
class GeneralIntent extends LocalIntent {
  const GeneralIntent(this.text, {required this.complex, required this.needsInternet});
  final String text;
  final bool complex;
  final bool needsInternet;
}

class LocalIntentEngine {
  const LocalIntentEngine({DateTime Function()? clock}) : _clock = clock; // ignore: prefer_initializing_formals
  final DateTime Function()? _clock;

  DateTime get _now => (_clock ?? DateTime.now)();

  static final _rememberPrefix = RegExp(
    r'^\s*(?:(?:bunu|şunu|sunu)\s+)?(?:hatırla|hatirla|aklında tut|aklinda tut|kaydet|unutma)(?!t)\s*(?:ki|:|,)?\s*',
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
    final now = _now;

    // --- Hatırlatıcı ("hatırlat") — "hatırla"dan ÖNCE kontrol edilmeli.
    if (RegExp(r'\bhatirlat').hasMatch(t) && !t.contains('hatirlatmalarim') && !t.contains('hatirlaticilarim')) {
      final p = TurkishTime.parse(raw, now);
      return ReminderIntent(_task(raw, p, const {'hatirlat', 'hatirlatir', 'hatirlatirmisin', 'misin', 'bana', 'lutfen', 'beni'}), p?.at);
    }
    if (_any(t, ['hatirlatmalarim', 'hatirlaticilarim', 'hatirlatmalar neler', 'hatirlaticilar'])) return const ListRemindersIntent();

    // --- Alarm
    if (_any(t, ['alarm kur', 'alarm ayarla', 'alarmi kur', 'beni uyandir', 'alarm koy']) || (words.contains('alarm') && words.length <= 6)) {
      return AlarmIntent(TurkishTime.parse(raw, now)?.at);
    }

    // --- Not
    final noteM = RegExp(r'^\s*(?:bir\s+)?not\s+(?:al|et|ekle|yaz)\s*[:,]?\s*(.*)$', caseSensitive: false).firstMatch(raw);
    if (noteM != null) return NoteIntent(noteM.group(1)!.trim());
    final noteSuffix = RegExp(r'^(.+?)\s*[,]?\s*(?:diye\s+)?not\s+(?:al|et|ekle)\s*[.!]*$', caseSensitive: false).firstMatch(raw);
    if (noteSuffix != null) return NoteIntent(noteSuffix.group(1)!.trim());
    if (_any(t, ['notlarim', 'notlarimi', 'notlari oku', 'notlari goster'])) return const ListNotesIntent();

    // --- Hafızaya kaydetme (açık istek)
    final pre = _rememberPrefix.firstMatch(raw);
    if (pre != null && raw.length - pre.end >= 3) return RememberIntent(_clean(raw.substring(pre.end)));
    final suf = _rememberSuffix.firstMatch(raw);
    if (suf != null && suf.start >= 3 && !t.contains('hatirliyor musun')) return RememberIntent(_clean(raw.substring(0, suf.start)));

    // --- Takvim
    if (t.contains('takvim') && _any(t, ['ekle', 'kaydet', 'olustur', 'koy'])) {
      final p = TurkishTime.parse(raw, now);
      return CalendarAddIntent(_task(raw, p, const {'takvime', 'takvimime', 'takvim', 'ekle', 'ekler', 'misin', 'kaydet', 'olustur', 'koy', 'bir', 'etkinlik', 'lutfen'}), p?.at);
    }
    if (_any(t, ['takvimimde', 'takvimde ne', 'programim', 'ajandam', 'ajandamda', 'bugun neler var', 'yarin neler var', 'toplantilarim'])) {
      final p = TurkishTime.parse(raw, now);
      final day = p?.at ?? now;
      return CalendarQueryIntent(DateTime(day.year, day.month, day.day));
    }

    // --- Bildirimler
    if (_any(t, ['bildirimlerimi', 'bildirimleri oku', 'son bildirim', 'bildirimlerim', 'kimden mesaj', 'yeni mesaj var mi', 'okunmamis mesaj'])) {
      return const NotificationsIntent();
    }

    // --- WhatsApp
    if (t.contains('whatsapp')) {
      if (RegExp(r'\b(ac|acar misin|baslat)$').hasMatch(t) && !_any(t, ['yaz', 'gonder', 'mesaj at'])) return const OpenAppIntent('WhatsApp');
      final colon = raw.indexOf(':');
      String target = '';
      String message = '';
      final targetM = RegExp(r"^(.+?)['’]?(?:ye|ya|e|a)\s+(?:whatsapp|wp)", caseSensitive: false).firstMatch(raw);
      if (targetM != null) target = targetM.group(1)!.trim();
      if (colon > 0) {
        message = raw.substring(colon + 1).trim();
      } else {
        final m = RegExp(r"whatsapp\S*\s+(?:(?:dan|tan|den|ten)\s+)?(?:mesaj\s+)?(.+?)\s+(?:diye\s+)?(?:yaz|gönder|gonder|ilet|söyle|soyle|de|mesaj at)\s*[.!]*$", caseSensitive: false)
            .firstMatch(raw);
        if (m != null) message = _toStatement(m.group(1)!.trim());
      }
      if (target.isEmpty) {
        final m = RegExp(r"whatsapp\S*\s+(?:dan|tan|den|ten)?\s*(\S+?)['’]?(?:ye|ya|e|a)\s", caseSensitive: false).firstMatch(raw);
        if (m != null) target = m.group(1)!;
      }
      return WhatsAppIntent(target, message);
    }

    // --- Arama
    final callM = RegExp(r"^(.+?)['’]?(?:yi|yı|yu|yü|i|ı|u|ü)?\s+(?:ara|arar\s*m[ıi]s[ıi]n|aramak istiyorum)\s*[.!?]*$", caseSensitive: false).firstMatch(raw);
    if (callM != null && words.length <= 5 && !_any(t, ['internette', 'google', 'arastir'])) {
      return CallIntent(callM.group(1)!.replaceAll(RegExp(r'^(?:lütfen|lutfen)\s+', caseSensitive: false), '').trim());
    }

    // --- Ayarlar
    if (_any(t, ['ayar', 'wifi', 'wi fi', 'bluetooth', 'parlaklik', 'konum ac', 'pil tasarruf']) && RegExp(r'\b(ac|acar misin|git|goster)$').hasMatch(t)) {
      return OpenSettingsIntent(switch (t) {
        _ when t.contains('wifi') || t.contains('wi fi') || t.contains('kablosuz') => SettingsTarget.wifi,
        _ when t.contains('bluetooth') => SettingsTarget.bluetooth,
        _ when t.contains('ekran') || t.contains('parlaklik') => SettingsTarget.display,
        _ when t.contains('ses') => SettingsTarget.sound,
        _ when t.contains('pil') || t.contains('batarya') => SettingsTarget.battery,
        _ when t.contains('konum') || t.contains('gps') => SettingsTarget.location,
        _ when t.contains('bildirim') => SettingsTarget.notifications,
        _ when t.contains('uygulama') => SettingsTarget.apps,
        _ => SettingsTarget.main,
      });
    }

    // --- Uygulama açma
    final openM = RegExp(r"^(.+?)(?:['’]?(?:yi|yı|yu|yü|i|ı|u|ü))?\s+(?:uygulamasını\s+|uygulamasini\s+)?(?:aç|ac|açar\s*m[ıi]s[ıi]n|başlat|baslat)\s*[.!]*$", caseSensitive: false)
        .firstMatch(raw);
    if (openM != null && words.length <= 5) return OpenAppIntent(openM.group(1)!.trim());

    // --- Hafıza sorgusu
    if (_any(t, ['hakkimda ne biliyorsun', 'neler hatirliyorsun', 'hafizanda ne var', 'neleri biliyorsun', 'beni taniyor musun', 'hakkimda neler'])) {
      return MemoryQueryIntent(raw, listAll: true);
    }
    final cat = _queryCategory(t);
    if (cat != null && FactExtractorQuestion.isSelfQuestion(t)) return MemoryQueryIntent(raw, category: cat);
    if (_any(t, ['hatirliyor musun', 'neydi', 'kacti', 'ne zamandi', 'neredeydi'])) return MemoryQueryIntent(raw);

    // --- Basit yerel komutlar
    if (words.length <= 6) {
      if (_any(t, ['merhaba', 'selam', 'gunaydin', 'iyi aksamlar', 'iyi geceler', 'hey saklaz', 'naber'])) return const GreetingIntent();
      if (_any(t, ['saat kac', 'saati soyle', 'saat ne'])) return const TimeIntent();
      if (_any(t, ['bugun gunlerden ne', 'tarih ne', 'bugunun tarihi', 'bugun ayin kaci', 'hangi gundeyiz'])) return const DateIntent();
      if (_any(t, ['kimsin', 'adin ne', 'sen nesin'])) return const IdentityIntent();
      if (_any(t, ['tesekkur', 'sag ol', 'sagol', 'eyvallah'])) return const ThanksIntent();
      if (_any(t, ['neler yapabilirsin', 'ne yapabilirsin', 'yardim'])) return const HelpIntent();
    }

    return GeneralIntent(raw, needsInternet: _any(t, _internetKeywords), complex: words.length > 14 || _any(t, _complexKeywords));
  }

  static FactCategory? _queryCategory(String t) {
    if (_any(t, ['meslegim', 'isim ne', 'ne is yapiyorum', 'ne is yaparim', 'gorevim'])) return FactCategory.profession;
    if (_any(t, ['proje'])) return FactCategory.project;
    if (_any(t, ['ilgi alan', 'hobi', 'nelerle ilgileniyorum', 'neyi seviyorum', 'neleri seviyorum'])) return FactCategory.interest;
    if (_any(t, ['hedef', 'amacim', 'planlarim'])) return FactCategory.goal;
    if (_any(t, ['nerede yasiyorum', 'nerede oturuyorum'])) return FactCategory.location;
    if (_any(t, ['adim ne', 'ismim ne'])) return FactCategory.name;
    if (_any(t, ['nerede calisiyorum', 'hangi sirket', 'sirketim'])) return FactCategory.company;
    if (_any(t, ['sektor'])) return FactCategory.sector;
    if (_any(t, ['tercih', 'en sevdigim'])) return FactCategory.preference;
    if (_any(t, ['aliskanlik', 'rutinim'])) return FactCategory.habit;
    if (_any(t, ['kararlarim', 'ne karar verdim', 'karar vermistim'])) return FactCategory.decision;
    return null;
  }

  /// Zaman ifadesi ve komut kelimeleri çıkarılmış görev metni.
  static String _task(String raw, ParsedTime? p, Set<String> stop) {
    final tokens = TurkishTime.tokens(raw);
    final kept = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      if (p != null && p.consumedTokens.contains(i)) continue;
      final n = TurkishTime.norm(tokens[i]);
      if (stop.contains(n) || n == 'saat' || n.isEmpty) continue;
      if (n.startsWith('hatirlat')) continue;
      kept.add(tokens[i]);
    }
    return kept.join(' ').replaceAll(RegExp(r'^[,:;\s]+|[.!?,\s]+$'), '').trim();
  }

  /// "geç kalacağımı" -> "geç kalacağım" (WhatsApp taslağı için).
  static String _toStatement(String s) => s
      .replaceAllMapped(RegExp(r'(acağ|eceğ)(ımı|imi)$'), (m) => '${m[1]}${m[2]!.substring(0, 2)}')
      .replaceAllMapped(RegExp(r'(dığ|diğ|tığ|tiğ|duğ|düğ|tuğ|tüğ)(ımı|imi|umu|ümü)$'), (m) => '${m[1]!.substring(0, 1)}${m[1]!.substring(1, 2) == 'ı' ? 'ım' : m[1]!.substring(1, 2) == 'i' ? 'im' : m[1]!.substring(1, 2) == 'u' ? 'um' : 'üm'}');

  static String _clean(String s) => s.trim().replaceAll(RegExp(r'^[,:;\s]+|[.!\s]+$'), '');

  static bool _any(String t, List<String> patterns) => patterns.any(t.contains);

  static const _internetKeywords = [
    'hava durumu', 'hava nasil', 'yagmur yagacak', 'haber', 'son dakika', 'doviz', 'dolar', 'euro', 'kur ', 'borsa',
    'bitcoin', 'mac skoru', 'mac sonucu', 'trafik', 'internette ara', 'internetten', 'guncel', 'bugun ne oldu', 'secim sonuc',
  ];

  static const _complexKeywords = [
    'analiz', 'karsilastir', 'acikla', 'neden', 'nasil yapilir', 'ozetle', 'yaz ', 'e posta yaz', 'plan', 'strateji',
    'oner', 'degerlendir', 'kod', 'hesapla', 'cevir', 'tercume',
  ];
}

/// Kullanıcının kendisi hakkında soru sorup sormadığını anlar.
abstract final class FactExtractorQuestion {
  static bool isSelfQuestion(String normalized) {
    final t = normalized;
    final self = RegExp(r'\b(benim|ben|bana|beni)\b').hasMatch(t) || RegExp(r'(im|im|um|um|yorum)\b').hasMatch(t);
    final question = RegExp(r'\b(ne|neler|nedir|neydi|hangi|hangileri|nerede|kim|mi|mu)\b').hasMatch(t);
    return self && question;
  }
}
