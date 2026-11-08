import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';
import 'package:test/test.dart';

class RecordingLlm implements LlmClient {
  RecordingLlm([this.reply = const Result.ok(LlmReply(text: 'bulut yanıtı'))]);
  final Result<LlmReply> reply;
  final requests = <LlmRequest>[];
  @override
  Future<Result<LlmReply>> complete(LlmRequest request) async {
    requests.add(request);
    return reply;
  }
}

/// Sahte yerel model: gelen istemi kaydeder.
class FakeLocal implements LocalLlm {
  FakeLocal({this.ready = true});
  final bool ready;
  final systems = <String>[];
  final histories = <List<LlmMessage>>[];
  @override
  Future<LocalLlmInfo> info() async => LocalLlmInfo(ready ? LocalLlmState.ready : LocalLlmState.noModel);
  @override
  Future<Result<String>> chat({required String system, required List<LlmMessage> history, required String user, int maxOutputTokens = 384}) async {
    systems.add(system);
    histories.add(history);
    return const Result.ok('<think>x</think>yerel **yanıt**');
  }
}

class FakeDevice extends NoDevice {
  final calls = <String>[];
  bool contactsGranted = true;
  @override
  Future<bool> ensurePermission(DevicePermission p) async => p != DevicePermission.contacts || contactsGranted;
  @override
  Future<List<Contact>> searchContacts(String query) async =>
      query == 'Ahmet' ? const [Contact('Ahmet Yılmaz', '05321112233')] : const [];
  @override
  Future<bool> openWhatsApp(String phone, String text) async {
    calls.add('wa:$phone:$text');
    return true;
  }

  @override
  Future<void> scheduleReminder(int id, String text, DateTime at) async => calls.add('rem:$id:$text:$at');
  @override
  Future<bool> setAlarm(int hour, int minute, String label) async {
    calls.add('alarm:$hour:$minute');
    return true;
  }
}

