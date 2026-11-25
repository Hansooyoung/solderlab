import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// AppLogo: Logo & Identitas Resmi SolderLab
class AppLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final double fontSize;

  const AppLogo({
    super.key,
    this.size = 36.0,
    this.showText = true,
    this.fontSize = 18.0,
  });

  @override
  Widget build(BuildContext context) {
    final iconBox = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.slateBlue,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2652738D),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/branding/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.bolt_rounded,
          color: Colors.white,
          size: size * 0.62,
        ),
      ),
    );

    if (!showText) {
      return iconBox;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        iconBox,
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SolderLab',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: AppTheme.slateBlueDark,
                letterSpacing: -0.4,
              ),
            ),
            const Text(
              'PENGENDALI MUTU SOLDER',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
