/// Türkçe metni eşleştirme için sadeleştirir: küçük harf, Türkçe karakterler
/// ASCII karşılıklarına, noktalama boşluğa, ardışık boşluklar teke.
String normalizeTr(String s) {
  const map = {
    'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g',
    'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c', 'â': 'a', 'Â': 'a',
    'î': 'i', 'Î': 'i', 'û': 'u', 'Û': 'u',
  };
  final b = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    b.write(map[ch] ?? ch.toLowerCase());
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Anlamsız kısa kelimeleri (bağlaç vb.) ayıklanmış anahtar kelimeler.
Set<String> keywordsTr(String s) {
  const stop = {
    've', 'veya', 'ile', 'bir', 'bu', 'su', 'o', 'da', 'de', 'mi', 'mu', 'ne',
    'benim', 'ben', 'sen', 'icin', 'gibi', 'ama', 'ki', 'cok', 'en', 'daha',
    'neydi', 'nedir', 'kim', 'hangi', 'nerede', 'zaman', 'biliyor', 'musun',
    'hatirla', 'hatirliyor', 'soyle', 'bana',
  };
  return normalizeTr(s).split(' ').where((w) => w.length > 1 && !stop.contains(w)).toSet();
}
