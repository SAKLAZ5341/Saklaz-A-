import 'package:saklaz_core/saklaz_core.dart';

import 'fact_repository.dart';

/// Yerel hafıza araması: Türkçe normalize edilmiş anahtar kelime örtüşmesi.
/// Tamamen cihazda çalışır; hiçbir şey buluta gönderilmez.
class MemorySearch {
  const MemorySearch();

  List<MemoryFact> search(String query, List<MemoryFact> facts, {int limit = 5}) {
    final q = keywordsTr(query);
    if (q.isEmpty) return const [];
    final scored = <(MemoryFact, double)>[];
    for (final f in facts) {
      final words = keywordsTr(f.text);
      var score = 0.0;
      for (final w in q) {
        if (words.contains(w)) {
          score += 1;
        } else if (w.length >= 4 && words.any((x) => x.startsWith(w.substring(0, 4)))) {
          // Türkçe ekler için kaba kök eşleşmesi (doğum / doğumgünüm).
          score += 0.5;
        }
      }
      if (score > 0) scored.add((f, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }
}
