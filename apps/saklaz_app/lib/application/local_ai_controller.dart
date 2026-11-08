import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_core/saklaz_core.dart';

import '../infrastructure/providers.dart';
import 'model_catalog.dart';
import 'settings_controller.dart';

class LocalAiState {
  const LocalAiState({
    this.installed = const {},
    this.downloads = const {},
    this.llm = const LocalLlmInfo(LocalLlmState.noModel),
    this.capability,
  });

  /// Kurulu model dosya adları.
  final Set<String> installed;
  final Map<String, DownloadStatus> downloads;
  final LocalLlmInfo llm;
  final DeviceCapability? capability;

  bool isInstalled(ModelSpec m) => installed.contains(m.fileName);
  bool get ready => llm.state == LocalLlmState.ready;

  LocalAiState copyWith({Set<String>? installed, Map<String, DownloadStatus>? downloads, LocalLlmInfo? llm, DeviceCapability? capability}) =>
      LocalAiState(
        installed: installed ?? this.installed,
        downloads: downloads ?? this.downloads,
        llm: llm ?? this.llm,
        capability: capability ?? this.capability,
      );
}

/// Model indirme, doğrulama, yükleme ve bellek yönetimi.
/// Açılışta seçili model kuruluysa otomatik yüklenir (ağ GEREKMEZ).
class LocalAiController extends Notifier<LocalAiState> {
  static const _tag = 'LocalAi';
  StreamSubscription<(String, DownloadStatus)>? _sub;

  ModelManager get _mm => ref.read(modelManagerProvider);

  @override
  LocalAiState build() {
    _sub = _mm.progress.listen(_onProgress);
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(_init);
    return const LocalAiState();
  }

  Future<void> _init() async {
    await refresh();
    final spec = modelById(ref.read(settingsProvider).activeModelId);
    if (spec != null && state.isInstalled(spec)) await load(spec);
  }

  Future<void> refresh() async {
    try {
      final installed = await _mm.installedFiles();
      final cap = await _mm.capability();
      final llm = ref.read(localLlmProvider);
      if (llm is AndroidLocalLlm) llm.noModelInstalled = installed.isEmpty;
      state = state.copyWith(installed: installed, capability: cap, llm: await llm.info());
    } on Object catch (e) {
      ref.read(loggerProvider).w(_tag, 'Model durumu okunamadı', error: e);
    }
  }

  Future<void> download(ModelSpec spec) async {
    state = state.copyWith(downloads: {...state.downloads, spec.id: DownloadStatus(DownloadPhase.running, total: spec.sizeBytes)});
    try {
      await _mm.download(spec);
    } on Object catch (e) {
      state = state.copyWith(downloads: {...state.downloads, spec.id: DownloadStatus(DownloadPhase.failed, error: '$e')});
    }
  }

  Future<void> cancel(ModelSpec spec) => _mm.cancel(spec.id);

  Future<void> delete(ModelSpec spec) async {
    final llm = ref.read(localLlmProvider);
    if (state.llm.modelName == spec.fileName && llm is AndroidLocalLlm) await llm.unload();
    await _mm.delete(spec);
    await refresh();
  }

  Future<void> load(ModelSpec spec) async {
    final llm = ref.read(localLlmProvider);
    if (llm is! AndroidLocalLlm) return;
    state = state.copyWith(llm: LocalLlmInfo(LocalLlmState.loading, modelName: spec.fileName));
    final info = await llm.load(spec.fileName, preferGpu: ref.read(settingsProvider).preferGpu);
    state = state.copyWith(llm: info);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(activeModelId: spec.id));
    ref.read(loggerProvider).i(_tag, 'Model yükleme: ${info.state.name} ${info.backend ?? ''} ${info.detail ?? ''}');
  }

  Future<void> unload() async {
    final llm = ref.read(localLlmProvider);
    if (llm is AndroidLocalLlm) await llm.unload();
    state = state.copyWith(llm: const LocalLlmInfo(LocalLlmState.notLoaded));
  }

  void _onProgress((String, DownloadStatus) e) {
    final (id, status) = e;
    state = state.copyWith(downloads: {...state.downloads, id: status});
    if (status.phase == DownloadPhase.completed) {
      unawaited(() async {
        await refresh();
        final spec = modelById(id);
        if (spec != null && !state.ready) await load(spec);
      }());
    }
  }
}

final localAiProvider = NotifierProvider<LocalAiController, LocalAiState>(LocalAiController.new);
