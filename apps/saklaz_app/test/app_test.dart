import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_app/application/conversation_controller.dart';
import 'package:saklaz_app/application/settings_controller.dart';
import 'package:saklaz_app/presentation/layout/breakpoints.dart';
import 'package:saklaz_app/presentation/saklaz_app.dart';
import 'package:saklaz_app/presentation/widgets/ai_orb.dart';
import 'package:saklaz_memory/saklaz_memory.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import 'fakes.dart';

Future<ProviderContainer> pumpApp(WidgetTester tester, Fakes f, {Size size = const Size(412, 1100)}) async {
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
  await tester.enterText(find.byType(TextField).last, text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await settle(tester);
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await settle(tester);
}

void main() {
  test('Fold 7 kırılma noktaları', () {
    expect(layoutFor(412), SaklazLayout.compact);
    expect(layoutFor(884), SaklazLayout.expanded);
  });

  group('Varsayılanlar ve gizlilik', () {
    testWidgets('ilk açılış: mikrofon kapalı, tamamen yerel, bulut pasif', (tester) async {
      final f = Fakes();
      final c = await pumpApp(tester, f);
      expect(f.stt.starts, 0);
      expect(find.text('Mikrofon kapalı'), findsOneWidget);
      expect(find.text('Tamamen yerel'), findsOneWidget);
      expect(c.read(settingsProvider).activeProvider, isNull);
      for (final k in ProviderKind.values) {
        expect(c.read(settingsProvider).provider(k).enabled, isFalse);
      }
    });

    testWidgets('model yokken anlaşılır mesaj; HİÇBİR ağ isteği yapılmaz', (tester) async {
      final f = Fakes(prefs: {'voiceReplies': 'false'});
      await pumpApp(tester, f);
      expect(find.text('Model indirilmedi'), findsOneWidget);
      await type(tester, 'Kuantum ve klasik bilgisayarları karşılaştır');
      expect(find.textContaining('Model Yönetimi'), findsOneWidget);
      expect(f.transport.requests, isEmpty);
    });

    testWidgets('yerel model hazır: genel soru yerelde yanıtlanır', (tester) async {
      final f = Fakes(prefs: {'voiceReplies': 'false'});
      f.localLlm.ready = true;
      await pumpApp(tester, f);
      expect(find.text('Yerel AI hazır'), findsOneWidget);
      await type(tester, 'Bana bir fıkra anlat');
      expect(find.text('yerel model yanıtı'), findsOneWidget);
      expect(find.text('Yerel AI'), findsOneWidget);
      expect(f.transport.requests, isEmpty);
    });
  });

  group('Otomatik kişisel öğrenme', () {
    testWidgets('istenen senaryo: öğren, sonra hafızadan yanıtla', (tester) async {
      final f = Fakes(prefs: {'voiceReplies': 'false'});
      f.localLlm.ready = true;
      await pumpApp(tester, f);
      await type(tester, 'Ben satınalma yöneticisiyim ve ASEDEN ERP üzerinde çalışıyorum.');
      expect(find.textContaining('Hafızama ekledim'), findsOneWidget);
      expect((await f.facts.all()).map((x) => x.text), containsAll(['satınalma yöneticisi', 'ASEDEN ERP']));
      await type(tester, 'Ben hangi projeler üzerinde çalışıyorum?');
      expect(find.text('Proje: ASEDEN ERP.'), findsOneWidget);
      await type(tester, 'Benim hakkımda ne biliyorsun?');
      expect(find.textContaining('Senin hakkında bildiklerim'), findsOneWidget);
    });

    testWidgets('Benim Hafızam: arama, düzenleme, silme, otomatik öğrenme anahtarı', (tester) async {
      final f = Fakes();
      await f.facts.upsert(FactCategory.project, 'ASEDEN ERP', source: FactSource.auto);
      await f.facts.upsert(FactCategory.interest, 'satranç');
      final c = await pumpApp(tester, f);
      await tester.tap(find.byTooltip('Benim Hafızam'));
      await settle(tester);
      expect(find.text('ASEDEN ERP'), findsOneWidget);
      expect(find.textContaining('otomatik öğrenildi'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'satranç');
      await settle(tester);
      expect(find.text('ASEDEN ERP'), findsNothing);
      expect(find.widgetWithText(ListTile, 'satranç'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '');
      await settle(tester);

      await tapVisible(tester, find.byTooltip('Düzenle').first);
      await tester.enterText(find.byType(TextField).last, 'ASEDEN ERP v2');
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await settle(tester);
      expect((await f.facts.all()).map((x) => x.text), contains('ASEDEN ERP v2'));

      await tapVisible(tester, find.byTooltip('Sil').first);
      await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
      await settle(tester);
      expect(await f.facts.all(), hasLength(1));

      await tapVisible(tester, find.text('Otomatik öğrenme'));
      expect(c.read(settingsProvider).autoLearn, isFalse);
    });
  });

  group('Agent (onaylı telefon işlemleri)', () {
    testWidgets('hatırlatıcı: kart çıkar, sesli "evet" ile onaylanır', (tester) async {
      final f = Fakes(prefs: {'autoConfirmMedium': 'false'});
      await pumpApp(tester, f);
      await tester.tap(startBtn);
      await settle(tester);
      f.stt.controller.add(const SpeechFinal("yarın sabah 9'da toplantıyı hatırlat"));
      await settle(tester);
      expect(find.text('Onaylıyor musun?'), findsOneWidget);
      expect(await f.reminders.all(), isEmpty);
      f.stt.controller.add(const SpeechFinal('evet'));
      await settle(tester);
      expect((await f.reminders.all()).single.text, 'toplantıyı');
      expect(f.device.calls.single, 'rem:toplantıyı');
    });

    testWidgets('WhatsApp yüksek risk: sesli "evet" GEÇERSİZ, ekrandan onay gerekir', (tester) async {
      final f = Fakes(prefs: {'voiceReplies': 'false'});
      final c = await pumpApp(tester, f);
      await type(tester, "Ahmet'e WhatsApp'tan geç kalacağımı yaz");
      expect(find.text('Onay gerekli (yalnızca ekrandan)'), findsOneWidget);
      await c.read(conversationProvider.notifier).submitText('evet', fromVoice: true);
      await settle(tester);
      expect(f.device.calls, isEmpty);
      expect(find.textContaining('ekrandaki'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Onayla'));
      expect(f.device.calls.single, 'wa:05321112233:geç kalacağım');
    });
  });

  group('Bulut sağlayıcı (yalnızca kullanıcı etkinleştirirse, MOCK)', () {
    testWidgets('etkin + aktif: izin kartı; onayla gönderilir, reddedince gönderilmez', (tester) async {
      final f = Fakes(prefs: {...cloudPrefs(), 'voiceReplies': 'false'});
      await f.secrets.put(ProviderKind.deepseek.secretName, 'sk-test');
      await pumpApp(tester, f);
      expect(find.text('Bulut: DeepSeek'), findsOneWidget);
      await type(tester, 'Kuantum ve klasik bilgisayarları karşılaştır');
      expect(find.text('Bulut sağlayıcısına gönderilsin mi?'), findsOneWidget);
      expect(f.transport.requests, isEmpty);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Gönder'));
      expect(f.transport.requests.single.$2.toString(), 'https://api.deepseek.com/chat/completions');
      expect(find.text('Bulut yanıtı'), findsOneWidget);

      await type(tester, 'Bunu da analiz et ve karşılaştır');
      await tapVisible(tester, find.widgetWithText(TextButton, 'Gönderme'));
      expect(f.transport.requests, hasLength(1));
    });

    testWidgets('anahtar yoksa etkin olsa bile bulut kullanılmaz', (tester) async {
      final f = Fakes(prefs: {...cloudPrefs(), 'voiceReplies': 'false'});
      await pumpApp(tester, f);
      await type(tester, 'Kuantum ve klasik bilgisayarları karşılaştır');
      expect(f.transport.requests, isEmpty);
      expect(find.text('Bulut sağlayıcısına gönderilsin mi?'), findsNothing);
    });
  });

  group('Ses (Phase 2 davranışı korunur)', () {
    testWidgets('Başlat / Durdur ve konuşma döngüsü', (tester) async {
      final f = Fakes();
      final c = await pumpApp(tester, f);
      await tester.tap(startBtn);
      await settle(tester);
      expect(find.text('Mikrofon açık · Dinliyor'), findsOneWidget);
      f.stt.controller.add(const SpeechFinal('saat kaç'));
      await settle(tester);
      expect(f.tts.spoken.single, startsWith('Saat şu an'));
      expect(f.stt.starts, 2);
      await tester.tap(stopBtn);
      await settle(tester);
      expect(c.read(conversationProvider).conversationActive, isFalse);
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
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('izin yoksa mikrofon açılmaz', (tester) async {
      final f = Fakes()..perm.state = MicPermission.denied;
      await pumpApp(tester, f);
      await tester.tap(startBtn);
      await settle(tester);
      expect(f.stt.starts, 0);
    });

    testWidgets('yan tuş: varsayılan ayarda mikrofon AÇILMAZ', (tester) async {
      final f = Fakes()..platform.pending = AssistInvocation(AssistSource.voiceInteractionSession, DateTime(2026));
      await pumpApp(tester, f);
      expect(f.stt.starts, 0);
    });
  });

  group('Ekranlar ve düzenler', () {
    testWidgets('katlı tek sütun, açık iki sütun', (tester) async {
      await pumpApp(tester, Fakes());
      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.byType(AiOrb), findsOneWidget);
    });

    testWidgets('açık ekran', (tester) async {
      await pumpApp(tester, Fakes(), size: const Size(884, 1000));
      expect(find.byType(VerticalDivider), findsOneWidget);
    });

    testWidgets('Model Yönetimi: katalog, lisans ve onaylı indirme', (tester) async {
      final f = Fakes();
      await pumpApp(tester, f);
      await tester.tap(find.text('Model indirilmedi'));
      await settle(tester);
      expect(find.text('Qwen3 1.7B (önerilen)'), findsOneWidget);
      expect(find.textContaining('Apache-2.0'), findsWidgets);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'İndir').first);
      expect(find.text('Qwen3 1.7B (önerilen) indirilsin mi?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'İndir').last);
      await settle(tester);
      expect(f.models.downloads, ['qwen3-1.7b-int4']);
    });

    testWidgets('Ayarlar merkezinden tüm ekranlar açılır', (tester) async {
      await pumpApp(tester, Fakes(), size: const Size(884, 1400));
      await tester.tap(find.byTooltip('Ayarlar'));
      await settle(tester);
      expect(find.text('Benim Hafızam'), findsOneWidget);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      for (final (route, title) in [
        ('/ai-settings', 'Yapay Zekâ Ayarları'),
        ('/providers', 'API Sağlayıcıları'),
        ('/models', 'Model Yönetimi'),
        ('/memory', 'Benim Hafızam'),
        ('/history', 'Sohbet Geçmişi'),
        ('/notes', 'Notlar ve Hatırlatmalar'),
        ('/permissions', 'Asistan izinleri'),
      ]) {
        unawaited(nav.pushNamed(route));
        await settle(tester);
        expect(find.text(title), findsWidgets, reason: route);
        expect(tester.takeException(), isNull, reason: route);
        nav.pop();
        await settle(tester);
      }
    });
  });
}
