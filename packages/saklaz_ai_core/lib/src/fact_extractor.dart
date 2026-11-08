import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';

class ExtractedFact {
  const ExtractedFact(this.category, this.text);
  final FactCategory category;
  final String text;
  @override
  String toString() => '${category.name}: $text';
}

/// Hassas sırları (şifre, kart, IBAN, kimlik no, API anahtarı) tespit eder.
/// Bunlar OTOMATİK olarak asla kaydedilmez.
abstract final class SensitiveFilter {
  static const _words = [
    'sifre', 'parola', 'pin kod', 'pin numara', 'pinim', 'cvv', 'cvc', 'kart numara', 'kredi kart', 'banka kart',
    'iban', 'hesap numara', 'tc kimlik', 'kimlik numara', 'tckn', 'api key', 'api anahtar', 'token', 'secret',
    'gizli anahtar', 'private key', 'ozel anahtar', 'seed', 'kurtarma kelime', 'dogrulama kod', 'onay kod', 'sms kod',
  ];

  static bool isSensitive(String text) {
    final n = normalizeTr(text);
    if (_words.any(n.contains)) return true;
    final compact = text.replaceAll(RegExp(r'[\s-]'), '');
    if (RegExp(r'\d{11,}').hasMatch(compact)) return true; // TC kimlik, kart
    if (RegExp(r'TR\d{2}[0-9A-Z]{10,}', caseSensitive: false).hasMatch(compact)) return true; // IBAN
    if (RegExp(r'\b(sk|pk|rk)-[A-Za-z0-9_-]{12,}').hasMatch(text)) return true; // API anahtarları
    if (RegExp(r'\b[A-Za-z0-9+/_-]{32,}\b').hasMatch(text)) return true; // uzun rastgele dizgeler
    return false;
  }
}

/// Kullanıcı mesajlarından kalıcı kişisel bilgileri KURAL TABANLI çıkarır.
///
/// Neden LLM değil? Küçük cihaz modeli (Qwen3-1.7B) gerçek testte bilgi uydurdu;
/// kural tabanlı çıkarım deterministik, test edilebilir ve uydurmaz.
class FactExtractor {
  const FactExtractor();

  static const _w = r"[A-Za-zÇĞİÖŞÜçğıöşüâîû0-9&.\-]";

  static const _professions = [
    'yönetici', 'müdür', 'mühendis', 'uzman', 'öğretmen', 'doktor', 'avukat', 'geliştirici', 'tasarımcı', 'analist',
    'muhasebeci', 'hemşire', 'öğrenci', 'emekli', 'danışman', 'mimar', 'eczacı', 'polis', 'aşçı', 'teknisyen',
    'operatör', 'yazılımcı', 'programcı', 'girişimci', 'şef', 'satıcı', 'esnaf', 'şoför', 'memur', 'işçi', 'asistan',
    'sekreter', 'direktör', 'koordinatör', 'sorumlu', 'temsilci', 'editör', 'gazeteci', 'pilot', 'antrenör',
    'psikolog', 'veteriner', 'hekim', 'çiftçi', 'tüccar', 'bankacı', 'sigortacı', 'akademisyen', 'araştırmacı',
    'yazar', 'sanatçı', 'müzisyen', 'fotoğrafçı', 'şef', 'kaptan', 'subay', 'astsubay', 'hakim', 'savcı',
  ];

  static const _relations = {
    'esim': 'Eşi', 'annem': 'Annesi', 'babam': 'Babası', 'kizim': 'Kızı', 'oglum': 'Oğlu', 'kardesim': 'Kardeşi',
    'ablam': 'Ablası', 'abim': 'Ağabeyi', 'patronum': 'Patronu', 'muduru': 'Müdürü', 'mudurum': 'Müdürü',
    'arkadasim': 'Arkadaşı', 'sevgilim': 'Sevgilisi', 'kopegim': 'Köpeği', 'kedim': 'Kedisi',
  };

  /// Soru cümleleri bilgi kaynağı sayılmaz.
  static bool isQuestion(String text) {
    final t = text.trim();
    if (t.endsWith('?')) return true;
    final n = normalizeTr(t);
    final words = n.split(' ');
    const qWords = {'mi', 'mu', 'misin', 'musun', 'miyim', 'muyum', 'midir', 'ne', 'neden', 'nasil', 'nerede', 'kim', 'hangi', 'kac'};
    return words.any(qWords.contains) || n.startsWith('ne ') || n.contains('biliyor musun');
  }

  List<ExtractedFact> extract(String text) {
    if (text.trim().length < 6 || isQuestion(text) || SensitiveFilter.isSensitive(text)) return const [];
    final out = <ExtractedFact>[];
    for (final clause in _clauses(text)) {
      final c = clause.trim();
      if (c.length < 4) continue;
      final f = _fromClause(c);
      if (f != null && !out.any((x) => x.category == f.category && x.text == f.text)) out.add(f);
    }
    return out;
  }

  static List<String> _clauses(String text) => text
      .split(RegExp(r'[.;!?\n]|,\s*|\s+(?:ve|ama|fakat|ayrıca|ancak|ayrica)\s+', caseSensitive: false))
      .where((s) => s.trim().isNotEmpty)
      .toList();

  static RegExp _re(String p) => RegExp(p, caseSensitive: false, unicode: true);

