/// Türkçe doğal dil zaman ifadelerini çözer (tamamen yerel, kural tabanlı).
///
/// Desteklenenler: "10 dakika sonra", "yarım saat sonra", "2 saat sonra",
/// "bugün/yarın/öbür gün", gün adları ("cuma"), "sabah/öğlen/öğleden sonra/akşam/gece",
/// "saat 9'da", "15:30'da", "9 buçukta", "7'ye".
class ParsedTime {
  const ParsedTime(this.at, this.consumedTokens, {required this.hasExplicitTime});
  final DateTime at;

  /// Zaman ifadesine ait (görev metninden çıkarılacak) token indeksleri.
  final Set<int> consumedTokens;
  final bool hasExplicitTime;
}

abstract final class TurkishTime {
  static const _numbers = {
    'bir': 1, 'iki': 2, 'uc': 3, 'dort': 4, 'bes': 5, 'alti': 6, 'yedi': 7, 'sekiz': 8, 'dokuz': 9,
    'on': 10, 'onbes': 15, 'yirmi': 20, 'otuz': 30, 'kirk': 40, 'elli': 50, 'altmis': 60,
  };
  static const _days = {
    'pazartesi': DateTime.monday, 'sali': DateTime.tuesday, 'carsamba': DateTime.wednesday,
    'persembe': DateTime.thursday, 'cuma': DateTime.friday, 'cumartesi': DateTime.saturday, 'pazar': DateTime.sunday,
  };

  /// Eşleştirme için: küçük harf, Türkçe harfler ASCII, kesme işaretleri silinir, `:` ve `.` korunur.
  static String norm(String token) {
    const map = {'ı': 'i', 'İ': 'i', 'ş': 's', 'Ş': 's', 'ğ': 'g', 'Ğ': 'g', 'ü': 'u', 'Ü': 'u', 'ö': 'o', 'Ö': 'o', 'ç': 'c', 'Ç': 'c', 'I': 'i'};
    final b = StringBuffer();
    for (final r in token.runes) {
      final ch = String.fromCharCode(r);
      b.write(map[ch] ?? ch.toLowerCase());
    }
    return b.toString().replaceAll(RegExp(r"['’`]"), '').replaceAll(RegExp(r'[^a-z0-9:.]'), '');
  }

  static List<String> tokens(String text) => text.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

  static int? _num(String t) => int.tryParse(t) ?? _numbers[t];

