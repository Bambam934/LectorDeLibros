import 'package:flutter/material.dart';

/// Brand mark — open-book + sound-wave glyph on a tinted rounded square.
class BrandedLogo extends StatelessWidget {
  const BrandedLogo({this.size = 72, this.compact = false, super.key});

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: CustomPaint(painter: _BrandPainter(color: scheme.onPrimary)),
    );

    if (compact) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(height: 16),
        Text(
          'LectorSync',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Lee, escucha, sincroniza.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BrandPainter extends CustomPainter {
  _BrandPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045
      ..strokeCap = StrokeCap.round;

    // Open book — two diagonal lines forming a "V"
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.28;

    // Left page
    canvas.drawLine(Offset(cx - r, cy + r * 0.3), Offset(cx, cy - r * 0.4),
        paint);
    // Right page
    canvas.drawLine(Offset(cx + r, cy + r * 0.3), Offset(cx, cy - r * 0.4),
        paint);
    // Spine
    canvas.drawLine(
        Offset(cx, cy - r * 0.4), Offset(cx, cy + r * 0.6), paint);

    // Sound wave dots above the book
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final dotR = size.width * 0.04;
    for (int i = 0; i < 3; i++) {
      final dx = cx - r - size.width * 0.12 + i * dotR * 2.4;
      canvas.drawCircle(
        Offset(dx, cy - r * 0.7),
        dotR * (1 - i * 0.15),
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BrandPainter old) => old.color != color;
}
