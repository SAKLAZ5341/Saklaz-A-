/// Kullanıcının açık onayıyla kaydedilmiş kişisel bilgi.
class MemoryFact {
  const MemoryFact({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  final int id;
  final String text;
  final DateTime createdAt;
}

abstract interface class FactRepository {
  Future<List<MemoryFact>> all();

  /// YALNIZCA kullanıcı onayından sonra çağrılmalıdır.
  Future<MemoryFact> add(String text);
  Future<void> delete(int id);
  Future<void> clear();
}
