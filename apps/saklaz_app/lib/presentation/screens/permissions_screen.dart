import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../../application/assistant_role_controller.dart';
import '../../infrastructure/providers.dart';
import '../theme/saklaz_theme.dart';

final micPermissionStateProvider = FutureProvider.autoDispose<MicPermission>(
  (ref) => ref.watch(micPermissionProvider).current(),
);

/// Asistan rolü ve mikrofon izni. Tüm durumlar sistemden okunur.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});
  static const route = '/permissions';

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    ref.read(assistantRoleProvider.notifier).refresh();
    ref.invalidate(micPermissionStateProvider);
  }

  Future<void> _requestRole() async {
    final granted = await ref.read(assistantRoleProvider.notifier).requestOrOpenSettings();
    if (!mounted || granted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Android bu rolü uygulama içinden vermiyor. Açılan ekranda '
          '"Dijital asistan uygulaması" bölümünden SAKLAZ\'ı seç.',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }

  Future<void> _requestMic(MicPermission current) async {
    final port = ref.read(micPermissionProvider);
    if (current == MicPermission.permanentlyDenied) {
      await port.openAppSettings();
    } else {
      await port.request();
    }
    ref.invalidate(micPermissionStateProvider);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(assistantRoleProvider);
    final mic = ref.watch(micPermissionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistan izinleri'),
        actions: [IconButton(tooltip: 'Yenile', onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          role.when(
            data: (s) => _RoleCard(status: s, onRequest: _requestRole),
            loading: () => const _LoadingCard(),
            error: (e, _) => _ErrorCard(message: 'Rol durumu okunamadı: $e'),
          ),
          const SizedBox(height: 12),
          mic.when(
            data: (m) => _StatusCard(
              icon: Icons.mic,
              title: 'Mikrofon',
              ok: m == MicPermission.granted,
              okText: 'İzin verildi',
              notOkText: m == MicPermission.permanentlyDenied
                  ? 'Kalıcı olarak reddedildi — uygulama ayarlarından açılmalı'
                  : 'İzin verilmedi',
              description:
                  'Mikrofon yalnızca sen mikrofon düğmesine bastığında veya SAKLAZ\'ı yan tuşla '
                  'çağırdığında açılır. Sürekli dinleme yapılmaz, ses kaydedilmez.',
              actionLabel: m == MicPermission.permanentlyDenied ? 'Uygulama ayarları' : 'İzin ver',
              onAction: m == MicPermission.granted ? null : () => _requestMic(m),
            ),
            loading: () => const _LoadingCard(),
            error: (e, _) => _ErrorCard(message: 'Mikrofon durumu okunamadı: $e'),
          ),
          const SizedBox(height: 12),
          const _PhonePermissionsCard(),
          const SizedBox(height: 12),
          const _SideKeyHelpCard(),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.status, required this.onRequest});
  final AssistantRoleStatus status;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final ok = status.isDefaultAssistant;
    return _StatusCard(
      icon: Icons.assistant,
      title: 'Varsayılan dijital asistan',
      ok: ok,
      okText: 'SAKLAZ varsayılan asistan',
      notOkText: !status.roleAvailable
          ? 'Bu cihazda asistan rolü kullanılamıyor'
          : (status.roleHeld ? 'Rol alındı, servis henüz etkin değil' : 'SAKLAZ varsayılan asistan değil'),
      description: 'Sistem durumu — ROLE_ASSISTANT: ${status.roleHeld ? "evet" : "hayır"}, '
          'VoiceInteractionService etkin: ${status.voiceInteractionServiceActive ? "evet" : "hayır"}\n'
          'Cihaz: ${status.device} · Android API ${status.sdkInt}',
      actionLabel: 'Varsayılan asistan yap',
      onAction: ok || !status.roleAvailable ? null : onRequest,
    );
  }
}

class _SideKeyHelpCard extends StatelessWidget {
  const _SideKeyHelpCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.smart_button, color: SaklazColors.cyan),
              SizedBox(width: 12),
              Expanded(
                child: Text('Yan tuşla çağırma (Samsung)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ]),
            SizedBox(height: 12),
            Text(
              '1. SAKLAZ\'ı varsayılan dijital asistan yap (yukarıdaki kart).\n'
              '2. Ayarlar → Gelişmiş özellikler → Yan tuş.\n'
              '3. "Basılı tut" altında "Dijital asistan"ı seç.\n'
              '4. Yan tuşa basılı tut: SAKLAZ açılır.',
              style: TextStyle(color: SaklazColors.textSecondary, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.ok,
    required this.okText,
    required this.notOkText,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final bool ok;
  final String okText;
  final String notOkText;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final color = ok ? SaklazColors.listening : SaklazColors.warning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: SaklazColors.cyan),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                Icon(ok ? Icons.check_circle : Icons.error_outline, color: color),
              ],
            ),
            const SizedBox(height: 8),
            Text(ok ? okText : notOkText, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(description, style: const TextStyle(color: SaklazColors.textSecondary, height: 1.5)),
            if (onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) =>
      const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(message, style: const TextStyle(color: SaklazColors.danger)),
        ),
      );
}

