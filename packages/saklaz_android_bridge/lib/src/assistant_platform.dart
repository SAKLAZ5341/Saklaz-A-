import 'dart:async';

import 'generated/saklaz_api.g.dart' as g;

/// Sistemden okunan gerçek asistan rolü durumu.
class AssistantRoleStatus {
  const AssistantRoleStatus({
    required this.roleAvailable,
    required this.roleHeld,
    required this.voiceInteractionServiceActive,
    required this.sdkInt,
    required this.device,
  });

  final bool roleAvailable;
  final bool roleHeld;
  final bool voiceInteractionServiceActive;
  final int sdkInt;
  final String device;

  /// SAKLAZ gerçekten varsayılan dijital asistan mı? (rol + aktif servis)
  bool get isDefaultAssistant => roleHeld && voiceInteractionServiceActive;
}

enum AssistSource { voiceInteractionSession, assistIntent }

class AssistInvocation {
  const AssistInvocation(this.source, this.time);
  final AssistSource source;
  final DateTime time;
}

abstract interface class AssistantPlatform {
  Future<AssistantRoleStatus> roleStatus();

  /// true: rol alındı. false: sistem vermedi (ayarlar açılmalı).
  Future<bool> requestRole();
  Future<bool> openDefaultAssistantSettings();

  /// Soğuk açılışta bekleyen çağrı (varsa) bir kez döner.
  Future<AssistInvocation?> consumePendingInvocation();

  /// Uygulama açıkken gelen asistan çağrıları.
  Stream<AssistInvocation> get invocations;
}

class AndroidAssistantPlatform implements AssistantPlatform, g.AssistLaunchFlutterApi {
  AndroidAssistantPlatform({g.AssistantRoleHostApi? roleApi, g.AssistLaunchHostApi? launchApi})
      : _role = roleApi ?? g.AssistantRoleHostApi(),
        _launch = launchApi ?? g.AssistLaunchHostApi() {
    g.AssistLaunchFlutterApi.setUp(this);
  }

  final g.AssistantRoleHostApi _role;
  final g.AssistLaunchHostApi _launch;
  final _controller = StreamController<AssistInvocation>.broadcast();

  @override
  Stream<AssistInvocation> get invocations => _controller.stream;

  @override
  Future<AssistantRoleStatus> roleStatus() async {
    final s = await _role.getStatus();
    return AssistantRoleStatus(
      roleAvailable: s.roleAvailable,
      roleHeld: s.roleHeld,
      voiceInteractionServiceActive: s.voiceInteractionServiceActive,
      sdkInt: s.sdkInt,
      device: '${s.manufacturer} ${s.model}',
    );
  }

  @override
  Future<bool> requestRole() async =>
      await _role.requestRole() == g.RoleRequestOutcome.granted;

  @override
  Future<bool> openDefaultAssistantSettings() => _role.openDefaultAssistantSettings();

  @override
  Future<AssistInvocation?> consumePendingInvocation() async {
    final m = await _launch.consumePendingLaunch();
    return m == null ? null : _map(m);
  }

  @override
  void onAssistInvoked(g.AssistLaunchMessage launch) => _controller.add(_map(launch));

  static AssistInvocation _map(g.AssistLaunchMessage m) => AssistInvocation(
        switch (m.source) {
          g.AssistLaunchSource.voiceInteractionSession => AssistSource.voiceInteractionSession,
          g.AssistLaunchSource.assistIntent => AssistSource.assistIntent,
        },
        DateTime.fromMillisecondsSinceEpoch(m.timestampMillis),
      );
}
