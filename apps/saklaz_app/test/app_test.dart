import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_app/application/conversation_controller.dart';
import 'package:saklaz_app/application/settings_controller.dart';
import 'package:saklaz_app/infrastructure/providers.dart';
import 'package:saklaz_app/presentation/layout/breakpoints.dart';
import 'package:saklaz_app/presentation/saklaz_app.dart';
import 'package:saklaz_app/presentation/widgets/ai_orb.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import 'fakes.dart';

Future<ProviderContainer> pumpApp(WidgetTester tester, Fakes f, {Size size = const Size(412, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: f.overrides, child: const SaklazApp()));
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// Küre animasyonu sürekli döndüğü için pumpAndSettle yerine sabit kareler.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder get startBtn => find.widgetWithText(FilledButton, 'Konuşmayı Başlat');
Finder get stopBtn => find.widgetWithText(OutlinedButton, 'Konuşmayı Durdur');

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await settle(tester);
}

void main() {
  test('Fold 7 kırılma noktaları', () {
    expect(layoutFor(412), SaklazLayout.compact);
    expect(layoutFor(700), SaklazLayout.medium);
    expect(layoutFor(884), SaklazLayout.expanded);
  });

  group('A. Sesli konuşma kontrolü', () {
    testWidgets('açılışta mikrofon KAPALI; Başlat ve Durdur ayrı kontroller', (tester) async {
      final f = Fakes();
      await pumpApp(tester, f);
      expect(f.stt.starts, 0);
      expect(find.text('Mikrofon kapalı'), findsOneWidget);
      expect(startBtn, findsOneWidget);
      expect(stopBtn, findsOneWidget);
      expect(tester.widget<OutlinedButton>(stopBtn).onPressed, isNull, reason: 'çalışan bir şey yokken Durdur pasif');
    });

    testWidgets('Başlat mikrofonu açar; Durdur tanımayı tamamen sonlandırır', (tester) async {
      final f = Fakes();
      final c = await pumpApp(tester, f);
      await tester.tap(startBtn);
      await settle(tester);
      expect(f.stt.starts, 1);
      expect(find.text('Mikrofon açık · Dinliyor'), findsOneWidget);
      expect(c.read(conversationProvider).conversationActive, isTrue);

      await tester.tap(stopBtn);
      await settle(tester);
      expect(f.stt.cancels, greaterThanOrEqualTo(1));
      expect(c.read(conversationProvider).conversationActive, isFalse);
      expect(find.text('Mikrofon kapalı'), findsOneWidget);
    });

    testWidgets('konuşma modu: yanıt bitince yeniden dinler', (tester) async {
      final f = Fakes();
      await pumpApp(tester, f);
      await tester.tap(startBtn);
      await settle(tester);
      f.stt.controller.add(const SpeechFinal('saat kaç'));
      await settle(tester);
      expect(f.tts.spoken.single, startsWith('Saat şu an'));
      expect(f.stt.starts, 2, reason: 'TTS bitince tekrar dinlemeli');
      expect(find.text('saat kaç'), findsOneWidget, reason: 'söylenen metin ekranda');
    });

    testWidgets('sesli yanıt dinlemeden bağımsız kapatılabilir ve kalıcıdır', (tester) async {
      final f = Fakes();
      final c = await pumpApp(tester, f);
      await tester.tap(find.text('Sesli yanıt açık'));
      await settle(tester);
      expect(c.read(settingsProvider).voiceReplies, isFalse);
      expect(await f.preferences.readAll(), containsPair('voiceReplies', 'false'));
      await type(tester, 'Merhaba');
      expect(find.text('Merhaba, ben SAKLAZ. Seni dinliyorum.'), findsOneWidget);
      expect(f.tts.spoken, isEmpty);
      expect(f.stt.starts, 0, reason: 'yazılı mesaj mikrofonu açmaz');
    });

    testWidgets('yanıtı tekrar dinletme', (tester) async {
      final f = Fakes(prefs: {'voiceReplies': 'false'});
      await pumpApp(tester, f);
      await type(tester, 'Merhaba');
      await tester.tap(find.byTooltip('Tekrar dinle'));
      await settle(tester);
      expect(f.tts.spoken, ['Merhaba, ben SAKLAZ. Seni dinliyorum.']);
    });

    testWidgets('arka plana geçince mikrofon kapanır', (tester) async {
      final f = Fakes();
      final c = await pumpApp(tester, f);
      await tester.tap(startBtn);
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await settle(tester);
      expect(c.read(conversationProvider).conversationActive, isFalse);
      expect(c.read(conversationProvider).notice, contains('arka plana'));
      expect(f.stt.cancels, greaterThanOrEqualTo(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('art arda sessizlikte konuşma modu kendiliğinden kapanır', (tester) async {
      final f = Fakes();
      final c = await pumpApp(tester, f);
      await tester.tap(startBtn);
      await settle(tester);
      for (var i = 0; i < 3; i++) {
        f.stt.controller.add(const SpeechError(7, 'Konuşma anlaşılamadı'));
        await settle(tester);
      }
      expect(f.stt.starts, 3);
      expect(c.read(conversationProvider).conversationActive, isFalse);
    });

    testWidgets('mikrofon izni yoksa dinleme başlamaz', (tester) async {
      final f = Fakes()..perm.state = MicPermission.denied;
      final c = await pumpApp(tester, f);
      await tester.tap(startBtn);
      await settle(tester);
      expect(f.stt.starts, 0);
      expect(c.read(conversationProvider).conversationActive, isFalse);
      expect(find.text('Mikrofon izni verilmedi.'), findsWidgets);
    });
  });

  group('Fold 7 düzenleri', () {
    testWidgets('katlı: tek sütun', (tester) async {
      await pumpApp(tester, Fakes());
      expect(find.byType(AiOrb), findsOneWidget);
      expect(find.byType(VerticalDivider), findsNothing);
    });
    testWidgets('açık: iki sütun', (tester) async {
      await pumpApp(tester, Fakes(), size: const Size(884, 1000));
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(startBtn, findsOneWidget);
    });
  });

  group('B/C/E. Zekâ, yönlendirme ve hafıza (MOCK gateway)', () {
    testWidgets('hatırla: onay kartı; Kaydet ile hafızaya eklenir', (tester) async {
      final f = Fakes(prefs: {'voiceReplies': 'false'});
      await pumpApp(tester, f);
      await type(tester, 'Hatırla ki doğum günüm 12 Mart');
      expect(find.text('Hafızaya kaydedilsin mi?'), findsOneWidget);
      expect(await f.facts.all(), isEmpty);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Kaydet'));
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await settle(tester);
      expect((await f.facts.all()).single.text, 'doğum günüm 12 Mart');
      await type(tester, 'Doğum günüm ne zamandı?');
      expect(find.textContaining('Kayıtlarıma göre'), findsOneWidget);
    });

    testWidgets('karmaşık soru: OpenAI izni sorulur, onayla gateway çağrılır', (tester) async {
      final f = Fakes(prefs: {...gatewayPrefs, 'voiceReplies': 'false'});
      await pumpApp(tester, f);
      await type(tester, 'Kuantum ve klasik bilgisayarları karşılaştır');
      expect(find.text('OpenAI\'a gönderilsin mi?'), findsOneWidget);
      expect(f.transport.requests, isEmpty, reason: 'izin olmadan gönderilmez');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Gönder'));
      await tester.tap(find.widgetWithText(FilledButton, 'Gönder'));
      await settle(tester);
      expect(f.transport.requests.single.$2.path, '/v1/respond');
      expect(find.text('Bulut yanıtı'), findsOneWidget);
      expect(find.text('OpenAI'), findsOneWidget, reason: 'kaynak etiketi');
    });

    testWidgets('bulut reddedilirse hiçbir şey gönderilmez', (tester) async {
      final f = Fakes(prefs: {...gatewayPrefs, 'voiceReplies': 'false'});
      await pumpApp(tester, f);
      await type(tester, 'Kuantum ve klasik bilgisayarları karşılaştır');
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Gönderme'));
      await tester.tap(find.widgetWithText(TextButton, 'Gönderme'));
      await settle(tester);
      expect(f.transport.requests, isEmpty);
      expect(find.text('Tamam, buluta göndermedim.'), findsOneWidget);
    });

    testWidgets('internet yokken yerel özellikler çalışır, bulut sorusuna açık mesaj', (tester) async {
      final f = Fakes(prefs: {...gatewayPrefs, 'voiceReplies': 'false'});
      f.network.online = false;
      await pumpApp(tester, f);
      await type(tester, 'Saat kaç');
      expect(find.textContaining('Saat şu an'), findsOneWidget);
      await type(tester, 'İstanbul hava durumu nasıl');
      expect(find.textContaining('internet bağlantısı yok'), findsOneWidget);
      expect(f.transport.requests, isEmpty);
    });

    testWidgets('gateway ayarlı değilse anlaşılır mesaj, sahte başarı yok', (tester) async {
      final f = Fakes(prefs: {'voiceReplies': 'false'});
      await pumpApp(tester, f);
      await type(tester, 'Bunu analiz et ve karşılaştır');
      expect(find.textContaining('Gateway henüz ayarlanmadı'), findsOneWidget);
    });

    testWidgets('yerel model hazırsa basit genel soru cihazda yanıtlanır', (tester) async {
      final f = Fakes(prefs: {'voiceReplies': 'false'});
      f.localLlm.ready = true;
      await pumpApp(tester, f);
      await type(tester, 'Bana bir fıkra anlat');
      expect(find.text('yerel model yanıtı'), findsOneWidget);
      expect(find.text('Yerel AI'), findsOneWidget);
    });

    testWidgets('konuşma geçmişi depoya yazılır', (tester) async {
      final f = Fakes(prefs: {'voiceReplies': 'false'});
      await pumpApp(tester, f);
      await type(tester, 'Merhaba');
      expect((await f.conversations.all()).map((m) => m.text), ['Merhaba', 'Merhaba, ben SAKLAZ. Seni dinliyorum.']);
    });
  });

  group('Asistan rolü (Phase 1 davranışı korunur)', () {
    testWidgets('rol yoksa uyarı rozeti; izin ekranı sistem durumunu gösterir', (tester) async {
      final f = Fakes();
      await pumpApp(tester, f);
      await tester.tap(find.byTooltip('SAKLAZ henüz varsayılan asistan değil'));
      await settle(tester);
      expect(find.text('SAKLAZ varsayılan asistan değil'), findsOneWidget);
      await tester.tap(find.text('Varsayılan asistan yap'));
      await settle(tester);
      expect(f.platform.requests, 1);
      expect(f.platform.settingsOpened, 1);
    });

    testWidgets('yan tuş çağrısı: varsayılan ayarda mikrofon AÇILMAZ', (tester) async {
      final f = Fakes()..platform.pending = AssistInvocation(AssistSource.voiceInteractionSession, DateTime(2026));
      await pumpApp(tester, f);
      await settle(tester);
      expect(f.stt.starts, 0);
    });

    testWidgets('yan tuş çağrısı: ayar açıksa konuşma başlar', (tester) async {
      final f = Fakes(prefs: {'listenOnAssistInvoke': 'true'})
        ..platform.pending = AssistInvocation(AssistSource.voiceInteractionSession, DateTime(2026));
      await pumpApp(tester, f);
      await settle(tester);
      expect(f.stt.starts, 1);
    });
  });

  testWidgets('hafıza ekranı şifreleme durumunu ve kayıtları gösterir, silme onaylıdır', (tester) async {
    final f = Fakes();
    await f.facts.add('En sevdiğim renk lacivert');
    final c = await pumpApp(tester, f);
    expect(c.read(memoryProvider).encrypted, isTrue);
    await tester.tap(find.byTooltip('Hafıza'));
    await settle(tester);
    expect(find.text('Şifreli ve yalnızca bu cihazda'), findsOneWidget);
    expect(find.text('En sevdiğim renk lacivert'), findsOneWidget);
    await tester.tap(find.byTooltip('Sil'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await settle(tester);
    expect(await f.facts.all(), isEmpty);
  });
}
