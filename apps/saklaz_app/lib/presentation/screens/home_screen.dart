import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_ai_core/saklaz_ai_core.dart';
import 'package:saklaz_android_bridge/saklaz_android_bridge.dart';

import '../../application/assistant_role_controller.dart';
import '../../application/conversation_controller.dart';
import '../../application/local_ai_controller.dart';
import '../../application/settings_controller.dart';
import '../../infrastructure/providers.dart';
import '../layout/breakpoints.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/ai_orb.dart';
import '../widgets/common.dart';
import '../widgets/conversation_view.dart';
import '../widgets/mic_controls.dart';
import '../widgets/saklaz_logo.dart';
import 'ai_settings_screen.dart';
import 'memory_screen.dart';
import 'model_screen.dart';
import 'permissions_screen.dart';
import 'settings_screen.dart';

final factCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(conversationProvider.select((c) => c.messages.length));
  return (await ref.watch(memoryProvider).facts.all()).length;
});

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
    unawaited(_applyDevConfig());
  }

  /// YALNIZCA debug APK: adb ile gelen gateway adresi/tokenı ön doldurulur (etkinleştirilmez).
  Future<void> _applyDevConfig() async {
    final dev = await consumeDevConfig();
    if (dev == null || !mounted) return;
    final s = ref.read(settingsProvider);
    if (dev.url != null) {
      ref.read(settingsProvider.notifier).update((x) => x.copyWith(providerUpdate: s.provider(ProviderKind.gateway).copyWith(baseUrl: dev.url)));
    }
    if (dev.token != null) await ref.read(secretStoreProvider).put(ProviderKind.gateway.secretName, dev.token!);
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
      // "inactive" izin diyaloğunda da gelir; mikrofonu yalnızca görünmez olunca kapat.
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

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Fotoğraf çek'), onTap: () => Navigator.pop(c, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Galeriden fotoğraf'), onTap: () => Navigator.pop(c, 'gallery')),
          ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Dosya seç (PDF, metin, görsel)'), onTap: () => Navigator.pop(c, 'file')),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text('Görüntü ve dosya cihazdan çıkmaz; metin ve nesneler cihazda okunur, yerel modele verilir.',
                style: TextStyle(color: SaklazColors.textSecondary, fontSize: 12)),
          ),
        ]),
      ),
    );
    if (choice == null) return;
    final reader = ref.read(documentReaderProvider);
    try {
      final doc = choice == 'file' ? await reader.pickFile() : await reader.captureImage(fromCamera: choice == 'camera');
      if (doc != null) await ref.read(conversationProvider.notifier).analyzeDocument(doc);
    } on Object catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dosya okunamadı: $e')));
    }
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
      orbSize: layout == SaklazLayout.compact ? 150 : 260,
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
        _InputBar(controller: _input, onSend: _send, onAttach: () => unawaited(_attach()), enabled: !conv.busy),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const SaklazWordmark(height: 24),
        actions: [
          const _RoleBadge(),
          IconButton(tooltip: 'Benim Hafızam', icon: const Icon(Icons.memory), onPressed: () => Navigator.pushNamed(context, MemoryScreen.route)),
          IconButton(tooltip: 'Ayarlar', icon: const Icon(Icons.tune), onPressed: () => Navigator.pushNamed(context, SettingsScreen.route)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const _StatusStrip(),
            Expanded(
              child: switch (layout) {
                SaklazLayout.expanded || SaklazLayout.medium => Row(children: [
                    Expanded(flex: 5, child: SingleChildScrollView(child: orbPane)),
                    const VerticalDivider(width: 1, color: SaklazColors.outline),
                    Expanded(flex: 6, child: chatPane),
                  ]),
                SaklazLayout.compact => Column(children: [
                    orbPane,
                    const Divider(height: 1, color: SaklazColors.outline),
                    Expanded(child: chatPane),
                  ]),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Yerel AI, model, hafıza ve sağlayıcı durumu.
class _StatusStrip extends ConsumerWidget {
  const _StatusStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(localAiProvider);
    final facts = ref.watch(factCountProvider).value ?? 0;
    final cloud = ref.watch(settingsProvider.select((s) => s.activeCloud));
    final (aiLabel, aiColor) = switch (ai.llm.state) {
      LocalLlmState.ready => ('Yerel AI hazır', SaklazColors.listening),
      LocalLlmState.loading => ('Model yükleniyor…', SaklazColors.cyan),
      LocalLlmState.notLoaded => ('Model yüklü değil', SaklazColors.warning),
      LocalLlmState.noModel => ('Model indirilmedi', SaklazColors.warning),
      LocalLlmState.failed => ('Model hatası', SaklazColors.danger),
    };
    final downloading = ai.downloads.values.where((d) => d.phase == DownloadPhase.running).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          StatusPill(
            icon: Icons.psychology,
            label: downloading != null ? 'İndiriliyor %${(downloading.fraction * 100).round()}' : aiLabel,
            color: aiColor,
            tooltip: ai.llm.modelName ?? 'Model Yönetimi',
            onTap: () => Navigator.pushNamed(context, ModelScreen.route),
          ),
          const SizedBox(width: 8),
          StatusPill(
            icon: Icons.memory,
            label: 'Hafıza: $facts bilgi',
            color: SaklazColors.cyan,
            onTap: () => Navigator.pushNamed(context, MemoryScreen.route),
          ),
          const SizedBox(width: 8),
          StatusPill(
            icon: cloud == null ? Icons.lock_outline : Icons.cloud_outlined,
            label: cloud == null ? 'Tamamen yerel' : 'Bulut: ${cloud.kind.label}',
            color: cloud == null ? SaklazColors.listening : SaklazColors.magenta,
            onTap: () => Navigator.pushNamed(context, AiSettingsScreen.route),
          ),
        ]),
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
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AiOrb(phase: voice.phase, level: voice.level, size: orbSize),
          const SizedBox(height: 4),
          MicStatusChip(voice: voice, conversationActive: conv.conversationActive),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: SaklazColors.warning)),
            ),
          const SizedBox(height: 10),
          ConversationControls(active: conv.conversationActive, voice: voice, onStart: onStart, onStop: onStop),
          const SizedBox(height: 6),
          VoiceReplyToggle(enabled: voiceReplies, onChanged: onVoiceReplies),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend, required this.onAttach, required this.enabled});
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
      child: Row(
        children: [
          IconButton(tooltip: 'Dosya veya fotoğraf ekle', onPressed: enabled ? onAttach : null, icon: const Icon(Icons.add_circle_outline)),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(hintText: 'SAKLAZ\'a yaz...'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(tooltip: 'Gönder', onPressed: enabled ? onSend : null, icon: const Icon(Icons.arrow_upward_rounded)),
        ],
      ),
    );
  }
}

class _RoleBadge extends ConsumerWidget {
  const _RoleBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(assistantRoleProvider);
    if (role.value?.isDefaultAssistant ?? false) {
      return const Tooltip(
        message: 'SAKLAZ varsayılan dijital asistan',
        child: Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.check_circle, color: SaklazColors.listening, size: 20)),
      );
    }
    return IconButton(
      tooltip: 'SAKLAZ henüz varsayılan asistan değil',
      icon: const Icon(Icons.error_outline, color: SaklazColors.warning, size: 20),
      onPressed: () => Navigator.pushNamed(context, PermissionsScreen.route),
    );
  }
}
