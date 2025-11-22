import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Beautiful SCN logo widget
class SCNLogo extends StatelessWidget {
  final double size;
  final bool showText;
  
  const SCNLogo({
    super.key,
    this.size = 80,
    this.showText = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF2196F3),
                      const Color(0xFF1976D2),
                      const Color(0xFF0D47A1),
                    ]
                  : [
                      const Color(0xFF1976D2),
                      const Color(0xFF1565C0),
                      const Color(0xFF0D47A1),
                    ],
            ),
            borderRadius: BorderRadius.circular(size * 0.25),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.blue : Colors.blue.shade700).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background pattern
              CustomPaint(
                size: Size(size, size),
                painter: _SCNPatternPainter(
                  color: Colors.white.withOpacity(0.15),
                ),
              ),
              // SCN Text
              Text(
                'SCN',
                style: TextStyle(
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: size * 0.02,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showText) ...[
          const SizedBox(height: 8),
          Text(
            'SCN',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              letterSpacing: 2,
            ),
          ),
        ],
      ],
    );
  }
}

/// Pattern painter for logo background
class _SCNPatternPainter extends CustomPainter {
  final Color color;

  _SCNPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw network connection pattern
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.3;

    // Outer circle
    canvas.drawCircle(center, radius, paint);

    // Inner circle
    canvas.drawCircle(center, radius * 0.6, paint);

    // Connection lines
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60) * 3.14159 / 180;
      final startX = center.dx + radius * 0.6 * math.cos(angle);
      final startY = center.dy + radius * 0.6 * math.sin(angle);
      final endX = center.dx + radius * math.cos(angle);
      final endY = center.dy + radius * math.sin(angle);
      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

