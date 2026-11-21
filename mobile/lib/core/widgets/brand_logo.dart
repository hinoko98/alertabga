import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Escudo con mapa y pin (identidad AlertaBGA), dibujado sin dependencias externas.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AlertaBGA',
      child: CustomPaint(size: Size.square(size), painter: _ShieldPainter()),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48;
    canvas.scale(s);

    final shield = Path()
      ..moveTo(24, 3)
      ..lineTo(6, 9.5)
      ..lineTo(6, 22.7)
      ..cubicTo(6, 34.3, 13.7, 42.6, 24, 45)
      ..cubicTo(34.3, 42.6, 42, 34.3, 42, 22.7)
      ..lineTo(42, 9.5)
      ..close();
    canvas.drawPath(shield, Paint()..color = BrandColors.navy900);

    final grid = Paint()
      ..color = BrandColors.cyan.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final y in [20.5, 28.0]) {
      canvas.drawLine(Offset(11, y), Offset(37, y), grid);
    }
    for (final x in [19.0, 29.0]) {
      canvas.drawLine(Offset(x, 12), Offset(x, 40), grid);
    }

    final pin = Path()
      ..moveTo(24, 13.5)
      ..cubicTo(19.9, 13.5, 16.7, 16.7, 16.7, 20.7)
      ..cubicTo(16.7, 26, 24, 33.7, 24, 33.7)
      ..cubicTo(24, 33.7, 31.3, 26, 31.3, 20.7)
      ..cubicTo(31.3, 16.7, 28.1, 13.5, 24, 13.5)
      ..close();
    canvas.drawPath(pin, Paint()..color = BrandColors.cyan);
    canvas.drawCircle(const Offset(24, 20.7), 2.8, Paint()..color = BrandColors.amber);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