  static ParsedTime? parse(String text, DateTime now) {
    final raw = tokens(text);
    final t = raw.map(norm).toList();
    final used = <int>{};

    // --- Göreli: "<n> dakika/saat sonra", "yarım saat sonra"
    for (var i = 0; i + 2 < t.length || (i + 1 < t.length); i++) {
      if (i + 2 < t.length && t[i + 2] == 'sonra') {
        final unit = t[i + 1];
        final n = t[i] == 'yarim' ? null : _num(t[i]);
        if (t[i] == 'yarim' && unit == 'saat') return ParsedTime(now.add(const Duration(minutes: 30)), {i, i + 1, i + 2}, hasExplicitTime: true);
        if (n != null && (unit.startsWith('dakika') || unit == 'dk')) {
          return ParsedTime(now.add(Duration(minutes: n)), {i, i + 1, i + 2}, hasExplicitTime: true);
        }
        if (n != null && unit == 'saat') return ParsedTime(now.add(Duration(hours: n)), {i, i + 1, i + 2}, hasExplicitTime: true);
      }
    }

    // --- Gün
    DateTime? day;
    for (var i = 0; i < t.length; i++) {
      final w = t[i];
      if (w.startsWith('bugun') || w == 'bu' && i + 1 < t.length && t[i + 1].startsWith('aksam')) {
        day = DateTime(now.year, now.month, now.day);
        used.add(i);
      } else if (w.startsWith('yarin')) {
        day = DateTime(now.year, now.month, now.day + 1);
        used.add(i);
      } else if ((w == 'obur' || w == 'ertesi') && i + 1 < t.length && t[i + 1].startsWith('gun')) {
        day = DateTime(now.year, now.month, now.day + 2);
        used.addAll({i, i + 1});
      } else {
        final base = _days.keys.firstWhere((d) => w == d || (w.startsWith(d) && w.length <= d.length + 3), orElse: () => '');
        // "pazar" ile "pazartesi" karışmasın: uzun ad önce denenir.
        final name = _days.keys.where((d) => w.startsWith(d) && w.length <= d.length + 4).fold<String>('', (a, b) => b.length > a.length ? b : a);
        final chosen = name.isNotEmpty ? name : base;
        if (chosen.isNotEmpty) {
          var diff = (_days[chosen]! - now.weekday) % 7;
          if (diff == 0) diff = 7;
          day = DateTime(now.year, now.month, now.day + diff);
          used.add(i);
          if (i + 1 < t.length && t[i + 1].startsWith('gun')) used.add(i + 1);
        }
      }
    }

    // --- Dönem
    String? period;
    for (var i = 0; i < t.length; i++) {
      final w = t[i];
      if (w.startsWith('sabah')) {
        period = 'am';
        used.add(i);
      } else if (w.startsWith('ogleden') && i + 1 < t.length && t[i + 1].startsWith('sonra')) {
        period = 'pm';
        used.addAll({i, i + 1});
      } else if (w.startsWith('oglen') || w.startsWith('ogle')) {
        period = 'noon';
        used.add(i);
      } else if (w.startsWith('aksam')) {
        period = 'pm';
        used.add(i);
        if (i > 0 && t[i - 1] == 'bu') used.add(i - 1);
      } else if (w.startsWith('gece')) {
        period = 'night';
        used.add(i);
      }
    }

    // --- Saat
    int? hour;
    var minute = 0;
    var twentyFour = false;
    for (var i = 0; i < t.length; i++) {
      final w = t[i];
      final hm = RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch(w);
      if (hm != null) {
        hour = int.parse(hm.group(1)!);
        minute = int.parse(hm.group(2)!);
        twentyFour = true;
        used.add(i);
        break;
      }
      if (w == 'saat' && i + 1 < t.length) {
        final m = RegExp(r'^(\d{1,2})').firstMatch(t[i + 1]);
        if (m != null) {
          hour = int.parse(m.group(1)!);
          used.addAll({i, i + 1});
          if (i + 2 < t.length && t[i + 2].startsWith('bucuk')) {
            minute = 30;
            used.add(i + 2);
          }
          break;
        }
      }
      // "9da", "9a", "7ye", "15te", "9 bucukta"
      final suffixed = RegExp(r'^(\d{1,2})(da|de|ta|te|a|e|ya|ye)$').firstMatch(w);
      if (suffixed != null) {
        hour = int.parse(suffixed.group(1)!);
        used.add(i);
        break;
      }
      final plain = RegExp(r'^(\d{1,2})$').firstMatch(w);
      if (plain != null && i + 1 < t.length && t[i + 1].startsWith('bucuk')) {
        hour = int.parse(plain.group(1)!);
        minute = 30;
        used.addAll({i, i + 1});
        break;
      }
    }

    if (hour == null && day == null && period == null) return null;
    if (hour != null && (hour > 23 || minute > 59)) return null;

    var h = hour;
    if (h != null && !twentyFour) {
      if (period == 'pm' && h < 12) h += 12;
      if (period == 'noon' && h < 6) h += 12;
      if (period == 'night' && h >= 6 && h < 12) h += 12;
      // Belirsiz "saat 3" -> 15:00 (Türkçede iş saati varsayımı), 8 ve üstü olduğu gibi.
      if (period == null && h >= 1 && h <= 7) h += 12;
    }
    h ??= switch (period) {
      'am' => 9,
      'noon' => 12,
      'pm' => 19,
      'night' => 22,
      _ => 9,
    };

    final base = day ?? DateTime(now.year, now.month, now.day);
    var at = DateTime(base.year, base.month, base.day, h, minute);
    if (day == null && !at.isAfter(now)) at = at.add(const Duration(days: 1));
    return ParsedTime(at, used, hasExplicitTime: hour != null || period != null);
  }

  static String format(DateTime at, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(at.year, at.month, at.day);
    final diff = d.difference(today).inDays;
    final dayText = switch (diff) {
      0 => 'bugün',
      1 => 'yarın',
      2 => 'öbür gün',
      _ => '${at.day} ${_months[at.month - 1]} ${_dayNames[at.weekday - 1]}',
    };
    return '$dayText ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }

  static const _months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  static const _dayNames = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
}
