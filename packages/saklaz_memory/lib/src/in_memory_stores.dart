import 'fact_repository.dart';
import 'preferences_store.dart';

class InMemoryFactRepository implements FactRepository {
  final _facts = <MemoryFact>[];
  int _id = 0;

  @override
  Future<List<MemoryFact>> all() async => List.unmodifiable(_facts.reversed);

  @override
  Future<MemoryFact> add(String text) async {
    final f = MemoryFact(id: ++_id, text: text, createdAt: DateTime.now());
    _facts.add(f);
    return f;
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
