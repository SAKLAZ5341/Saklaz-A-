import 'package:flutter/material.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../theme/saklaz_theme.dart';
import 'ai_orb.dart';

/// Mikrofon durumunun her zaman görünür göstergesi.
class MicStatusChip extends StatelessWidget {
  const MicStatusChip({super.key, required this.voice, required this.conversationActive});
  final VoiceState voice;
  final bool conversationActive;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (voice.phase) {
      VoicePhase.listening => (SaklazColors.listening, Icons.mic),
      VoicePhase.speaking => (SaklazColors.speaking, Icons.graphic_eq),
      VoicePhase.thinking => (SaklazColors.violet, Icons.auto_awesome),
      VoicePhase.requestingPermission => (SaklazColors.warning, Icons.lock_open),
      VoicePhase.idle => (SaklazColors.textSecondary, Icons.mic_off),
    };
    final label = switch (voice.phase) {
      VoicePhase.listening => 'Mikrofon açık · Dinliyor',
      VoicePhase.idle => 'Mikrofon kapalı',
      _ => 'Mikrofon kapalı · ${phaseLabel(voice.phase)}',
    };
    return Semantics(
      liveRegion: true,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
            if (conversationActive) ...[
              const SizedBox(width: 8),
              const Icon(Icons.loop, size: 14, color: SaklazColors.cyan),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Konuşmayı Başlat" ve "Konuşmayı Durdur": iki ayrı, net kontrol.
class ConversationControls extends StatelessWidget {
  const ConversationControls({
    super.key,
    required this.active,
    required this.voice,
    required this.onStart,
    required this.onStop,
  });

  final bool active;
  final VoiceState voice;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final anythingRunning = active || voice.micActive || voice.phase == VoicePhase.speaking;
    final requesting = voice.phase == VoicePhase.requestingPermission;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: SaklazColors.listening,
            foregroundColor: SaklazColors.background,
            minimumSize: const Size(170, 52),
          ),
          onPressed: active || requesting ? null : onStart,
          icon: const Icon(Icons.mic_rounded),
          label: const Text('Konuşmayı Başlat'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: SaklazColors.danger,
            side: BorderSide(color: anythingRunning ? SaklazColors.danger : SaklazColors.outline),
            minimumSize: const Size(170, 52),
          ),
          onPressed: anythingRunning ? onStop : null,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('Konuşmayı Durdur'),
        ),
      ],
    );
  }
}

/// Sesli yanıt aç/kapat (dinlemeden bağımsız).
class VoiceReplyToggle extends StatelessWidget {
  const VoiceReplyToggle({super.key, required this.enabled, required this.onChanged});
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: enabled,
      onSelected: onChanged,
      avatar: Icon(enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 18),
      label: Text(enabled ? 'Sesli yanıt açık' : 'Sesli yanıt kapalı'),
      showCheckmark: false,
      tooltip: 'Sesli yanıtı aç/kapat',
    );
  }
}
