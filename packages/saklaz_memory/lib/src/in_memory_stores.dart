import 'fact_repository.dart';
import 'memory_search.dart';
import 'preferences_store.dart';

class InMemoryFactRepository implements FactRepository {
  final _facts = <MemoryFact>[];
  int _id = 0;

  @override
  Future<List<MemoryFact>> all({bool includeArchived = false}) async {
    final list = _facts.where((f) => includeArchived || f.isActive).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<List<MemoryFact>> search(String query, {int limit = 5}) async =>
      const MemorySearch().search(query, await all(), limit: limit);

  @override
  Future<UpsertResult> upsert(FactCategory category, String text, {FactSource source = FactSource.manual}) async {
    final now = DateTime.now();
    final active = _facts.where((f) => f.isActive && f.category == category).toList();
    for (final f in active) {
      if (FactRules.sameMeaning(f.text, text)) {
        final touched = f.copyWith(updatedAt: now);
        _facts[_facts.indexOf(f)] = touched;
        return UpsertResult(UpsertOutcome.duplicate, touched);
      }
    }
    final replaced = <MemoryFact>[];
    if (category.singleValued) {
      for (final f in active) {
        final archived = f.copyWith(status: FactStatus.archived, updatedAt: now);
        _facts[_facts.indexOf(f)] = archived;
        replaced.add(archived);
      }
    }
    final fact = MemoryFact(id: ++_id, category: category, text: text, createdAt: now, updatedAt: now, source: source);
    _facts.add(fact);
    return UpsertResult(replaced.isEmpty ? UpsertOutcome.added : UpsertOutcome.replaced, fact, replaced: replaced);
  }

  @override
  Future<MemoryFact> add(String text) async => (await upsert(FactCategory.other, text)).fact;

  @override
  Future<void> update(int id, String text) async {
    final i = _facts.indexWhere((f) => f.id == id);
    if (i >= 0) _facts[i] = _facts[i].copyWith(text: text, updatedAt: DateTime.now());
  }

  @override
  Future<void> delete(int id) async => _facts.removeWhere((f) => f.id == id);

  @override
  Future<void> clear() async => _facts.clear();
}

class InMemoryPreferencesStore implements PreferencesStore {
  final _map = <String, String>{};

  @override
  Future<Map<String, String>> readAll() async => Map.unmodifiable(_map);

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }
}
