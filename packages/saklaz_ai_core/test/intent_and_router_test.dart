import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:test/test.dart';

void main() {
  const engine = LocalIntentEngine();

  group('LocalIntentEngine', () {
    test('basit komutlar', () {
      expect(engine.classify('Merhaba SAKLAZ'), isA<GreetingIntent>());
      expect(engine.classify('Saat kaç?'), isA<TimeIntent>());
      expect(engine.classify('Bugün günlerden ne'), isA<DateIntent>());
      expect(engine.classify('Sen kimsin'), isA<IdentityIntent>());
      expect(engine.classify('Teşekkürler'), isA<ThanksIntent>());
    });

    test('hatırla ki ... (önek ve sonek)', () {
      final a = engine.classify('Hatırla ki doğum günüm 12 Mart');
      expect(a, isA<RememberIntent>());
      expect((a as RememberIntent).content, 'doğum günüm 12 Mart');
      final b = engine.classify('Arabamın plakası 34 ABC 123, bunu hatırla.');
      expect((b as RememberIntent).content, 'Arabamın plakası 34 ABC 123');
      final c = engine.classify('kaydet: en sevdiğim renk lacivert');
      expect((c as RememberIntent).content, 'en sevdiğim renk lacivert');
    });

    test('hafıza sorgusu', () {
      expect(engine.classify('Doğum günüm ne zamandı?'), isA<MemoryQueryIntent>());
      expect(engine.classify('Plakamı hatırlıyor musun'), isA<MemoryQueryIntent>());
      final all = engine.classify('Hakkımda ne biliyorsun');
      expect((all as MemoryQueryIntent).listAll, isTrue);
    });

    test('genel istek: internet ve karmaşıklık işaretleri', () {
      final w = engine.classify('İstanbul hava durumu nasıl') as GeneralIntent;
      expect(w.needsInternet, isTrue);
      final c = engine.classify('Kuantum bilgisayarları klasik bilgisayarlarla karşılaştır') as GeneralIntent;
      expect(c.complex, isTrue);
      expect(c.needsInternet, isFalse);
      final s = engine.classify('Bana bir fıkra anlat') as GeneralIntent;
      expect(s.complex, isFalse);
    });
  });

  group('AssistantRouter', () {
    const router = AssistantRouter();
    RouteContext ctx({
      CloudMode mode = CloudMode.ask,
      bool configured = true,
      bool online = true,
      bool local = false,
    }) =>
        RouteContext(cloudMode: mode, cloudConfigured: configured, online: online, localLlmReady: local);

    const general = GeneralIntent('fıkra anlat', complex: false, needsInternet: false);
    const complex = GeneralIntent('analiz et', complex: true, needsInternet: false);
    const web = GeneralIntent('hava durumu', complex: false, needsInternet: true);

    test('basit komut ve hafıza her zaman yerel (internet olmasa da)', () {
      expect(router.decide(const TimeIntent(), ctx(online: false)), isA<UseBrain>().having((d) => d.brain, 'brain', Brain.localRules));
      expect(router.decide(const MemoryQueryIntent('x'), ctx(online: false)), isA<UseBrain>().having((d) => d.brain, 'brain', Brain.memory));
    });

    test('karmaşık: izin modunda onay ister, yerel alternatifi bildirir', () {
      final d = router.decide(complex, ctx(local: true));
      expect(d, isA<AskCloudConsent>().having((d) => d.localAlternative, 'local', isTrue));
    });

    test('karmaşık: "her zaman" modunda doğrudan bulut', () {
      expect(router.decide(complex, ctx(mode: CloudMode.always)), isA<UseBrain>().having((d) => d.brain, 'b', Brain.cloud));
    });

    test('karmaşık + çevrimdışı: yerel model varsa onu kullanır', () {
      expect(router.decide(complex, ctx(online: false, local: true)), isA<UseBrain>().having((d) => d.brain, 'b', Brain.localLlm));
      expect(router.decide(complex, ctx(online: false)), isA<Unavailable>().having((d) => d.reason, 'r', UnavailableReason.offline));
    });

    test('genel basit: önce yerel model', () {
      expect(router.decide(general, ctx(local: true, mode: CloudMode.always)), isA<UseBrain>().having((d) => d.brain, 'b', Brain.localLlm));
      expect(router.decide(general, ctx()), isA<AskCloudConsent>());
    });

    test('internet gerektiren: çevrimdışıysa açık neden', () {
      expect(router.decide(web, ctx(online: false, local: true)), isA<Unavailable>().having((d) => d.reason, 'r', UnavailableReason.offline));
      expect(router.decide(web, ctx(configured: false)), isA<Unavailable>().having((d) => d.reason, 'r', UnavailableReason.cloudNotConfigured));
      expect(router.decide(web, ctx(mode: CloudMode.off)), isA<Unavailable>().having((d) => d.reason, 'r', UnavailableReason.cloudDisabled));
    });

    test('bulut kapalıyken asla bulut seçilmez', () {
      for (final i in [general, complex, web]) {
        final d = router.decide(i, ctx(mode: CloudMode.off, local: true));
        expect(d is UseBrain && d.brain == Brain.cloud, isFalse);
        expect(d, isNot(isA<AskCloudConsent>()));
      }
    });
  });
}
