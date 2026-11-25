import 'package:flutter/material.dart';

/// WavyHeaderDivider: Organic flowing wave separator styled after Loop app
class WavyHeaderDivider extends StatelessWidget {
  final double height;
  final Color waveColor;
  final double strokeWidth;

  const WavyHeaderDivider({
    super.key,
    this.height = 24,
    this.waveColor = const Color(0xFFCBE2F4),
    this.strokeWidth = 3.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WavyPainter(
          waveColor: waveColor,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _WavyPainter extends CustomPainter {
  final Color waveColor;
  final double strokeWidth;

  _WavyPainter({required this.waveColor, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path();
    const waveLength = 48.0;
    final waveCount = (size.width / waveLength).ceil() + 1;
    final midY = size.height / 2;

    path.moveTo(0, midY);
    for (int i = 0; i < waveCount; i++) {
      final startX = i * waveLength;
      path.quadraticBezierTo(
        startX + waveLength * 0.25,
        midY - 8,
        startX + waveLength * 0.5,
        midY,
      );
      path.quadraticBezierTo(
        startX + waveLength * 0.75,
        midY + 8,
        startX + waveLength,
        midY,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