  static String _clean(String s) => s
      .trim()
      .replaceAll(RegExp(r'^(?:ben|bir|benim)\s+', caseSensitive: false), '')
      .replaceAll(RegExp(r"['’]\S*$"), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  ExtractedFact? _fromClause(String c) {
    RegExpMatch? m;

    // İsim
    m = _re(r'^(?:benim\s+)?(?:adım|ismim)\s+(' + _w + r'+(?:\s+' + _w + r'+)?)').firstMatch(c);
    if (m != null) {
      final name = m.group(1)!.replaceAll(RegExp(r'(dır|dir|dur|dür)$'), '');
      if (name.length >= 2) return ExtractedFact(FactCategory.name, name);
    }

    // Proje (şirketten önce: "üzerinde çalışıyorum" -> -de ile biter)
    m = _re(r'^(?:ben\s+)?(.{2,60}?)\s+(?:projesi\s+)?(?:üzerinde|projesinde)\s+çalışıyorum').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.project, _clean(m.group(1)!));
    m = _re(r'^(?:benim\s+)?(?:projem|projemin adı)\s+(.{2,60})$').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.project, _clean(m.group(1)!));
    m = _re(r'^(?:ben\s+)?(.{2,60}?)\s+projesini\s+(?:yürütüyorum|geliştiriyorum|yönetiyorum)').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.project, _clean(m.group(1)!));

    // Sektör
    m = _re(r'^(?:ben\s+)?(.{2,40}?)\s+sektöründe\s+(?:çalışıyorum|çalışırım)').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.sector, _clean(m.group(1)!));

    // Meslek
    m = _re(r'^(?:benim\s+)?(?:mesleğim|işim)\s+(.{3,50})$').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.profession, _clean(m.group(1)!));
    m = _re(r'^(?:ben\s+)?(.{3,50}?)\s+olarak\s+çalışıyorum').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.profession, _clean(m.group(1)!));
    final prof = _professions.join('|');
    m = _re(r'^ben\s+(?:bir\s+)?((?:\S+\s+){0,3}?(?:' + prof + r')\S*?)(?:y)?(?:ım|im|um|üm)$').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.profession, _clean(m.group(1)!));

    // Çalıştığı yer (şirket)
    m = _re(r'^(?:ben\s+)?(.{2,40}?)[\s\x27’]*(?:da|de|ta|te)\s+çalışıyorum$').firstMatch(c);
    if (m != null && !_re(r'(üzerin|projesin|sektörün|olarak|evde|burada|orada|şurada)$').hasMatch(m.group(1)!)) {
      return ExtractedFact(FactCategory.company, _clean(m.group(1)!));
    }

    // Yaşadığı yer
    m = _re(r'^(?:ben\s+)?(.{2,30}?)[\s\x27’]*(?:da|de|ta|te)\s+(?:yaşıyorum|oturuyorum)$').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.location, _clean(m.group(1)!));

    // Yakınları
    m = _re(r'^(\S+?)(?:ın|in|un|ün|nın|nin|nun|nün)?\s+(?:adı|ismi)\s+(' + _w + r'+)').firstMatch(c);
    if (m != null) {
      final rel = _relations[normalizeTr(m.group(1)!)];
      if (rel != null) return ExtractedFact(FactCategory.person, '$rel: ${m.group(2)}');
    }

    // Hedef
    m = _re(r'^(?:benim\s+)?(?:hedefim|amacım|planım|hayalim)\s+(.{3,100})$').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.goal, _clean(m.group(1)!));
    m = _re(r'^(?:uzun vadede\s+)?(.{3,100}?)\s+(?:hedefliyorum|planlıyorum)$').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.goal, _clean(m.group(1)!));

    // Karar
    m = _re(r'^(.{3,100}?)\s+karar\s+verdim$').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.decision, _clean(m.group(1)!));

    // İlgi alanı
    m = _re(r'^(?:benim\s+)?(?:hobim|hobilerim|ilgi alanım|ilgi alanlarım)\s+(.{2,80})$').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.interest, _clean(m.group(1)!));
    m = _re(r'^(?:ben\s+)?(.{2,50}?)\s+(?:ile\s+)?ilgileniyorum$').firstMatch(c);
    if (m != null) return ExtractedFact(FactCategory.interest, _clean(m.group(1)!).replaceAll(RegExp(r'(la|le)$'), ''));
    m = _re(r'^(?:ben\s+)?(.{2,50}?)\s+(?:yapmayı|oynamayı|okumayı|dinlemeyi|izlemeyi)?\s*(?:çok\s+)?seviyorum$').firstMatch(c);
    if (m != null && !_re(r'^(seni|onu|sizi|bunu|şunu|onları)$').hasMatch(m.group(1)!.trim())) {
      return ExtractedFact(FactCategory.interest, c.replaceAll(RegExp(r'^ben\s+', caseSensitive: false), ''));
    }

    // Tercih
    if (_re(r'^(?:benim\s+)?en sevdiğim\s+\S+').hasMatch(c) || _re(r'\s(?:tercih ederim|tercih ediyorum|sevmiyorum|sevmem)$').hasMatch(c)) {
      return ExtractedFact(FactCategory.preference, c.replaceAll(RegExp(r'^(?:ben|benim)\s+', caseSensitive: false), ''));
    }

    // Alışkanlık
    if (_re(r'^(?:ben\s+)?(?:her\s+(?:sabah|gün|akşam|hafta|gece|pazar|cumartesi|hafta sonu)|genellikle|genelde|hep)\s+.{3,80}(?:ım|im|um|üm|rım|rim|rum|rüm|yorum)$').hasMatch(c)) {
      return ExtractedFact(FactCategory.habit, c.replaceAll(RegExp(r'^ben\s+', caseSensitive: false), ''));
    }
    return null;
  }
}
