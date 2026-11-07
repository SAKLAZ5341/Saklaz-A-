import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_core/saklaz_core.dart';

import '../infrastructure/providers.dart';

/// Yerel model (Gemini Nano) durumu. Modeli asla kendiliğinden indirmez.
class LocalAiController extends AsyncNotifier<LocalLlmInfo> {
  @override
  Future<LocalLlmInfo> build() => _safeInfo();

  Future<LocalLlmInfo> _safeInfo() async {
    try {
      return await ref.read(localLlmProvider).info();
    } on Object catch (e) {
      ref.read(loggerProvider).w('LocalAi', 'Yerel model durumu okunamadı', error: e);
      return const LocalLlmInfo(LocalLlmState.unavailable, detail: 'Durum okunamadı');
    }
  }

  Future<void> refresh() async => state = AsyncData(await _safeInfo());

  /// Yalnızca kullanıcı onayından sonra çağrılır.
  Future<void> download() async {
    state = const AsyncData(LocalLlmInfo(LocalLlmState.downloading));
    try {
      state = AsyncData(await ref.read(localLlmProvider).download());
    } on Object catch (e) {
      state = AsyncData(LocalLlmInfo(LocalLlmState.error, detail: '$e'));
    }
  }
}

final localAiProvider = AsyncNotifierProvider<LocalAiController, LocalLlmInfo>(LocalAiController.new);
