import 'package:flutter/material.dart';

/// AppTheme: Sistem Desain Resmi SolderLab
/// Tema Warm Eggshell & Soft Sky (#FAF8EE, #52738D, #CBE2F4, #FFFFFF)
class AppTheme {
  // 1. Palet Warna Resmi SolderLab
  static const Color warmEggshell = Color(0xFFFAF8EE); // Latar Belakang Hangat Utama
  static const Color slateBlue = Color(0xFF52738D); // Brand Utama, Header, & Dock
  static const Color slateBlueDark = Color(0xFF3C566D); // Teks Judul Pekat
  static const Color slateBlueDeep = Color(0xFF283F52); // Teks Sangat Kontras
  static const Color softSky = Color(0xFFCBE2F4); // Kontainer Aksen Lembut & Kartu Lulus
  static const Color softSkyBorder = Color(0xFFA8CCE8); // Garis Tepi Kartu (1px Border)
  static const Color surfaceWhite = Color(0xFFFFFFFF); // Permukaan Kartu Putih Bersih

  // 2. Teks & Tipografi
  static const Color textPrimary = Color(0xFF283F52); // Teks Utama Gelap Kontras
  static const Color textSecondary = Color(0xFF52738D); // Teks Sekunder Slate
  static const Color textMuted = Color(0xFF6B8EA9); // Teks Redup / Hint
  static const Color textInverse = Color(0xFFFFFFFF); // Teks Terang di atas Slate

  // 3. Status Badges (LULUS & REWORK)
  static const Color passBadgeBg = Color(0xFFCBE2F4);
  static const Color passBadgeBorder = Color(0xFFA8CCE8);
  static const Color passBadgeText = Color(0xFF2A506E);

  static const Color reworkBadgeBg = Color(0xFFFFEAEA);
  static const Color reworkBadgeBorder = Color(0xFFFFBFBF);
  static const Color reworkBadgeText = Color(0xFFD32F2F);

  // Status Colors Tambahan untuk Diagram & Logika
  static const Color passGreen = Color(0xFF2E7D32);
  static const Color failRed = Color(0xFFD32F2F);
  static const Color uncertainYellow = Color(0xFFF59E0B);

  // Fallback dark palette untuk kompatibilitas kamera HUD
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
  static const Color accentBlue = Color(0xFF38BDF8);

  // Dekorasi Kartu Standar SolderLab
  static BoxDecoration cardDecoration({
    Color backgroundColor = surfaceWhite,
    Color borderColor = softSkyBorder,
    double radius = 16.0,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 1.0),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1452738D),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    );
  }

  // Tema Resmi SolderLab
  static ThemeData get solderLabTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: warmEggshell,
      colorScheme: const ColorScheme.light(
        primary: slateBlue,
        secondary: softSky,
        surface: surfaceWhite,
        error: failRed,
        onPrimary: textInverse,
        onSurface: textPrimary,
      ),
      fontFamily: 'Segoe UI',
      appBarTheme: const AppBarTheme(
        backgroundColor: warmEggshell,
        foregroundColor: slateBlue,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: slateBlue,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: slateBlue),
      ),
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: softSkyBorder, width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      dividerTheme: const DividerThemeData(
        color: softSkyBorder,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: slateBlue,
          foregroundColor: textInverse,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: slateBlue,
          side: const BorderSide(color: softSkyBorder, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  // Alias lightTheme mengarah ke solderLabTheme
  static ThemeData get lightTheme => solderLabTheme;
  static ThemeData get darkTheme => solderLabTheme;
}
