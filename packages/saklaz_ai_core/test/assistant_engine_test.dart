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

class FakeLocal implements LocalLlm {
  FakeLocal({this.ready = true});
  final bool ready;
  final prompts = <String>[];
  @override
  Future<LocalLlmInfo> info() async => LocalLlmInfo(ready ? LocalLlmState.ready : LocalLlmState.unavailable);
  @override
  Future<LocalLlmInfo> download() => info();
  @override
  Future<Result<String>> generate(String prompt, {int maxOutputTokens = 256, double temperature = 0.3}) async {
    prompts.add(prompt);
    return const Result.ok('yerel yanıt');
  }
}

void main() {
  late InMemoryFactRepository facts;
  late RecordingLlm cloud;
  late FakeLocal local;
  var ctx = const RouteContext(cloudMode: CloudMode.ask, cloudConfigured: true, online: true, localLlmReady: false);
  var shareFacts = false;

  SaklazAssistant make() => SaklazAssistant(
        facts: facts,
        cloud: () => cloud,
        localLlm: local,
        routeContext: () async => ctx,
        shareFactsWithCloud: () => shareFacts,
        clock: () => DateTime(2026, 11, 8, 14, 30),
      );

  setUp(() {
    facts = InMemoryFactRepository();
    cloud = RecordingLlm();
    local = FakeLocal(ready: false);
    ctx = const RouteContext(cloudMode: CloudMode.ask, cloudConfigured: true, online: true, localLlmReady: false);
    shareFacts = false;
  });

  test('saat yerel kurallarla, buluta gitmeden', () async {
    final t = await make().respond('Saat kaç', const []);
    expect(t.text, 'Saat şu an 14:30.');
    expect(t.source, MessageSource.localRules);
    expect(cloud.requests, isEmpty);
  });

  test('hatırla: onaysız KAYDETMEZ, onayla kaydeder', () async {
    final a = make();
    final t = await a.respond('Hatırla ki doğum günüm 12 Mart', const []);
    expect(t.pending, isA<ConfirmRemember>());
    expect(await facts.all(), isEmpty);
    await a.confirmRemember(t.pending! as ConfirmRemember);
    expect((await facts.all()).single.text, 'doğum günüm 12 Mart');
  });

  test('hafıza sorgusu yerelde yanıtlanır', () async {
    await facts.add('Doğum günüm 12 Mart');
    final t = await make().respond('Doğum günüm ne zamandı?', const []);
    expect(t.source, MessageSource.memory);
    expect(t.text, contains('12 Mart'));
    expect(cloud.requests, isEmpty);
  });

  test('karmaşık soru: izin ister; onaylanınca buluta gider', () async {
    final a = make();
    final t = await a.respond('Kuantum ve klasik bilgisayarları karşılaştır', const []);
    expect(t.pending, isA<ConfirmCloud>());
    expect(cloud.requests, isEmpty);
    final r = await a.answerWithCloud(t.pending! as ConfirmCloud, const []);
    expect(r.source, MessageSource.cloud);
    expect(cloud.requests.single.messages.last.text, 'Kuantum ve klasik bilgisayarları karşılaştır');
  });

  test('veri azaltma: buluta en fazla 6 önceki mesaj; kişisel bilgiler gönderilmez', () async {
    await facts.add('Bilgisayar şifrem 1234');
    ctx = const RouteContext(cloudMode: CloudMode.always, cloudConfigured: true, online: true, localLlmReady: false);
    final history = [
      for (var i = 0; i < 20; i++)
        ChatMessage(id: '$i', role: i.isEven ? ChatRole.user : ChatRole.assistant, text: 'm$i', createdAt: DateTime(2026)),
    ];
    await make().respond('Bilgisayar mimarisini analiz et', history);
    final req = cloud.requests.single;
    expect(req.messages, hasLength(7));
    expect(req.instructions, isNot(contains('1234')));
  });

  test('kullanıcı izin verirse ilgili kişisel bilgi bağlama eklenir', () async {
    await facts.add('Bilgisayar şifrem 1234');
    shareFacts = true;
    ctx = const RouteContext(cloudMode: CloudMode.always, cloudConfigured: true, online: true, localLlmReady: false);
    await make().respond('Bilgisayar mimarisini analiz et', const []);
    expect(cloud.requests.single.instructions, contains('1234'));
  });

  test('çevrimdışı + yerel model: yerel yanıt, kayıtlı bilgi yerelde kullanılabilir', () async {
    await facts.add('Kızımın adı Elif');
    local = FakeLocal();
    ctx = const RouteContext(cloudMode: CloudMode.ask, cloudConfigured: true, online: false, localLlmReady: true);
    final t = await make().respond('Kızım Elif için bir masal anlat', const []);
    expect(t.source, MessageSource.localLlm);
    expect(local.prompts.single, contains('Elif'));
    expect(cloud.requests, isEmpty);
  });

  test('çevrimdışı ve model yok: anlaşılır mesaj', () async {
    ctx = const RouteContext(cloudMode: CloudMode.ask, cloudConfigured: true, online: false, localLlmReady: false);
    final t = await make().respond('Bana bir fıkra anlat', const []);
    expect(t.text, contains('internet bağlantısı yok'));
    expect(t.source, MessageSource.system);
  });

  test('bulut hatası kullanıcıya açıklanır, uydurma yanıt verilmez', () async {
    cloud = RecordingLlm(const Result.err(Failure('budget', 'Günlük bulut bütçesi doldu.')));
    ctx = const RouteContext(cloudMode: CloudMode.always, cloudConfigured: true, online: true, localLlmReady: false);
    final t = await make().respond('Bunu analiz et lütfen', const []);
    expect(t.source, MessageSource.system);
    expect(t.text, contains('bütçesi doldu'));
  });

  test('bulut reddedilirse yerel model varsa onunla yanıtlar', () async {
    local = FakeLocal();
    ctx = const RouteContext(cloudMode: CloudMode.ask, cloudConfigured: true, online: true, localLlmReady: true);
    final a = make();
    final t = await a.respond('Kuantum ve klasik bilgisayarları karşılaştır', const []);
    final r = await a.answerLocally(t.pending! as ConfirmCloud, const []);
    expect(r.source, MessageSource.localLlm);
    expect(cloud.requests, isEmpty);
  });
}