void main() {
  late InMemoryFactRepository facts;
  late RecordingLlm cloud;
  late FakeLocal local;
  late FakeDevice device;
  late InMemoryNoteRepository notes;
  late InMemoryReminderRepository reminders;
  var ctx = const RouteContext(cloudMode: CloudMode.off, cloudConfigured: false, online: true, localLlmReady: true);
  var autoLearn = true;
  final now = DateTime(2026, 11, 7, 20, 15);

  SaklazAssistant make() => SaklazAssistant(
        facts: facts,
        notes: notes,
        reminders: reminders,
        device: device,
        cloud: () => cloud,
        localLlm: local,
        routeContext: () async => ctx,
        autoLearn: () => autoLearn,
        clock: () => now,
      );

  setUp(() {
    facts = InMemoryFactRepository();
    notes = InMemoryNoteRepository();
    reminders = InMemoryReminderRepository();
    cloud = RecordingLlm();
    local = FakeLocal();
    device = FakeDevice();
    autoLearn = true;
    ctx = const RouteContext(cloudMode: CloudMode.off, cloudConfigured: false, online: true, localLlmReady: true);
  });

  group('Varsayılan: yerel AI, bulut ASLA çağrılmaz', () {
    test('genel soru yerel modelle yanıtlanır; çıktı temizlenir', () async {
      final t = await make().respond('Bana bir fıkra anlat', const []);
      expect(t.source, MessageSource.localLlm);
      expect(t.text, 'yerel yanıt');
      expect(cloud.requests, isEmpty);
    });

    test('karmaşık soru da yerelde kalır (sağlayıcı yok)', () async {
      await make().respond('Kuantum ve klasik bilgisayarları karşılaştır', const []);
      expect(cloud.requests, isEmpty);
      expect(local.systems, hasLength(1));
    });

    test('model yoksa anlaşılır mesaj', () async {
      ctx = const RouteContext(cloudMode: CloudMode.off, cloudConfigured: false, online: true, localLlmReady: false);
      final t = await make().respond('Bana bir fıkra anlat', const []);
      expect(t.text, contains('Model Yönetimi'));
    });

    test('konuşma devamlılığı: önceki mesajlar yerel modele verilir', () async {
      final history = [
        ChatMessage(id: '1', role: ChatRole.user, text: 'Üç öneri ver', createdAt: now),
        ChatMessage(id: '2', role: ChatRole.assistant, text: 'Bir, iki, üç', createdAt: now, source: MessageSource.localLlm),
      ];
      await make().respond('Kaç öneri verdin?', history);
      expect(local.histories.single.map((m) => m.text), ['Üç öneri ver', 'Bir, iki, üç']);
    });
  });

  group('Otomatik kişisel öğrenme', () {
    test('istenen senaryo: öğren -> sonra hafızadan yanıtla', () async {
      final a = make();
      final t = await a.respond('Ben satınalma yöneticisiyim ve ASEDEN ERP üzerinde çalışıyorum.', const []);
      expect(t.learned.map((f) => f.text), ['satınalma yöneticisi', 'ASEDEN ERP']);
      final q = await a.respond('Ben hangi projeler üzerinde çalışıyorum?', const []);
      expect(q.source, MessageSource.memory);
      expect(q.text, 'Proje: ASEDEN ERP.');
      final p = await a.respond('Benim mesleğim ne?', const []);
      expect(p.text, 'Meslek: satınalma yöneticisi.');
      final all = await a.respond('Benim hakkımda ne biliyorsun?', const []);
      expect(all.text, allOf(contains('satınalma yöneticisi'), contains('ASEDEN ERP')));
    });

    test('ilgili bilgiler yerel modele bağlam olarak verilir', () async {
      final a = make();
      await a.respond('Ben satınalma yöneticisiyim', const []);
      await a.respond('Satınalma süreçlerini nasıl iyileştirebilirim', const []);
      expect(local.systems.last, contains('Meslek: satınalma yöneticisi'));
      expect(local.systems.last, contains('KULLANICIYA aittir'));
    });

    test('çelişki: yeni meslek eskisini arşivler', () async {
      final a = make();
      await a.respond('Ben muhasebeciyim', const []);
      await a.respond('Ben satınalma yöneticisiyim', const []);
      expect((await facts.all()).single.text, 'satınalma yöneticisi');
      expect((await facts.all(includeArchived: true)), hasLength(2));
    });

    test('otomatik öğrenme kapatılabilir', () async {
      autoLearn = false;
      final t = await make().respond('Ben satınalma yöneticisiyim', const []);
      expect(t.learned, isEmpty);
      expect(await facts.all(), isEmpty);
    });

    test('sırlar kaydedilmez (açık "hatırla" isteğinde bile)', () async {
      final t = await make().respond('Hatırla ki şifrem Lacivert123', const []);
      expect(t.pending, isNull);
      expect(t.text, contains('kaydetmiyorum'));
      expect(await facts.all(), isEmpty);
    });

    test('model yokken bile öğrenilenler bildirilir', () async {
      ctx = const RouteContext(cloudMode: CloudMode.off, cloudConfigured: false, online: true, localLlmReady: false);
      final t = await make().respond('Ben satınalma yöneticisiyim', const []);
      expect(t.text, contains('Not ettim'));
    });
  });

  group('Agent: onaylı telefon işlemleri', () {
    test('hatırlatıcı: onay -> veritabanı + sistem alarmı', () async {
      final a = make();
      final t = await a.respond("Yarın sabah 9'da toplantıyı hatırlat", const []);
      final p = t.pending! as ConfirmAgentAction;
      expect(p.voiceConfirmable, isTrue);
      expect(await reminders.all(), isEmpty, reason: 'onaysız kaydedilmez');
      await a.execute(p.action);
      expect((await reminders.all()).single.text, 'toplantıyı');
      expect(device.calls.single, startsWith('rem:1:toplantıyı:2026-11-08 09:00'));
    });

    test('WhatsApp: rehberden kişi bulunur, yüksek risk -> sesli onay geçersiz', () async {
      final a = make();
      final t = await a.respond("Ahmet'e WhatsApp'tan geç kalacağımı yaz", const []);
      final p = t.pending! as ConfirmAgentAction;
      expect(p.action, isA<WhatsAppAction>());
      expect(p.voiceConfirmable, isFalse);
      expect(device.calls, isEmpty);
      await a.execute(p.action);
      expect(device.calls.single, 'wa:05321112233:geç kalacağım');
    });

    test('rehber izni yoksa açık mesaj', () async {
      device.contactsGranted = false;
      final t = await make().respond("Ahmet'i ara", const []);
      expect(t.text, contains('Rehber izni'));
    });

    test('not ve alarm', () async {
      final a = make();
      final n = await a.respond('Not al: süt al', const []);
      await a.execute((n.pending! as ConfirmAgentAction).action);
      expect((await notes.all()).single.text, 'süt al');
      final al = await a.respond("Yarın 6:30'a alarm kur", const []);
      await a.execute((al.pending! as ConfirmAgentAction).action);
      expect(device.calls.last, 'alarm:6:30');
    });
  });

  group('Bulut (yalnızca kullanıcı etkinleştirirse)', () {
    test('sağlayıcı etkin + sor modu: izin istenir, onayla gönderilir', () async {
      ctx = const RouteContext(cloudMode: CloudMode.ask, cloudConfigured: true, online: true, localLlmReady: true);
      final a = make();
      final t = await a.respond('Kuantum ve klasik bilgisayarları karşılaştır', const []);
      expect(t.pending, isA<ConfirmCloud>());
      expect(cloud.requests, isEmpty);
      final r = await a.answerWithCloud(t.pending! as ConfirmCloud, const []);
      expect(r.source, MessageSource.cloud);
    });

    test('kişisel bilgiler izin olmadan buluta gitmez', () async {
      await facts.upsert(FactCategory.profession, 'satınalma yöneticisi');
      ctx = const RouteContext(cloudMode: CloudMode.always, cloudConfigured: true, online: true, localLlmReady: false);
      await make().respond('Satınalma süreçlerini analiz et', const []);
      expect(cloud.requests.single.instructions, isNot(contains('satınalma yöneticisi')));
    });
  });
}
