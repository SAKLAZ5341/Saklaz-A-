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
    this.activeFile,
  });

  final Set<String> installed;
  final Map<String, DownloadStatus> downloads;
  final LocalLlmInfo llm;
  final DeviceCapability? capability;

  /// İlk soruda yüklenecek kurulu model.
  final String? activeFile;

  bool isInstalled(ModelSpec m) => installed.contains(m.fileName);
  bool get ready => llm.state == LocalLlmState.ready;

  /// Yerel model kullanılabilir mi? (Yüklü olması gerekmez; ilk soruda yüklenir.)
  bool get usable => ready || (activeFile != null && installed.contains(activeFile));

  LocalAiState copyWith({
    Set<String>? installed,
    Map<String, DownloadStatus>? downloads,
    LocalLlmInfo? llm,
    DeviceCapability? capability,
    String? activeFile,
  }) =>
      LocalAiState(
        installed: installed ?? this.installed,
        downloads: downloads ?? this.downloads,
        llm: llm ?? this.llm,
        capability: capability ?? this.capability,
        activeFile: activeFile ?? this.activeFile,
      );
}

/// Model indirme, doğrulama ve yükleme. Telefonun donmaması için model açılışta
/// YÜKLENMEZ; ilk yerel AI sorusunda (arka planda) yüklenir.
class LocalAiController extends Notifier<LocalAiState> {
  static const _tag = 'LocalAi';
  StreamSubscription<(String, DownloadStatus)>? _sub;

  ModelManager get _mm => ref.read(modelManagerProvider);

  @override
  LocalAiState build() {
    _sub = _mm.progress.listen(_onProgress);
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(refresh);
    return const LocalAiState();
  }

  /// Kurulu modelleri ve motor durumunu okur. Belleğe yükleme YAPMAZ.
  Future<void> refresh() async {
    try {
      final installed = await _mm.installedFiles();
      final cap = await _mm.capability();
      final settings = ref.read(settingsProvider);
      var active = modelById(settings.activeModelId);
      if (active == null || !installed.contains(active.fileName)) {
        active = modelCatalog.where((m) => installed.contains(m.fileName)).firstOrNull;
      }
      final llm = ref.read(localLlmProvider);
      if (llm is AndroidLocalLlm) {
        llm.noModelInstalled = installed.isEmpty;
        llm.preferredFile = active?.fileName;
        llm.preferGpu = settings.preferGpu;
      }
      state = state.copyWith(installed: installed, capability: cap, llm: await llm.info(), activeFile: active?.fileName);
    } on Object catch (e) {
      ref.read(loggerProvider).w(_tag, 'Model durumu okunamadı', error: e);
    }
  }

  /// Yalnızca motor durumunu tazeler (ör. tembel yüklemeden sonra).
  Future<void> syncStatus() async {
    try {
      state = state.copyWith(llm: await ref.read(localLlmProvider).info());
    } on Object {
      // yok say
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

  /// Kullanıcı "Yükle ve kullan" dediğinde: modeli seç ve hemen yükle.
  Future<void> load(ModelSpec spec) async {
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(activeModelId: spec.id));
    final llm = ref.read(localLlmProvider);
    if (llm is! AndroidLocalLlm) return;
    llm.preferredFile = spec.fileName;
    llm.preferGpu = ref.read(settingsProvider).preferGpu;
    state = state.copyWith(llm: LocalLlmInfo(LocalLlmState.loading, modelName: spec.fileName), activeFile: spec.fileName);
    final info = await llm.ensureLoaded();
    state = state.copyWith(llm: info);
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
      final spec = modelById(id);
      if (spec != null) ref.read(settingsProvider.notifier).update((s) => s.copyWith(activeModelId: spec.id));
      unawaited(refresh());
    }
  }
}

final localAiProvider = NotifierProvider<LocalAiController, LocalAiState>(LocalAiController.new);
