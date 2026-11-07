import 'package:saklaz_core/saklaz_core.dart';

import 'assistant_brain.dart';

/// Yapay zekâ DEĞİLDİR. Ses ve arayüz hattını uçtan uca test edebilmek için
/// birkaç basit Türkçe kalıba yanıt verir; diğer her şeyde dürüstçe AI
/// çekirdeğinin henüz bağlanmadığını söyler. Hiçbir veri cihazdan çıkmaz.
class OfflinePlaceholderBrain implements AssistantBrain {
  OfflinePlaceholderBrain({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  String get displayName => 'Yerel test modu (AI yok)';

  @override
  bool get isOnDevice => true;

  @override
  Future<Result<String>> reply(String userText, List<ChatMessage> history) async {
    final t = normalize(userText);
    if (t.isEmpty) {
      return const Result.ok('Seni duyamadım, tekrar söyler misin?');
    }
    if (_any(t, ['merhaba', 'selam', 'gunaydin', 'iyi aksamlar', 'hey saklaz'])) {
      return const Result.ok('Merhaba, ben SAKLAZ. Seni dinliyorum.');
    }
    if (_any(t, ['saat kac', 'saati soyle'])) {
      final now = _clock();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      return Result.ok('Saat şu an $hh:$mm.');
    }
    if (_any(t, ['bugun gunlerden ne', 'tarih ne', 'bugunun tarihi'])) {
      final now = _clock();
      return Result.ok('Bugün ${now.day} ${_months[now.month - 1]} ${now.year}, ${_days[now.weekday - 1]}.');
    }
    if (_any(t, ['kimsin', 'adin ne', 'sen nesin'])) {
      return const Result.ok(
        'Ben SAKLAZ, kişisel asistanınım. Şu an geliştirmenin ilk aşamasındayım; '
        'yapay zekâ çekirdeğim henüz bağlanmadı.',
      );
    }
    if (_any(t, ['tesekkur', 'sag ol', 'sagol'])) {
      return const Result.ok('Rica ederim.');
    }
    return Result.ok(
      '"${userText.trim()}" dediğini anladım. Yapay zekâ çekirdeğim henüz bağlı değil, '
      'bu yüzden şimdilik yalnızca selamlaşma, saat ve tarih sorularına yanıt verebiliyorum.',
    );
  }

  static bool _any(String text, List<String> patterns) => patterns.any(text.contains);

  /// Küçük harfe çevirir ve Türkçe karakterleri sadeleştirir (eşleştirme için).
  static String normalize(String s) {
    const map = {
      'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g',
      'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c', 'â': 'a', 'Â': 'a',
    };
    final b = StringBuffer();
    for (final ch in s.split('')) {
      b.write(map[ch] ?? ch.toLowerCase());
    }
    return b.toString().replaceAll(RegExp(r'[^\w\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  static const _days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
}
