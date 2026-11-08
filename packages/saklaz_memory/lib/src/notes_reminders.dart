class Note {
  const Note({required this.id, required this.text, required this.createdAt});
  final int id;
  final String text;
  final DateTime createdAt;
}

abstract interface class NoteRepository {
  Future<List<Note>> all();
  Future<Note> add(String text);
  Future<void> delete(int id);
}

class Reminder {
  const Reminder({required this.id, required this.text, required this.dueAt, required this.createdAt, this.done = false});
  final int id;
  final String text;
  final DateTime dueAt;
  final DateTime createdAt;
  final bool done;
}

abstract interface class ReminderRepository {
  Future<List<Reminder>> all();
  Future<List<Reminder>> upcoming(DateTime now);
  Future<Reminder> add(String text, DateTime dueAt);
  Future<void> markDone(int id);
  Future<void> delete(int id);
}

class InMemoryNoteRepository implements NoteRepository {
  final _items = <Note>[];
  int _id = 0;
  @override
  Future<List<Note>> all() async => List.unmodifiable(_items.reversed);
  @override
  Future<Note> add(String text) async {
    final n = Note(id: ++_id, text: text, createdAt: DateTime.now());
    _items.add(n);
    return n;
  }

  @override
  Future<void> delete(int id) async => _items.removeWhere((n) => n.id == id);
}

class InMemoryReminderRepository implements ReminderRepository {
  final _items = <Reminder>[];
  int _id = 0;
  @override
  Future<List<Reminder>> all() async => [..._items]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  @override
  Future<List<Reminder>> upcoming(DateTime now) async =>
      (await all()).where((r) => !r.done && r.dueAt.isAfter(now)).toList();
  @override
  Future<Reminder> add(String text, DateTime dueAt) async {
    final r = Reminder(id: ++_id, text: text, dueAt: dueAt, createdAt: DateTime.now());
    _items.add(r);
    return r;
  }

  @override
  Future<void> markDone(int id) async {
    final i = _items.indexWhere((r) => r.id == id);
    if (i >= 0) {
      final r = _items[i];
      _items[i] = Reminder(id: r.id, text: r.text, dueAt: r.dueAt, createdAt: r.createdAt, done: true);
    }
  }

  @override
  Future<void> delete(int id) async => _items.removeWhere((r) => r.id == id);
}
