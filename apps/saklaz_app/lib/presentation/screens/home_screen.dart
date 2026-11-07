import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant_role_controller.dart';
import '../../application/conversation_controller.dart';
import '../../application/settings_controller.dart';
import '../../infrastructure/providers.dart';
import '../layout/breakpoints.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/ai_orb.dart';
import '../widgets/conversation_view.dart';
import '../widgets/mic_controls.dart';
import '../widgets/saklaz_logo.dart';
import 'memory_screen.dart';
import 'permissions_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(ref.read(assistantRoleProvider.notifier).refresh());
      // "inactive" izin diyaloğu/bildirim perdesinde de gelir; mikrofonu o zaman
      // kapatmak izin akışını bozar. Görünmez olunca (hidden/paused) kapatılır.
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        unawaited(ref.read(conversationProvider.notifier).onAppBackgrounded());
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _send() {
    final text = _input.text;
    _input.clear();
    unawaited(ref.read(conversationProvider.notifier).submitText(text));
  }

  @override
  Widget build(BuildContext context) {
    final conv = ref.watch(conversationProvider);
    final voiceReplies = ref.watch(settingsProvider.select((s) => s.voiceReplies));
    final memory = ref.watch(memoryProvider);
    final layout = context.saklazLayout;
    final ctrl = ref.read(conversationProvider.notifier);

    final orbPane = _OrbPane(
      conv: conv,
      orbSize: layout == SaklazLayout.compact ? 170 : 280,
      voiceReplies: voiceReplies,
      onStart: () => unawaited(ctrl.startConversation()),
      onStop: () => unawaited(ctrl.stopConversation()),
      onVoiceReplies: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(voiceReplies: v)),
    );
    final chatPane = Column(
      children: [
        if (!memory.encrypted)
          MaterialBanner(
            backgroundColor: SaklazColors.warning.withValues(alpha: 0.12),
            leading: const Icon(Icons.lock_open, color: SaklazColors.warning),
            content: Text(
              'Şifreli hafıza açılamadı (${memory.error ?? 'bilinmiyor'}). Konuşmalar yalnızca bellekte tutuluyor.',
              style: const TextStyle(color: SaklazColors.warning),
            ),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(
          child: ConversationView(
            messages: conv.messages,
            partialText: conv.voice.partialText,
            pending: conv.pending,
            busy: conv.busy,
            onReplay: (m) => unawaited(ctrl.replay(m)),
            onResolve: ({required accept, preferLocal = false}) =>
                unawaited(ctrl.resolvePending(accept: accept, preferLocal: preferLocal)),
          ),
        ),
        _InputBar(controller: _input, onSend: _send, enabled: !conv.busy),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const SaklazWordmark(height: 24),
        actions: [
          const _RoleBadge(),
          IconButton(
            tooltip: 'Hafıza',
            icon: const Icon(Icons.memory),
            onPressed: () => Navigator.pushNamed(context, MemoryScreen.route),
          ),
          IconButton(
            tooltip: 'Asistan izinleri',
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: () => Navigator.pushNamed(context, PermissionsScreen.route),
          ),
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.pushNamed(context, SettingsScreen.route),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (layout) {
          SaklazLayout.expanded || SaklazLayout.medium => Row(
              children: [
                Expanded(flex: 5, child: SingleChildScrollView(child: orbPane)),
                const VerticalDivider(width: 1, color: SaklazColors.outline),
                Expanded(flex: 6, child: chatPane),
              ],
            ),
          SaklazLayout.compact => Column(
              children: [
                orbPane,
                const Divider(height: 1, color: SaklazColors.outline),
                Expanded(child: chatPane),
              ],
            ),
        },
      ),
    );
  }
}

class _OrbPane extends StatelessWidget {
  const _OrbPane({
    required this.conv,
    required this.orbSize,
    required this.voiceReplies,
    required this.onStart,
    required this.onStop,
    required this.onVoiceReplies,
  });

  final ConversationState conv;
  final double orbSize;
  final bool voiceReplies;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final ValueChanged<bool> onVoiceReplies;

  @override
  Widget build(BuildContext context) {
    final voice = conv.voice;
    final message = voice.errorMessage ?? conv.notice;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AiOrb(phase: voice.phase, level: voice.level, size: orbSize),
          const SizedBox(height: 6),
          MicStatusChip(voice: voice, conversationActive: conv.conversationActive),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: SaklazColors.warning)),
            ),
          const SizedBox(height: 12),
          ConversationControls(active: conv.conversationActive, voice: voice, onStart: onStart, onStop: onStop),
          const SizedBox(height: 8),
          VoiceReplyToggle(enabled: voiceReplies, onChanged: onVoiceReplies),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend, required this.enabled});
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(hintText: 'SAKLAZ\'a yaz...'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Gönder',
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

/// Üst çubukta rol durumunu gösteren küçük rozet (sistemden okunur).
class _RoleBadge extends ConsumerWidget {
  const _RoleBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(assistantRoleProvider);
    if (role.value?.isDefaultAssistant ?? false) {
      return const Tooltip(
        message: 'SAKLAZ varsayılan dijital asistan',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.check_circle, color: SaklazColors.listening, size: 20),
        ),
      );
    }
    return IconButton(
      tooltip: 'SAKLAZ henüz varsayılan asistan değil',
      icon: const Icon(Icons.error_outline, color: SaklazColors.warning, size: 20),
      onPressed: () => Navigator.pushNamed(context, PermissionsScreen.route),
    );
  }
}
