import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_core/saklaz_core.dart';

import '../infrastructure/providers.dart';

/// Asistan rolü durumu: her zaman sistemden (RoleManager) okunur.
class AssistantRoleController extends AsyncNotifier<AssistantRoleStatus> {
  static const _tag = 'AssistantRole';

  @override
  Future<AssistantRoleStatus> build() => ref.read(assistantPlatformProvider).roleStatus();

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(assistantPlatformProvider).roleStatus());
  }

  /// Rolü ister; sistem diyalog göstermezse (ROLE_ASSISTANT çoğu cihazda
  /// requestable değildir) varsayılan uygulamalar ayarlarını açar.
  /// Dönüş: true = rol alındı, false = kullanıcı ayarlardan seçmeli.
  Future<bool> requestOrOpenSettings() async {
    final platform = ref.read(assistantPlatformProvider);
    final log = ref.read(loggerProvider);
    final granted = await platform.requestRole();
    log.i(_tag, 'Rol isteği sonucu: granted=$granted');
    if (!granted) {
      final opened = await platform.openDefaultAssistantSettings();
      log.i(_tag, 'Varsayılan uygulamalar ayarı açıldı=$opened');
    }
    await refresh();
    return granted;
  }
}

final assistantRoleProvider =
    AsyncNotifierProvider<AssistantRoleController, AssistantRoleStatus>(AssistantRoleController.new);
