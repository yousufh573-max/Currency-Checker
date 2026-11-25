import 'package:material_ui/material_ui.dart';

/// Colours sampled from App design.pdf.
abstract final class AppColors {
  static const navy = Color(0xFF07152A);
  static const navyLight = Color(0xFF1B2C45);
  static const glassTop = Color(0x33FFFFFF);
  static const glassBottom = Color(0x14FFFFFF);
  static const glassBorder = Color(0xFFB8C8D8);
  static const ringBlue = Color(0xFF3A4BCB);
  static const brightBlue = Color(0xFF2340FF);
  static const micBlue = Color(0xFF2F6FE0);
  static const cyan = Color(0xFF2EB7EA);
  static const steel = Color(0xFF6D88A8);
  static const scanYellow = Color(0xFFFFD400);
  static const successGreen = Color(0xFF4CBF3A);
  static const successBorder = Color(0xFF138A3A);
  static const warningRed = Color(0xFFFF3B3B);
  static const neutralGrey = Color(0xFF8A9AA6);
  static const amber = Color(0xFFFFB020);
  static const cream = Color(0xFFF6F3E6);
  static const summaryBlue = Color(0xFF2B5BF5);
  static const summaryText = Color(0xFF1F4FB0);
  static const white = Colors.white;
}

abstract final class AppFonts {
  static const display = 'DMSerifDisplay';
  static const body = 'CrimsonPro';
  static const bengali = 'NotoSerifBengali';
  // Bengali text and the Taka sign (৳) fall back to Noto Serif Bengali.
  static const fallback = [bengali];
}

ThemeData buildTheme() {
  const base = TextStyle(fontFamily: AppFonts.body, fontFamilyFallback: AppFonts.fallback, color: AppColors.white);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.navy,
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.fallback,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.micBlue,
      secondary: AppColors.cyan,
      surface: AppColors.navy,
      error: AppColors.warningRed,
    ),
    textTheme: TextTheme(
      displayLarge: base.copyWith(fontFamily: AppFonts.display, fontSize: 44, height: 1.1),
      displayMedium: base.copyWith(fontFamily: AppFonts.display, fontSize: 36),
      headlineMedium: base.copyWith(fontSize: 32, fontWeight: FontWeight.w400),
      titleLarge: base.copyWith(fontSize: 26),
      bodyLarge: base.copyWith(fontSize: 21, height: 1.3),
      bodyMedium: base.copyWith(fontSize: 18, height: 1.3),
      labelLarge: base.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.navyLight),
    sliderTheme: const SliderThemeData(activeTrackColor: AppColors.cyan, thumbColor: AppColors.cyan),
  );
}

/// Taka amount text: "৳120".
String taka(int amount) => '৳$amount';
