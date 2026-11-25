import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// StatusBadge: Badge Status Hasil Inspeksi SolderLab (LULUS / REWORK / REVIEW)
class StatusChip extends StatelessWidget {
  final String status;
  final double fontSize;
  final bool useIndonesian;

  const StatusChip({
    super.key,
    required this.status,
    this.fontSize = 11.0,
    this.useIndonesian = true,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color text;
    String label;

    final normalized = status.toUpperCase();
    if (normalized == 'PASS' || normalized == 'LULUS' || normalized == 'OPTIMAL') {
      bg = AppTheme.passBadgeBg;
      border = AppTheme.passBadgeBorder;
      text = AppTheme.passBadgeText;
      label = useIndonesian ? 'LULUS' : 'PASS';
    } else if (normalized == 'FAIL' || normalized == 'REWORK' || normalized == 'CACAT') {
      bg = AppTheme.reworkBadgeBg;
      border = AppTheme.reworkBadgeBorder;
      text = AppTheme.reworkBadgeText;
      label = useIndonesian ? 'REWORK' : 'REWORK';
    } else {
      bg = const Color(0xFFFEF3C7);
      border = const Color(0xFFFDE68A);
      text = const Color(0xFFB45309);
      label = useIndonesian ? 'TINJAU' : 'REVIEW';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
