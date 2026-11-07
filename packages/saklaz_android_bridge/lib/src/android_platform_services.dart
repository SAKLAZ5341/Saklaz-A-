import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_core/saklaz_core.dart';

import 'generated/saklaz_api.g.dart' as g;

/// Veritabanı anahtarı ve dizini (Keystore ile korunur).
class DatabaseKey {
  const DatabaseKey({required this.hexKey, required this.hardwareBacked, required this.directory});
  final String hexKey;
  final bool hardwareBacked;
  final String directory;
}

abstract interface class KeyVault {
  Future<DatabaseKey> databaseKey();
}

class AndroidKeyVault implements KeyVault {
  AndroidKeyVault({g.KeyVaultHostApi? api}) : _api = api ?? g.KeyVaultHostApi();
  final g.KeyVaultHostApi _api;

  @override
  Future<DatabaseKey> databaseKey() async {
    final m = await _api.getOrCreateDatabaseKey();
    return DatabaseKey(hexKey: m.hexKey, hardwareBacked: m.hardwareBacked, directory: m.databaseDirectory);
  }
}

abstract interface class NetworkStatus {
  Future<bool> isOnline();
}

class AndroidNetworkStatus implements NetworkStatus {
  AndroidNetworkStatus({g.NetworkHostApi? api}) : _api = api ?? g.NetworkHostApi();
  final g.NetworkHostApi _api;

  @override
  Future<bool> isOnline() => _api.isOnline();
}

class DeviceCapability {
  const DeviceCapability({
    required this.totalRamMb,
    required this.availableRamMb,
    required this.lowRamDevice,
    required this.soc,
    required this.abis,
  });
  final int totalRamMb;
  final int availableRamMb;
  final bool lowRamDevice;
  final String soc;
  final List<String> abis;

  /// Ayrı bir LLM'i (ör. Gemma 3 1B int4, ~1 GB tepe RAM) uygulama içinde
  /// çalıştırmak için kaba eşik. Gemini Nano sistemde çalıştığı için bu eşiğe
  /// tabi değildir.
  bool get canHostOwnSmallModel => !lowRamDevice && totalRamMb >= 8000 && abis.contains('arm64-v8a');
}

/// Gemini Nano (ML Kit GenAI Prompt API) adaptörü.
class AndroidLocalLlm implements LocalLlm {
  AndroidLocalLlm({g.LocalAiHostApi? api}) : _api = api ?? g.LocalAiHostApi();
  final g.LocalAiHostApi _api;

  Future<DeviceCapability> deviceCapability() async {
    final d = await _api.getDeviceCapability();
    return DeviceCapability(
      totalRamMb: d.totalRamMb,
      availableRamMb: d.availableRamMb,
      lowRamDevice: d.lowRamDevice,
      soc: '${d.socManufacturer} ${d.socModel}'.trim(),
      abis: d.abis,
    );
  }

  static LocalLlmInfo _map(g.LocalModelInfoMessage m) => LocalLlmInfo(
        switch (m.status) {
          g.LocalModelStatus.available => LocalLlmState.ready,
          g.LocalModelStatus.downloadable => LocalLlmState.downloadable,
          g.LocalModelStatus.downloading => LocalLlmState.downloading,
          g.LocalModelStatus.unavailable => LocalLlmState.unavailable,
          g.LocalModelStatus.error => LocalLlmState.error,
        },
        modelName: m.baseModelName,
        detail: m.detail,
      );

  @override
  Future<LocalLlmInfo> info() async => _map(await _api.checkModel());

  @override
  Future<LocalLlmInfo> download() async => _map(await _api.downloadModel());

  @override
  Future<Result<String>> generate(String prompt, {int maxOutputTokens = 256, double temperature = 0.3}) async {
    try {
      return Result.ok(await _api.generate(prompt, maxOutputTokens, temperature));
    } on Object catch (e) {
      return Result.err(Failure('local-model', 'Yerel model hatası', cause: e));
    }
  }
}