final _phonePermsProvider = FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  final d = ref.watch(devicePortsProvider);
  if (d is! AndroidDevicePorts) return const {};
  final cap = await d.reminderCapability();
  return {
    'contacts': await d.hasPermission(DevicePermission.contacts),
    'calendar': await d.hasPermission(DevicePermission.calendar),
    'notifications': cap.notifications,
    'exact': cap.exact,
    'listener': await d.notificationAccess(),
  };
});

/// Telefon entegrasyonu izinleri. Hepsi isteğe bağlıdır; yalnızca ilgili özellik için gerekir.
class _PhonePermissionsCard extends ConsumerWidget {
  const _PhonePermissionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(_phonePermsProvider).value ?? const {};
    final d = ref.watch(devicePortsProvider);
    Future<void> run(Future<Object?> Function(AndroidDevicePorts a) f) async {
      if (d is AndroidDevicePorts) await f(d);
      ref.invalidate(_phonePermsProvider);
    }

    Widget row(String key, IconData icon, String title, String why, Future<Object?> Function(AndroidDevicePorts a) grant) {
      final ok = perms[key] ?? false;
      return ListTile(
        leading: Icon(icon, color: SaklazColors.cyan),
        title: Text(title),
        subtitle: Text(why, style: const TextStyle(color: SaklazColors.textSecondary)),
        trailing: ok
            ? const Icon(Icons.check_circle, color: SaklazColors.listening)
            : TextButton(onPressed: () => run(grant), child: const Text('İzin ver')),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          const ListTile(
            title: Text('Telefon entegrasyonu (isteğe bağlı)', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('İzinler yalnızca ilgili özelliği kullanınca gerekir. Veriler cihazdan çıkmaz.'),
          ),
          row('contacts', Icons.contacts_outlined, 'Rehber', 'Kişiyi arama ve WhatsApp taslağı için', (a) => a.ensurePermission(DevicePermission.contacts)),
          row('calendar', Icons.event_outlined, 'Takvim (okuma)', '"Bugün takvimimde ne var?" için', (a) => a.ensurePermission(DevicePermission.calendar)),
          row('notifications', Icons.notifications_outlined, 'Bildirim gösterme', 'Hatırlatmaların bildirimi için', (a) => a.ensurePermission(DevicePermission.notifications)),
          row('exact', Icons.alarm_on_outlined, 'Tam zamanlı alarm', 'Hatırlatmaların dakikasında çalması için', (a) => a.openExactAlarmSettings()),
          row('listener', Icons.mark_chat_unread_outlined, 'Bildirim erişimi', 'Bildirimleri okuma ve onaylı yanıt için', (a) => a.openNotificationAccessSettings()),
        ]),
      ),
    );
  }
}
