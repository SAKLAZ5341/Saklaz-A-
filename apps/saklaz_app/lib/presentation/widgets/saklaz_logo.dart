import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/saklaz_theme.dart';

/// SAKLAZ amblemi: yörüngeli halka içinde stilize "S" dalgası (ses dalgası +
/// baş harf). Vektörel çizilir; her boyutta keskindir.
class SaklazMark extends StatelessWidget {
  const SaklazMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _MarkPainter()));
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final shader = SaklazColors.brandGradient.createShader(rect);

    final ring = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(r * 0.08), -math.pi * 0.35, math.pi * 1.55, false, ring);

    final s = Path()
      ..moveTo(c.dx + r * 0.38, c.dy - r * 0.34)
      ..cubicTo(c.dx + r * 0.1, c.dy - r * 0.62, c.dx - r * 0.5, c.dy - r * 0.4, c.dx - r * 0.3, c.dy - r * 0.08)
      ..cubicTo(c.dx - r * 0.12, c.dy + r * 0.18, c.dx + r * 0.5, c.dy + r * 0.05, c.dx + r * 0.32, c.dy + r * 0.36)
      ..cubicTo(c.dx + r * 0.16, c.dy + r * 0.62, c.dx - r * 0.3, c.dy + r * 0.52, c.dx - r * 0.42, c.dy + r * 0.3);
    canvas.drawPath(
      s,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(c.dx + r * 0.62, c.dy - r * 0.62),
      r * 0.09,
      Paint()..color = SaklazColors.cyan,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Amblem + "SAKLAZ" yazısı.
class SaklazWordmark extends StatelessWidget {
  const SaklazWordmark({super.key, this.height = 28});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SaklazMark(size: height),
        SizedBox(width: height * 0.35),
        ShaderMask(
          shaderCallback: SaklazColors.brandGradient.createShader,
          child: Text(
            'SAKLAZ',
            style: TextStyle(
              fontSize: height * 0.72,
              fontWeight: FontWeight.w800,
              letterSpacing: height * 0.16,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
