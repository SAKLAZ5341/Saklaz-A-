import 'dart:async';

import 'package:saklaz_core/saklaz_core.dart';

import 'ports.dart';
import 'voice_state.dart';

/// Platformdan bağımsız ses oturumu durum makinesi.
///
/// Kurallar:
///  * Mikrofon yalnızca [startListening] ile açılır (kullanıcı eylemi).
///  * Konuşurken dinleme başlatılırsa önce konuşma durdurulur.
///  * Hata olursa mikrofon kapatılır ve [VoicePhase.idle]'a dönülür.
class VoiceSession {
  VoiceSession({
    required SpeechRecognizerPort recognizer,
    required SpeechSynthesizerPort synthesizer,
    required MicrophonePermissionPort permission,
    required AppLogger logger,
    this.localeTag = 'tr-TR',
  })  : _stt = recognizer,
        _tts = synthesizer,
        _perm = permission,
        _log = logger {
    _sttSub = _stt.events.listen(_onSpeech);
    _ttsSub = _tts.events.listen(_onTts);
  }

  static const _tag = 'VoiceSession';

  final SpeechRecognizerPort _stt;
  final SpeechSynthesizerPort _tts;
  final MicrophonePermissionPort _perm;
  final AppLogger _log;
  final String localeTag;

  late final StreamSubscription<SpeechEvent> _sttSub;
  late final StreamSubscription<TtsEvent> _ttsSub;

  final _states = StreamController<VoiceState>.broadcast();
  final _transcripts = StreamController<String>.broadcast();

  VoiceState _state = const VoiceState();
  TtsInitResult? _ttsInit;
  int _utteranceSeq = 0;
  String? _currentUtterance;

  VoiceState get state => _state;
  Stream<VoiceState> get states => _states.stream;

  /// Kullanıcının söylediği nihai (final) metinler.
  Stream<String> get transcripts => _transcripts.stream;

  TtsInitResult? get ttsInfo => _ttsInit;

  void _emit(VoiceState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  Future<TtsInitResult> initTts() async {
    final r = await _tts.initialize(localeTag);
    _ttsInit = r;
    _log.i(_tag, 'TTS hazır=${r.ready} dilDestekli=${r.languageSupported}');
    return r;
  }

  /// Mikrofonu açar. İzin yoksa ister; reddedilirse hata durumuna geçer.
  Future<Result<void>> startListening({bool preferOnDevice = true}) async {
    if (_state.phase == VoicePhase.listening) return const Result.ok(null);
    if (_state.phase == VoicePhase.speaking) await stopSpeaking();

    var perm = await _perm.current();
    if (perm != MicPermission.granted) {
      _emit(_state.copyWith(phase: VoicePhase.requestingPermission, clearError: true));
      perm = await _perm.request();
    }
    if (perm != MicPermission.granted) {
      const f = Failure('mic-permission', 'Mikrofon izni verilmedi.');
      _emit(const VoiceState(errorMessage: 'Mikrofon izni verilmedi.'));
      _log.w(_tag, 'Mikrofon izni yok: ${perm.name}');
      return const Result.err(f);
    }

    _emit(const VoiceState(phase: VoicePhase.listening));
    try {
      await _stt.start(localeTag: localeTag, preferOnDevice: preferOnDevice);
      _log.i(_tag, 'Dinleme başladı');
      return const Result.ok(null);
    } on Object catch (e) {
      _log.e(_tag, 'Dinleme başlatılamadı', error: e);
      _emit(const VoiceState(errorMessage: 'Dinleme başlatılamadı.'));
      return Result.err(Failure('stt-start', 'Dinleme başlatılamadı.', cause: e));
    }
  }

  Future<void> stopListening() async {
    if (_state.phase != VoicePhase.listening) return;
    await _stt.stop();
  }

  Future<void> cancelListening() async {
    await _stt.cancel();
    if (_state.phase == VoicePhase.listening ||
        _state.phase == VoicePhase.requestingPermission) {
      _emit(const VoiceState());
    }
  }

  /// Yanıt hazırlanırken çağrılır (görsel "düşünüyor" durumu).
  void markThinking() => _emit(const VoiceState(phase: VoicePhase.thinking));

  void markIdle() => _emit(const VoiceState());

  Future<void> speak(String text, {double rate = 1.0, double pitch = 1.0}) async {
    final init = _ttsInit ?? await initTts();
    if (!init.ready) {
      _log.w(_tag, 'TTS hazır değil, sesli yanıt atlandı');
      _emit(const VoiceState(errorMessage: 'Sesli yanıt motoru hazır değil.'));
      return;
    }
    final id = 'u${++_utteranceSeq}';
    _currentUtterance = id;
    _emit(const VoiceState(phase: VoicePhase.speaking));
    await _tts.speak(id, text, rate: rate, pitch: pitch);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    _currentUtterance = null;
    if (_state.phase == VoicePhase.speaking) _emit(const VoiceState());
  }

  void _onSpeech(SpeechEvent e) {
    switch (e) {
      case SpeechReady() || SpeechBegan():
        break;
      case SpeechLevel(:final rmsDb):
        if (_state.phase == VoicePhase.listening) {
          _emit(_state.copyWith(level: normalizeRms(rmsDb)));
        }
      case SpeechPartial(:final text):
        _emit(_state.copyWith(partialText: text));
      case SpeechFinal(:final text):
        _emit(const VoiceState());
        final t = text.trim();
        if (t.isNotEmpty) _transcripts.add(t);
      case SpeechEnded():
        if (_state.phase == VoicePhase.listening) {
          _emit(_state.copyWith(level: 0));
        }
      case SpeechError(:final code, :final message):
        _log.w(_tag, 'STT hatası $code: $message');
        _emit(VoiceState(errorMessage: message));
    }
  }

  void _onTts(TtsEvent e) {
    if (e.utteranceId != _currentUtterance) return;
    switch (e.kind) {
      case TtsEventKind.started:
        break;
      case TtsEventKind.done || TtsEventKind.stopped:
        _currentUtterance = null;
        if (_state.phase == VoicePhase.speaking) _emit(const VoiceState());
      case TtsEventKind.error:
        _currentUtterance = null;
        _emit(const VoiceState(errorMessage: 'Sesli yanıt oynatılamadı.'));
    }
  }

  /// Android RMS dB değerini (yaklaşık -2..10) 0..1 aralığına çevirir.
  static double normalizeRms(double rmsDb) =>
      ((rmsDb + 2) / 12).clamp(0.0, 1.0).toDouble();

  Future<void> dispose() async {
    await _stt.cancel();
    await _tts.stop();
    await _sttSub.cancel();
    await _ttsSub.cancel();
    await _states.close();
    await _transcripts.close();
  }
}
