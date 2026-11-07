import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:saklaz_voice/saklaz_voice.dart';

import '../theme/saklaz_theme.dart';

/// Animasyonlu AI küresi. Duruma göre renk, nefes alma hızı ve dalga
/// genliği değişir; dinlerken mikrofon seviyesine tepki verir.
class AiOrb extends StatefulWidget {
  const AiOrb({super.key, required this.phase, this.level = 0, this.size = 240});

  final VoicePhase phase;

  /// 0..1 mikrofon seviyesi.
  final double level;
  final double size;

  @override
  State<AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<AiOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  double _smoothedLevel = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion && _ctrl.isAnimating) _ctrl.stop();
    if (!reduceMotion && !_ctrl.isAnimating) _ctrl.repeat();

    return Semantics(
      label: 'SAKLAZ küresi: ${phaseLabel(widget.phase)}',
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              _smoothedLevel += (widget.level - _smoothedLevel) * 0.25;
              return CustomPaint(
                painter: _OrbPainter(
                  t: _ctrl.value * 2 * math.pi,
                  phase: widget.phase,
                  level: _smoothedLevel,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

String phaseLabel(VoicePhase p) => switch (p) {
      VoicePhase.idle => 'Hazır',
      VoicePhase.requestingPermission => 'İzin bekleniyor',
      VoicePhase.listening => 'Dinliyor',
      VoicePhase.thinking => 'Düşünüyor',
      VoicePhase.speaking => 'Konuşuyor',
    };

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.t, required this.phase, required this.level});

  final double t;
  final VoicePhase phase;
  final double level;

  (Color, Color, double speed, double amp) get _style => switch (phase) {
        VoicePhase.idle => (SaklazColors.cyan, SaklazColors.violet, 1.0, 0.04),
        VoicePhase.requestingPermission => (SaklazColors.warning, SaklazColors.violet, 1.0, 0.03),
        VoicePhase.listening => (SaklazColors.listening, SaklazColors.cyan, 3.0, 0.06 + level * 0.16),
        VoicePhase.thinking => (SaklazColors.violet, SaklazColors.magenta, 5.0, 0.05),
        VoicePhase.speaking => (SaklazColors.speaking, SaklazColors.magenta, 4.0, 0.09),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final (a, b, speed, amp) = _style;
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    final breathe = 1 + 0.025 * math.sin(t * speed);
    final r = maxR * 0.62 * breathe;

    // Dış hale
    canvas.drawCircle(
      c,
      maxR,
      Paint()
        ..shader = RadialGradient(
          colors: [a.withValues(alpha: 0.28 + level * 0.2), b.withValues(alpha: 0.08), Colors.transparent],
          stops: const [0.45, 0.75, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: maxR)),
    );

    // Dalgalı yörünge halkaları
    for (var ring = 0; ring < 3; ring++) {
      final path = Path();
      const steps = 120;
      for (var i = 0; i <= steps; i++) {
        final ang = i / steps * 2 * math.pi;
        final wobble = amp *
            (math.sin(ang * (3 + ring) + t * speed * (1 + ring * 0.3)) +
                0.5 * math.sin(ang * (5 + ring) - t * speed * 0.7));
        final rr = r * (1.08 + ring * 0.09 + wobble);
        final p = c + Offset(math.cos(ang) * rr, math.sin(ang) * rr);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 - ring * 0.4
          ..color = Color.lerp(a, b, ring / 2)!.withValues(alpha: 0.65 - ring * 0.18),
      );
    }

    // Çekirdek küre
    final core = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [a, b, SaklazColors.magenta.withValues(alpha: 0.9), a],
          transform: GradientRotation(t * speed * 0.25),
        ).createShader(core),
    );
    // Hacim için iç gölge / parlama
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.45)],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(core),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.t != t || old.phase != phase || old.level != level;
}
