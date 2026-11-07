import 'package:flutter/material.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../theme/saklaz_theme.dart';
import 'ai_orb.dart';

/// Mikrofon durumunun her zaman görünür göstergesi.
class MicStatusChip extends StatelessWidget {
  const MicStatusChip({super.key, required this.voice});
  final VoiceState voice;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (voice.phase) {
      VoicePhase.listening => (SaklazColors.listening, Icons.mic),
      VoicePhase.speaking => (SaklazColors.speaking, Icons.graphic_eq),
      VoicePhase.thinking => (SaklazColors.violet, Icons.auto_awesome),
      VoicePhase.requestingPermission => (SaklazColors.warning, Icons.lock_open),
      VoicePhase.idle => (SaklazColors.textSecondary, Icons.mic_off),
    };
    final label = voice.phase == VoicePhase.idle ? 'Mikrofon kapalı' : phaseLabel(voice.phase);
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
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Büyük mikrofon düğmesi. Dinlerken yeşil ve nabız atar.
class MicButton extends StatelessWidget {
  const MicButton({super.key, required this.voice, required this.onPressed});
  final VoiceState voice;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final listening = voice.phase == VoicePhase.listening;
    final speaking = voice.phase == VoicePhase.speaking;
    final busy = voice.phase == VoicePhase.requestingPermission;
    final icon = listening ? Icons.stop_rounded : (speaking ? Icons.volume_off_rounded : Icons.mic_rounded);
    final tooltip = listening ? 'Dinlemeyi durdur' : (speaking ? 'Konuşmayı durdur' : 'Konuşmaya başla');

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: listening
                ? const LinearGradient(colors: [SaklazColors.listening, SaklazColors.cyan])
                : SaklazColors.brandGradient,
            boxShadow: [
              BoxShadow(
                color: (listening ? SaklazColors.listening : SaklazColors.violet)
                    .withValues(alpha: 0.25 + voice.level * 0.4),
                blurRadius: 24 + voice.level * 24,
                spreadRadius: 2 + voice.level * 8,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: busy ? null : onPressed,
              child: Icon(icon, size: 36, color: SaklazColors.background),
            ),
          ),
        ),
      ),
    );
  }
}
