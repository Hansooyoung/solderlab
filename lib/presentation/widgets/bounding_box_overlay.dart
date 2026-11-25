import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/bounding_box.dart';
import '../../data/models/inspection_joint_model.dart';

/// Overlay Bounding Box Interaktif untuk Kamera & Review Hasil
class BoundingBoxOverlay extends StatelessWidget {
  final List<NormalizedBoundingBox> boxes;
  final List<InspectionJointModel>? inspectedJoints;
  final Function(int index)? onBoxTapped;

  const BoundingBoxOverlay({
    super.key,
    required this.boxes,
    this.inspectedJoints,
    this.onBoxTapped,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

        return CustomPaint(
          size: canvasSize,
          painter: _BoundingBoxPainter(
            boxes: boxes,
            inspectedJoints: inspectedJoints,
            canvasSize: canvasSize,
          ),
        );
      },
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  final List<NormalizedBoundingBox> boxes;
  final List<InspectionJointModel>? inspectedJoints;
  final Size canvasSize;

  _BoundingBoxPainter({
    required this.boxes,
    this.inspectedJoints,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final rect = box.toPixelRect(canvasSize);

      Color boxColor = const Color(0xFF00E5FF);
      String label = 'PAD #${i + 1}';

      if (inspectedJoints != null && i < inspectedJoints!.length) {
        final joint = inspectedJoints![i];
        if (joint.isPass) {
          boxColor = AppTheme.passGreen;
          label = '#${joint.jointIndex} PASS';
        } else if (joint.isFail) {
          boxColor = AppTheme.failRed;
          label = '#${joint.jointIndex} ${joint.defectType?.defectCode ?? "FAIL"}';
        } else {
          boxColor = AppTheme.uncertainYellow;
          label = '#${joint.jointIndex} ?';
        }
      }

      // Draw box border
      final paint = Paint()
        ..color = boxColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawRect(rect, paint);

      // Draw label background
      final isWhite = boxColor == Colors.white || (boxColor.r >= 0.95 && boxColor.g >= 0.95 && boxColor.b >= 0.95);
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: isWhite ? Colors.black : Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final bgRect = Rect.fromLTWH(
        rect.left,
        rect.top - 15,
        textPainter.width + 6,
        14,
      );

      final bgPaint = Paint()..color = boxColor;
      canvas.drawRect(bgRect, bgPaint);
      textPainter.paint(canvas, Offset(rect.left + 3, rect.top - 14));
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return true;
  }
}
