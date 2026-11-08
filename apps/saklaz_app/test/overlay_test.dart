import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_app/infrastructure/providers.dart';
import 'package:saklaz_app/presentation/overlay/assist_overlay.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import 'fakes.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpOverlay(WidgetTester tester, Fakes f) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  f.platform.pending = AssistInvocation(AssistSource.voiceInteractionSession, DateTime.now());
  await tester.pumpWidget(ProviderScope(
    overrides: [...f.overrides, isOverlayProvider.overrideWithValue(true)],
    child: const AssistOverlayApp(),
  ));
  await settle(tester);
}

void main() {
  testWidgets('yan tuş paneli: uygulama açılmadan hemen dinler ve yanıtlar', (tester) async {
    final f = Fakes();
    await pumpOverlay(tester, f);
    expect(f.stt.starts, 1, reason: 'panel açılır açılmaz dinlemeli');
    expect(find.text('Mikrofon açık · Dinliyor'), findsOneWidget);
    f.stt.controller.add(const SpeechFinal('saat kaç'));
    await settle(tester);
    expect(find.textContaining('Saat şu an'), findsOneWidget);
    expect(f.tts.spoken.single, startsWith('Saat şu an'));
    expect(f.stt.starts, 2, reason: 'yanıttan sonra dinlemeye devam');
  });

  testWidgets('söylediğimi yap: hatırlatma sormadan kurulur', (tester) async {
    final f = Fakes();
    await pumpOverlay(tester, f);
    f.stt.controller.add(const SpeechFinal("10 dakika sonra ilacımı hatırlat"));
    await settle(tester);
    expect((await f.reminders.all()).single.text, 'ilacımı');
    expect(find.text('Onaylıyor musun?'), findsNothing);
  });

  testWidgets('WhatsApp yine ekrandan onay ister; onaylayınca panel kapanır', (tester) async {
    final f = Fakes();
    await pumpOverlay(tester, f);
    f.stt.controller.add(const SpeechFinal("Ahmet'e WhatsApp'tan geç kalacağımı yaz"));
    await settle(tester);
    expect(f.device.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 400)); // otomatik kaydırma bitsin
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Onayla'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilledButton, 'Onayla'));
    await settle(tester);
    expect(f.device.calls.single, startsWith('wa:'));
    expect(f.session.dismissed, 1, reason: 'WhatsApp açılınca panel kapanır');
  });

  testWidgets('dışarı dokununca panel kapanır, mikrofon durur', (tester) async {
    final f = Fakes();
    await pumpOverlay(tester, f);
    await tester.tapAt(const Offset(200, 40));
    await settle(tester);
    expect(f.session.dismissed, 1);
    expect(f.stt.cancels, greaterThanOrEqualTo(1));
  });

  testWidgets('mikrofon izni yoksa açıklama gösterir', (tester) async {
    final f = Fakes()..perm.state = MicPermission.denied;
    await pumpOverlay(tester, f);
    expect(f.stt.starts, 0);
    expect(find.textContaining('Mikrofon izni yok'), findsOneWidget);
  });
}
