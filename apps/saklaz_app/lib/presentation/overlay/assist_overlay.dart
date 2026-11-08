import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../../application/conversation_controller.dart';
import '../../application/local_ai_controller.dart';
import '../../infrastructure/providers.dart';
import '../theme/saklaz_theme.dart';
import '../widgets/ai_orb.dart';
import '../widgets/conversation_view.dart';
import '../widgets/mic_controls.dart';
import '../widgets/saklaz_logo.dart';

/// Yan tuşla açılan panel uygulaması (uygulama açılmadan, ekranın altından).
class AssistOverlayApp extends StatelessWidget {
  const AssistOverlayApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildSaklazTheme().copyWith(scaffoldBackgroundColor: Colors.transparent),
        color: Colors.transparent,
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const _OverlayBootstrap(),
      );
}

class _OverlayBootstrap extends ConsumerWidget {
  const _OverlayBootstrap();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(memoryStoresProvider).when(
        data: (_) => const AssistOverlay(),
        loading: () => const Scaffold(backgroundColor: Colors.transparent, body: SizedBox.shrink()),
        error: (e, _) => const Scaffold(backgroundColor: Colors.transparent, body: SizedBox.shrink()),
      );
}

class AssistOverlay extends ConsumerStatefulWidget {
  const AssistOverlay({super.key});
  @override
  ConsumerState<AssistOverlay> createState() => _AssistOverlayState();
}

class _AssistOverlayState extends ConsumerState<AssistOverlay> {
  DateTime _sessionStart = DateTime.now();
  Timer? _autoClose;

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  Future<void> _dismiss() async {
    _autoClose?.cancel();
    await ref.read(conversationProvider.notifier).stopConversation();
    await ref.read(assistSessionProvider).dismiss();
  }

  void _scheduleAutoClose(ConversationState c) {
    _autoClose?.cancel();
    final idle = !c.conversationActive && !c.busy && c.pending == null && c.voice.phase == VoicePhase.idle;
    if (idle) _autoClose = Timer(const Duration(seconds: 4), _dismiss);
  }

  @override
  Widget build(BuildContext context) {
    final conv = ref.watch(conversationProvider);
    final ai = ref.watch(localAiProvider);

    ref.listen(conversationProvider, (prev, next) {
      if (prev?.lastInvocation != next.lastInvocation) setState(() => _sessionStart = DateTime.now().subtract(const Duration(seconds: 1)));
      if ((prev?.externalLaunches ?? 0) < next.externalLaunches) {
        unawaited(_dismiss());
        return;
      }
      _scheduleAutoClose(next);
    });

    final session = conv.messages.where((m) => m.createdAt.isAfter(_sessionStart)).toList();
    final micDenied = conv.notice == 'Mikrofon izni verilmedi.' || conv.voice.errorMessage == 'Mikrofon izni verilmedi.';
    final height = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        // Dışarı dokununca kapan.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_dismiss()),
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 720, maxHeight: height * 0.62),
              child: Container(
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                decoration: BoxDecoration(
                  color: SaklazColors.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: SaklazColors.outline),
                  boxShadow: [BoxShadow(color: SaklazColors.violet.withValues(alpha: 0.25), blurRadius: 30)],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
                    child: Row(children: [
                      const SaklazWordmark(height: 18),
                      const Spacer(),
                      if (ai.llm.modelName != null && !ai.ready && conv.busy)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Text('Model yükleniyor…', style: TextStyle(color: SaklazColors.cyan, fontSize: 12)),
                        ),
                      IconButton(
                        tooltip: 'Uygulamayı aç',
                        icon: const Icon(Icons.open_in_full, size: 20),
                        onPressed: () async {
                          await ref.read(conversationProvider.notifier).stopConversation();
                          await ref.read(assistSessionProvider).openMainApp();
                        },
                      ),
                      IconButton(tooltip: 'Kapat', icon: const Icon(Icons.close, size: 20), onPressed: () => unawaited(_dismiss())),
                    ]),
                  ),
                  if (session.isNotEmpty || conv.voice.partialText.isNotEmpty || conv.busy || conv.pending != null)
                    Flexible(
                      child: ConversationView(
                        messages: session,
                        partialText: conv.voice.partialText,
                        pending: conv.pending,
                        busy: conv.busy,
                        onReplay: (m) => unawaited(ref.read(conversationProvider.notifier).replay(m)),
                        onResolve: ({required accept, preferLocal = false}) => unawaited(
                          ref.read(conversationProvider.notifier).resolvePending(accept: accept, preferLocal: preferLocal),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Row(children: [
                      AiOrb(phase: conv.voice.phase, level: conv.voice.level, size: 56),
                      const SizedBox(width: 12),
                      Expanded(
                        child: micDenied
                            ? const Text('Mikrofon izni yok. SAKLAZ uygulamasını bir kez açıp izin ver.',
                                style: TextStyle(color: SaklazColors.warning))
                            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                MicStatusChip(voice: conv.voice, conversationActive: conv.conversationActive),
                                if (session.isEmpty && conv.voice.partialText.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text('Seni dinliyorum…', style: TextStyle(color: SaklazColors.textSecondary)),
                                  ),
                              ]),
                      ),
                      IconButton.filled(
                        tooltip: conv.conversationActive ? 'Durdur' : 'Konuş',
                        onPressed: () => conv.conversationActive
                            ? unawaited(ref.read(conversationProvider.notifier).stopConversation())
                            : unawaited(ref.read(conversationProvider.notifier).startConversation()),
                        icon: Icon(conv.conversationActive ? Icons.stop_rounded : Icons.mic_rounded),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
