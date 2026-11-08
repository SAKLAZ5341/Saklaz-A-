import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_memory/saklaz_memory.dart';
import 'package:test/test.dart';

void main() {
  // Cumartesi 7 Kasım 2026, 20:15
  final now = DateTime(2026, 11, 7, 20, 15);
  DateTime? at(String s) => TurkishTime.parse(s, now)?.at;

  group('TurkishTime', () {
    test('göreli süreler', () {
      expect(at('10 dakika sonra'), now.add(const Duration(minutes: 10)));
      expect(at('on dakika sonra'), now.add(const Duration(minutes: 10)));
      expect(at('yarım saat sonra'), now.add(const Duration(minutes: 30)));
      expect(at('2 saat sonra'), now.add(const Duration(hours: 2)));
    });

    test('gün + saat', () {
      expect(at("yarın sabah 9'da"), DateTime(2026, 11, 8, 9));
      expect(at('yarın 14:30'), DateTime(2026, 11, 8, 14, 30));
      expect(at("öbür gün akşam 8'de"), DateTime(2026, 11, 9, 20));
      expect(at("pazartesi saat 10'da"), DateTime(2026, 11, 9, 10));
      expect(at('cuma 9 buçukta'), DateTime(2026, 11, 13, 9, 30));
    });

    test('pazar ile pazartesi karışmaz', () {
      expect(at("pazar 11'de"), DateTime(2026, 11, 8, 11));
      expect(at("pazartesi 11'de"), DateTime(2026, 11, 9, 11));
    });

    test('yalnızca saat: geçmişse yarına kayar; belirsiz 1-7 öğleden sonra', () {
      expect(at("saat 9'da"), DateTime(2026, 11, 8, 9));
      expect(at("saat 3'te"), DateTime(2026, 11, 8, 15));
      expect(at("akşam 9'da"), DateTime(2026, 11, 7, 21));
      expect(at('22:00'), DateTime(2026, 11, 7, 22));
    });

    test('zaman yoksa null', () {
      expect(at('toplantıyı unutma'), isNull);
    });
  });

  group('FactExtractor (otomatik öğrenme)', () {
    const x = FactExtractor();
    List<String> f(String s) => x.extract(s).map((e) => e.toString()).toList();

    test('istenen örnek: meslek + proje', () {
      expect(f('Ben satınalma yöneticisiyim ve ASEDEN ERP üzerinde çalışıyorum.'),
          ['profession: satınalma yöneticisi', 'project: ASEDEN ERP']);
    });

    test('farklı kalıplar', () {
      expect(f('Yazılım mühendisi olarak çalışıyorum'), ['profession: Yazılım mühendisi']);
      expect(f('Mesleğim öğretmen'), ['profession: öğretmen']);
      expect(f('Otomotiv sektöründe çalışıyorum'), ['sector: Otomotiv']);
      expect(f("Arçelik'te çalışıyorum"), ['company: Arçelik']);
      expect(f("İstanbul'da yaşıyorum"), ['location: İstanbul']);
      expect(f('Benim adım Fatih'), ['name: Fatih']);
      expect(f('Eşimin adı Ayşe'), ['person: Eşi: Ayşe']);
      expect(f('Hedefim bu yıl İngilizce öğrenmek'), ['goal: bu yıl İngilizce öğrenmek']);
      expect(f('Hobim satranç'), ['interest: satranç']);
      expect(f('Fotoğrafçılıkla ilgileniyorum'), ['interest: Fotoğrafçılık']);
      expect(f('En sevdiğim renk lacivert'), ['preference: En sevdiğim renk lacivert']);
      expect(f('Her sabah 6da koşarım'), ['habit: Her sabah 6da koşarım']);
      expect(f('Yeni tedarikçiyle çalışmaya karar verdim'), ['decision: Yeni tedarikçiyle çalışmaya']);
    });

    test('sorulardan ve sıradan cümlelerden bilgi çıkarmaz', () {
      expect(f('Ben hangi projeler üzerinde çalışıyorum?'), isEmpty);
      expect(f('Bugün hava çok güzel'), isEmpty);
      expect(f('Seni seviyorum'), isEmpty);
    });

    test('hassas sırları ASLA otomatik kaydetmez', () {
      expect(f('Benim şifrem Lacivert123 ve bankada çalışıyorum'), isEmpty);
      expect(f('Kart numaram 4543 1234 5678 9012'), isEmpty);
      expect(f('IBAN TR330006100519786457841326'), isEmpty);
      expect(f('API anahtarım sk-abcdefghijklmnop1234'), isEmpty);
      expect(SensitiveFilter.isSensitive('TC kimlik numaram 12345678901'), isTrue);
      expect(SensitiveFilter.isSensitive('ASEDEN ERP üzerinde çalışıyorum'), isFalse);
    });
  });

  group('LocalIntentEngine (agent komutları)', () {
    final e = LocalIntentEngine(clock: () => now);

    test('hatırlatıcı (hatırla ile karışmaz)', () {
      final r = e.classify("Yarın sabah 9'da toplantıyı hatırlat") as ReminderIntent;
      expect(r.at, DateTime(2026, 11, 8, 9));
      expect(r.task, 'toplantıyı');
      expect(e.classify('Hatırla ki doğum günüm 12 Mart'), isA<RememberIntent>());
      expect((e.classify('Bana 10 dakika sonra ilacımı hatırlat') as ReminderIntent).task, 'ilacımı');
    });

    test('not, alarm, takvim', () {
      expect((e.classify('Not al: süt ve ekmek') as NoteIntent).text, 'süt ve ekmek');
      expect((e.classify("Yarın 6:30'a alarm kur") as AlarmIntent).at, DateTime(2026, 11, 8, 6, 30));
      final c = e.classify("Takvime cuma 14'te dişçi randevusu ekle") as CalendarAddIntent;
      expect(c.title, 'dişçi randevusu');
      expect(c.at, DateTime(2026, 11, 13, 14));
      expect((e.classify('Yarın takvimimde ne var') as CalendarQueryIntent).day, DateTime(2026, 11, 8));
    });

    test('arama, WhatsApp, uygulama, ayar, bildirim', () {
      expect((e.classify("Ahmet'i ara") as CallIntent).target, 'Ahmet');
      final w = e.classify("Ahmet'e WhatsApp'tan geç kalacağımı yaz") as WhatsAppIntent;
      expect(w.target, 'Ahmet');
      expect(w.message, 'geç kalacağım');
      final w2 = e.classify("Ayşe'ye WhatsApp mesajı: akşam görüşelim") as WhatsAppIntent;
      expect((w2.target, w2.message), ('Ayşe', 'akşam görüşelim'));
      expect((e.classify('Spotify aç') as OpenAppIntent).name, 'Spotify');
      expect((e.classify('Wifi ayarlarını aç') as OpenSettingsIntent).target, SettingsTarget.wifi);
      expect(e.classify('Bildirimlerimi oku'), isA<NotificationsIntent>());
    });

    test('kategorili hafıza soruları', () {
      expect((e.classify('Ben hangi projeler üzerinde çalışıyorum?') as MemoryQueryIntent).category, FactCategory.project);
      expect((e.classify('Benim mesleğim ne?') as MemoryQueryIntent).category, FactCategory.profession);
      expect((e.classify('Benim hakkımda ne biliyorsun?') as MemoryQueryIntent).listAll, isTrue);
    });

    test('bilgi cümlesi genel sohbettir (öğrenme ayrıca yapılır)', () {
      expect(e.classify('Ben satınalma yöneticisiyim ve ASEDEN ERP üzerinde çalışıyorum.'), isA<GeneralIntent>());
    });
  });

  group('YesNo', () {
    test('sesli onay', () {
      expect(YesNo.parse('Evet'), isTrue);
      expect(YesNo.parse('tamam kaydet'), isTrue);
      expect(YesNo.parse('Hayır vazgeç'), isFalse);
      expect(YesNo.parse('yarın hava nasıl olacak acaba'), isNull);
    });
  });

  test('cleanModelText: think blokları ve markdown temizlenir', () {
    expect(cleanModelText('<think>düşün</think>**Merhaba**, ben SAKLAZ.'), 'Merhaba, ben SAKLAZ.');
    expect(cleanModelText('1. **Yürüyüş** yap\n- su iç'), '1. Yürüyüş yap\nsu iç');
  });
}
