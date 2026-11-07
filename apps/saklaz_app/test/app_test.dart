import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_app/application/conversation_controller.dart';
import 'package:saklaz_app/presentation/layout/breakpoints.dart';
import 'package:saklaz_app/presentation/saklaz_app.dart';
import 'package:saklaz_app/presentation/widgets/ai_orb.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import 'fakes.dart';

Future<void> pumpApp(WidgetTester tester, Fakes f, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: f.overrides, child: const SaklazApp()));
  await tester.pump();
}

void main() {
  test('Fold 7 kırılma noktaları', () {
    expect(layoutFor(412), SaklazLayout.compact); // dış ekran
    expect(layoutFor(700), SaklazLayout.medium);
    expect(layoutFor(884), SaklazLayout.expanded); // iç ekran
  });

  testWidgets('katlı ekranda tek sütun: küre, mikrofon, geçmiş', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, const Size(412, 915));
    expect(find.byType(AiOrb), findsOneWidget);
    expect(find.text('Mikrofon kapalı'), findsOneWidget);
    expect(find.text('Henüz konuşma yok.\nMikrofona dokun veya yaz.'), findsOneWidget);
    expect(find.byType(VerticalDivider), findsNothing);
  });

  testWidgets('açık ekranda iki sütun', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, const Size(884, 1000));
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.byType(AiOrb), findsOneWidget);
  });

  testWidgets('mikrofon düğmesi dinlemeyi başlatır ve durum görünür', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, const Size(412, 915));
    await tester.tap(find.byTooltip('Konuşmaya başla'));
    await tester.pump();
    expect(f.stt.starts, 1);
    expect(find.text('Dinliyor'), findsOneWidget);
  });

  testWidgets('yazılı mesaj geçmişe eklenir ve sesli yanıt verilir', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, const Size(412, 915));
    await tester.enterText(find.byType(TextField), 'Merhaba');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump();
    expect(find.text('Merhaba'), findsOneWidget);
    expect(find.text('Merhaba, ben SAKLAZ. Seni dinliyorum.'), findsOneWidget);
    expect(f.tts.spoken, ['Merhaba, ben SAKLAZ. Seni dinliyorum.']);
  });

  testWidgets('rol yoksa uyarı rozeti; izin ekranı sistem durumunu gösterir', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, const Size(412, 915));
    expect(find.byTooltip('SAKLAZ henüz varsayılan asistan değil'), findsOneWidget);
    await tester.tap(find.byTooltip('Asistan izinleri'));
    // Küre animasyonu sürekli döndüğü için pumpAndSettle yerine sabit kareler.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('SAKLAZ varsayılan asistan değil'), findsOneWidget);
    await tester.tap(find.text('Varsayılan asistan yap'));
    await tester.pump();
    await tester.pump();
    expect(f.platform.requests, 1);
    expect(f.platform.settingsOpened, 1);
  });

  testWidgets('soğuk açılışta yan tuş çağrısı dinlemeyi başlatır', (tester) async {
    final f = Fakes()
      ..platform.pending = AssistInvocation(AssistSource.voiceInteractionSession, DateTime(2026));
    await pumpApp(tester, f, const Size(412, 915));
    await tester.pump();
    expect(f.stt.starts, 1);
  });

  test('izin yoksa mikrofon açılmaz', () async {
    final f = Fakes()..perm.state = MicPermission.denied;
    final c = ProviderContainer(overrides: f.overrides);
    addTearDown(c.dispose);
    c.read(conversationProvider);
    await c.read(conversationProvider.notifier).startListening();
    await Future<void>.delayed(Duration.zero); // durum yayını asenkron
    expect(f.stt.starts, 0);
    expect(c.read(conversationProvider).voice.errorMessage, isNotNull);
  });
}
