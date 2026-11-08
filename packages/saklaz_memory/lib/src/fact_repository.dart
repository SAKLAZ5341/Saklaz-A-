import 'package:saklaz_core/saklaz_core.dart';

/// Kişisel bilgi kategorileri. [singleValued] olanlarda yeni bilgi eskisinin yerini alır.
enum FactCategory {
  name('İsim', singleValued: true),
  profession('Meslek', singleValued: true),
  sector('Sektör', singleValued: true),
  company('Çalıştığı yer', singleValued: true),
  location('Yaşadığı yer', singleValued: true),
  project('Proje'),
  interest('İlgi alanı'),
  preference('Tercih'),
  habit('Alışkanlık'),
  goal('Hedef'),
  decision('Karar'),
  person('Yakını'),
  other('Diğer');

  const FactCategory(this.label, {this.singleValued = false});
  final String label;
  final bool singleValued;
}

enum FactStatus { active, archived }

enum FactSource { auto, manual }

class MemoryFact {
  const MemoryFact({
    required this.id,
    required this.category,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.status = FactStatus.active,
    this.source = FactSource.manual,
  });

  final int id;
  final FactCategory category;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final FactStatus status;
  final FactSource source;

  bool get isActive => status == FactStatus.active;

  MemoryFact copyWith({String? text, FactStatus? status, DateTime? updatedAt}) => MemoryFact(
        id: id,
        category: category,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        status: status ?? this.status,
        source: source,
      );
}

enum UpsertOutcome { added, duplicate, replaced }

class UpsertResult {
  const UpsertResult(this.outcome, this.fact, {this.replaced = const []});
  final UpsertOutcome outcome;
  final MemoryFact fact;

  /// Çelişki nedeniyle "eski" olarak arşivlenen bilgiler.
  final List<MemoryFact> replaced;
}

abstract interface class FactRepository {
  /// Varsayılan: yalnızca güncel (aktif) bilgiler, en yeni önce.
  Future<List<MemoryFact>> all({bool includeArchived = false});

  /// Tam metin + benzer kelime araması (aktif bilgiler).
  Future<List<MemoryFact>> search(String query, {int limit = 5});

  /// Ekler; aynı bilgi varsa tazeler; tek değerli kategoride eskisini arşivler.
  Future<UpsertResult> upsert(FactCategory category, String text, {FactSource source = FactSource.manual});

  /// Geriye uyumluluk: kategori "diğer", kaynak "manuel".
  Future<MemoryFact> add(String text);

  Future<void> update(int id, String text);
  Future<void> delete(int id);
  Future<void> clear();
}

/// Ortak çelişki/yinelenme mantığı (SQLite ve bellek içi uygulamalar kullanır).
abstract final class FactRules {
  static bool sameMeaning(String a, String b) {
    final na = normalizeTr(a);
    final nb = normalizeTr(b);
    if (na == nb) return true;
    if (na.length >= 6 && nb.length >= 6 && (na.contains(nb) || nb.contains(na))) return true;
    final ka = keywordsTr(a);
    final kb = keywordsTr(b);
    if (ka.isEmpty || kb.isEmpty) return false;
    final inter = ka.intersection(kb).length;
    return inter / (ka.length > kb.length ? ka.length : kb.length) >= 0.8;
  }
}
