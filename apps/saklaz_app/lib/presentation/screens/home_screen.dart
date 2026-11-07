import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../../application/assistant_role_controller.dart';
import '../../application/conversation_controller.dart';
import '../layout/breakpoints.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/ai_orb.dart';
import '../widgets/conversation_view.dart';
import '../widgets/mic_controls.dart';
import '../widgets/saklaz_logo.dart';
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
    // Ayarlar'dan dönünce rol durumunu yeniden oku.
    if (state == AppLifecycleState.resumed) {
      ref.read(assistantRoleProvider.notifier).refresh();
    }
  }

  void _send() {
    final text = _input.text;
    _input.clear();
    ref.read(conversationProvider.notifier).submitText(text);
  }

  @override
  Widget build(BuildContext context) {
    final conv = ref.watch(conversationProvider);
    final layout = context.saklazLayout;
    final ctrl = ref.read(conversationProvider.notifier);

    final orbPane = _OrbPane(
      voice: conv.voice,
      orbSize: layout == SaklazLayout.compact ? 200 : 300,
      onMic: ctrl.toggleMic,
    );
    final chatPane = Column(
      children: [
        Expanded(
          child: ConversationView(messages: conv.messages, partialText: conv.voice.partialText),
        ),
        _InputBar(controller: _input, onSend: _send),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const SaklazWordmark(height: 26),
        actions: [
          const _RoleBadge(),
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
                Expanded(flex: 5, child: orbPane),
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
  const _OrbPane({required this.voice, required this.orbSize, required this.onMic});
  final VoiceState voice;
  final double orbSize;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AiOrb(phase: voice.phase, level: voice.level, size: orbSize),
          const SizedBox(height: 8),
          MicStatusChip(voice: voice),
          if (voice.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
              child: Text(
                voice.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: SaklazColors.warning),
              ),
            ),
          const SizedBox(height: 16),
          MicButton(voice: voice, onPressed: onMic),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

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
            onPressed: onSend,
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
    final isDefault = role.value?.isDefaultAssistant ?? false;
    if (isDefault) {
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
