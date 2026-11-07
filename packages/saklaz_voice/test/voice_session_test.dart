// Test sahteleri (fake) test süresince yaşar; kapatılmaları gerekmez.
// ignore_for_file: close_sinks
import 'dart:async';

import 'package:saklaz_core/saklaz_core.dart';
import 'package:saklaz_voice/saklaz_voice.dart';
import 'package:test/test.dart';

class FakeStt implements SpeechRecognizerPort {
  final controller = StreamController<SpeechEvent>.broadcast(sync: true);
  int starts = 0;
  int cancels = 0;
  bool throwOnStart = false;

  @override
  Stream<SpeechEvent> get events => controller.stream;
  @override
  Future<SpeechEngineInfo> engineInfo() async =>
      const SpeechEngineInfo(available: true, onDevice: true);
  @override
  Future<void> start({required String localeTag, required bool preferOnDevice}) async {
    if (throwOnStart) throw StateError('yok');
    starts++;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async => cancels++;
}

class FakeTts implements SpeechSynthesizerPort {
  final controller = StreamController<TtsEvent>.broadcast(sync: true);
  final spoken = <String>[];
  int stops = 0;
  bool ready = true;

  @override
  Stream<TtsEvent> get events => controller.stream;
  @override
  Future<TtsInitResult> initialize(String localeTag) async =>
      TtsInitResult(ready: ready, languageSupported: ready);
  @override
  Future<void> speak(String id, String text, {required double rate, required double pitch}) async {
    spoken.add('$id:$text');
  }

  @override
  Future<void> stop() async => stops++;
}

class FakePerm implements MicrophonePermissionPort {
  FakePerm(this.state, {this.afterRequest});
  MicPermission state;
  MicPermission? afterRequest;
  int requests = 0;

  @override
  Future<MicPermission> current() async => state;
  @override
  Future<MicPermission> request() async {
    requests++;
    state = afterRequest ?? state;
    return state;
  }

  @override
  Future<void> openAppSettings() async {}
}

void main() {
  late FakeStt stt;
  late FakeTts tts;

  VoiceSession make(FakePerm perm) => VoiceSession(
        recognizer: stt,
        synthesizer: tts,
        permission: perm,
        logger: MemoryLogger(),
      );

  setUp(() {
    stt = FakeStt();
    tts = FakeTts();
  });

  test('izin yoksa ister; reddedilirse mikrofon açılmaz', () async {
    final perm = FakePerm(MicPermission.denied, afterRequest: MicPermission.denied);
    final s = make(perm);
    final r = await s.startListening();
    expect(r.isOk, isFalse);
    expect(perm.requests, 1);
    expect(stt.starts, 0);
    expect(s.state.micActive, isFalse);
    expect(s.state.errorMessage, isNotNull);
  });

  test('izin verilirse dinlemeye geçer ve final metni yayınlar', () async {
    final s = make(FakePerm(MicPermission.denied, afterRequest: MicPermission.granted));
    final texts = <String>[];
    s.transcripts.listen(texts.add);

    expect((await s.startListening()).isOk, isTrue);
    expect(s.state.phase, VoicePhase.listening);
    expect(stt.starts, 1);

    stt.controller.add(const SpeechLevel(10));
    expect(s.state.level, 1.0);
    stt.controller.add(const SpeechPartial('merhaba'));
    expect(s.state.partialText, 'merhaba');
    stt.controller.add(const SpeechFinal(' merhaba saklaz '));
    await Future<void>.delayed(Duration.zero);

    expect(s.state.phase, VoicePhase.idle);
    expect(texts, ['merhaba saklaz']);
  });

  test('STT hatasında mikrofon kapanır ve hata gösterilir', () async {
    final s = make(FakePerm(MicPermission.granted));
    await s.startListening();
    stt.controller.add(const SpeechError(7, 'Konuşma anlaşılamadı'));
    expect(s.state.phase, VoicePhase.idle);
    expect(s.state.errorMessage, 'Konuşma anlaşılamadı');
  });

  test('başlatma istisnası hata sonucuna dönüşür', () async {
    stt.throwOnStart = true;
    final s = make(FakePerm(MicPermission.granted));
    final r = await s.startListening();
    expect(r.failureOrNull?.code, 'stt-start');
    expect(s.state.micActive, isFalse);
  });

  test('konuşurken dinleme başlatılırsa önce konuşma durur', () async {
    final s = make(FakePerm(MicPermission.granted));
    await s.speak('Merhaba');
    expect(s.state.phase, VoicePhase.speaking);
    await s.startListening();
    expect(tts.stops, 1);
    expect(s.state.phase, VoicePhase.listening);
  });

  test('TTS bitince idle durumuna döner; eski utterance olayları yok sayılır', () async {
    final s = make(FakePerm(MicPermission.granted));
    await s.speak('bir');
    tts.controller.add(const TtsEvent(TtsEventKind.done, 'eski'));
    expect(s.state.phase, VoicePhase.speaking);
    tts.controller.add(const TtsEvent(TtsEventKind.done, 'u1'));
    expect(s.state.phase, VoicePhase.idle);
    expect(tts.spoken, ['u1:bir']);
  });

  test('TTS hazır değilse konuşma atlanır', () async {
    tts.ready = false;
    final s = make(FakePerm(MicPermission.granted));
    await s.speak('x');
    expect(tts.spoken, isEmpty);
    expect(s.state.errorMessage, isNotNull);
  });

  test('speakToEnd konuşma bitene kadar bekler', () async {
    final s = make(FakePerm(MicPermission.granted));
    var finished = false;
    final f = s.speakToEnd('uzun cümle').then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(s.isSpeaking, isTrue);
    tts.controller.add(const TtsEvent(TtsEventKind.done, 'u1'));
    await f;
    expect(finished, isTrue);
    expect(s.isSpeaking, isFalse);
  });

  test('stopSpeaking bekleyen speakToEnd çağrısını serbest bırakır', () async {
    final s = make(FakePerm(MicPermission.granted));
    final f = s.speakToEnd('x');
    await Future<void>.delayed(Duration.zero);
    await s.stopSpeaking();
    await f; // askıda kalmamalı
    expect(s.state.phase, VoicePhase.idle);
  });

  test('STT hataları kodlarıyla errors akışında yayınlanır', () async {
    final s = make(FakePerm(MicPermission.granted));
    final codes = <int>[];
    s.errors.listen((e) => codes.add(e.code));
    await s.startListening();
    stt.controller.add(const SpeechError(6, 'Konuşma algılanmadı'));
    await Future<void>.delayed(Duration.zero);
    expect(codes, [6]);
  });

  test('normalizeRms sınırları', () {
    expect(VoiceSession.normalizeRms(-10), 0);
    expect(VoiceSession.normalizeRms(4), 0.5);
    expect(VoiceSession.normalizeRms(50), 1);
  });
}
