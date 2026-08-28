import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppThemeMode {
  dark,
  light,
  system,
  sepia,
  warm,
}

class AppThemeColors {
  final Color background;
  final Color cardBackground;
  final Color elevatedBackground;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color primary;
  final Color accent;
  final Brightness brightness;

  const AppThemeColors({
    required this.background,
    required this.cardBackground,
    required this.elevatedBackground,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.accent,
    required this.brightness,
  });
}

class AppTheme {
  // Brand Colors (Compatibility)
  static const Color primary = Color(0xFF6366F1); // Indigo
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color primaryLight = Color(0xFF38BDF8); // Cyan Accent
  
  static const Color secondary = Color(0xFF8B5CF6); // Purple
  static const Color accent = Color(0xFF10B981); // Emerald Green
  static const Color accentOrange = Color(0xFFF59E0B); // Amber
  static const Color accentRose = Color(0xFFF43F5E); // Rose
  
  // Backgrounds & Surfaces (Default Dark Theme)
  static const Color background = Color(0xFF0A0F1D);
  static const Color surface = Color(0xFF0F172A);
  static const Color surfaceLight = Color(0xFF1E293B);
  static const Color cardBg = Color(0xFF0F172A);
  
  // Borders & Dividers
  static const Color border = Color(0xFF1E293B);
  static const Color borderGlow = Color(0xFF38BDF8);

  // Text Colors
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFFCBD5E1);
  static const Color textMuted = Color(0xFF94A3B8);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFA855F7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient audioWaveGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF6366F1), Color(0xFFEC4899)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // 1. Dark Theme Colors
  static const darkColors = AppThemeColors(
    background: Color(0xFF0A0F1D),
    cardBackground: Color(0xFF0F172A),
    elevatedBackground: Color(0xFF1E293B),
    border: Color(0xFF233254),
    textPrimary: Colors.white,
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    primary: Color(0xFF38BDF8),
    accent: Color(0xFFF59E0B),
    brightness: Brightness.dark,
  );

  // 2. Light Theme Colors
  static const lightColors = AppThemeColors(
    background: Color(0xFFF8FAFC),
    cardBackground: Color(0xFFFFFFFF),
    elevatedBackground: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF334155),
    textMuted: Color(0xFF64748B),
    primary: Color(0xFF0284C7),
    accent: Color(0xFFD97706),
    brightness: Brightness.light,
  );

  // 3. Sepia Theme Colors (Giấy ngà vàng dịu mắt đọc tiểu thuyết)
  static const sepiaColors = AppThemeColors(
    background: Color(0xFFF4ECD8),
    cardBackground: Color(0xFFFAF4E8),
    elevatedBackground: Color(0xFFEFE4C8),
    border: Color(0xFFD7C9A8),
    textPrimary: Color(0xFF2C1810),
    textSecondary: Color(0xFF4A3525),
    textMuted: Color(0xFF8D7B68),
    primary: Color(0xFF8B5E3C),
    accent: Color(0xFFC05621),
    brightness: Brightness.light,
  );

  // 4. Warm Theme Colors (Ấm áp chống mỏi mắt ban đêm)
  static const warmColors = AppThemeColors(
    background: Color(0xFF18120A),
    cardBackground: Color(0xFF231B10),
    elevatedBackground: Color(0xFF332717),
    border: Color(0xFF4A3822),
    textPrimary: Color(0xFFFEF3C7),
    textSecondary: Color(0xFFFDE68A),
    textMuted: Color(0xFFD97706),
    primary: Color(0xFFF59E0B),
    accent: Color(0xFFF97316),
    brightness: Brightness.dark,
  );

  static AppThemeColors getColors(AppThemeMode mode, [BuildContext? context]) {
    switch (mode) {
      case AppThemeMode.light:
        return lightColors;
      case AppThemeMode.dark:
        return darkColors;
      case AppThemeMode.sepia:
        return sepiaColors;
      case AppThemeMode.warm:
        return warmColors;
      case AppThemeMode.system:
        final brightness = (context != null)
            ? MediaQuery.maybeOf(context)?.platformBrightness ?? Brightness.dark
            : WidgetsBinding.instance.platformDispatcher.platformBrightness;
        return brightness == Brightness.light ? lightColors : darkColors;
    }
  }

  static ThemeData getThemeData(AppThemeMode mode, [BuildContext? context]) {
    final colors = getColors(mode, context);
    final isDark = colors.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: colors.brightness,
      scaffoldBackgroundColor: colors.background,
      primaryColor: colors.primary,
      colorScheme: ColorScheme(
        brightness: colors.brightness,
        primary: colors.primary,
        onPrimary: isDark ? Colors.black : Colors.white,
        secondary: secondary,
        onSecondary: Colors.white,
        surface: colors.cardBackground,
        onSurface: colors.textPrimary,
        error: accentRose,
        onError: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: colors.cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border, width: 1),
        ),
      ),
    );
  }

  /// Helper lấy TextStyle tương ứng với fontFamily được chọn
  static TextStyle getStoryTextStyle({
    required String fontFamily,
    required double fontSize,
    Color? color,
    FontWeight? fontWeight,
    double? height,
  }) {
    try {
      return GoogleFonts.getFont(
        fontFamily,
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        height: height,
      );
    } catch (_) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        height: height,
      );
    }
  }
}
