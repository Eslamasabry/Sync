import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class ReaderPalette extends ThemeExtension<ReaderPalette> {
  const ReaderPalette({
    required this.backgroundBase,
    required this.backgroundElevated,
    required this.backgroundChrome,
    required this.textPrimary,
    required this.textMuted,
    required this.accentPrimary,
    required this.accentSoft,
    required this.borderSubtle,
    required this.shellGlow,
    required this.shellShadow,
    required this.success,
    required this.error,
  });

  final Color backgroundBase;
  final Color backgroundElevated;
  final Color backgroundChrome;
  final Color textPrimary;
  final Color textMuted;
  final Color accentPrimary;
  final Color accentSoft;
  final Color borderSubtle;
  final Color shellGlow;
  final Color shellShadow;
  final Color success;
  final Color error;

  static ReaderPalette of(BuildContext context) {
    return Theme.of(context).extension<ReaderPalette>()!;
  }

  @override
  ReaderPalette copyWith({
    Color? backgroundBase,
    Color? backgroundElevated,
    Color? backgroundChrome,
    Color? textPrimary,
    Color? textMuted,
    Color? accentPrimary,
    Color? accentSoft,
    Color? borderSubtle,
    Color? shellGlow,
    Color? shellShadow,
    Color? success,
    Color? error,
  }) {
    return ReaderPalette(
      backgroundBase: backgroundBase ?? this.backgroundBase,
      backgroundElevated: backgroundElevated ?? this.backgroundElevated,
      backgroundChrome: backgroundChrome ?? this.backgroundChrome,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentSoft: accentSoft ?? this.accentSoft,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      shellGlow: shellGlow ?? this.shellGlow,
      shellShadow: shellShadow ?? this.shellShadow,
      success: success ?? this.success,
      error: error ?? this.error,
    );
  }

  @override
  ReaderPalette lerp(ThemeExtension<ReaderPalette>? other, double t) {
    if (other is! ReaderPalette) {
      return this;
    }
    return ReaderPalette(
      backgroundBase: Color.lerp(backgroundBase, other.backgroundBase, t)!,
      backgroundElevated: Color.lerp(
        backgroundElevated,
        other.backgroundElevated,
        t,
      )!,
      backgroundChrome: Color.lerp(
        backgroundChrome,
        other.backgroundChrome,
        t,
      )!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      shellGlow: Color.lerp(shellGlow, other.shellGlow, t)!,
      shellShadow: Color.lerp(shellShadow, other.shellShadow, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

class SyncTheme {
  static ThemeData paper() {
    const palette = ReaderPalette(
      backgroundBase: Color(0xFFF3EDE1),
      backgroundElevated: Color(0xFFFFFBF3),
      backgroundChrome: Color(0xFFE8DED0),
      textPrimary: Color(0xFF1C140E),
      textMuted: Color(0xFF54463A),
      accentPrimary: Color(0xFFB56B1F),
      accentSoft: Color(0xFFE7C28F),
      borderSubtle: Color(0xFFD3C2A6),
      shellGlow: Color(0xFFE6C08F),
      shellShadow: Color(0x22160F08),
      success: Color(0xFF3F6B45),
      error: Color(0xFFA33A2B),
    );
    return _buildTheme(brightness: Brightness.light, palette: palette);
  }

  static ThemeData night() {
    const palette = ReaderPalette(
      backgroundBase: Color(0xFF11100E),
      backgroundElevated: Color(0xFF1A1714),
      backgroundChrome: Color(0xFF0D0C0A),
      textPrimary: Color(0xFFF3E6CE),
      textMuted: Color(0xFFD2BF9E),
      accentPrimary: Color(0xFFE5A158),
      accentSoft: Color(0xFF4A341F),
      borderSubtle: Color(0xFF332A22),
      shellGlow: Color(0x664A341F),
      shellShadow: Color(0x66000000),
      success: Color(0xFF74A07B),
      error: Color(0xFFD47466),
    );
    return _buildTheme(brightness: Brightness.dark, palette: palette);
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ReaderPalette palette,
  }) {
    final baseText = GoogleFonts.sourceSerif4TextTheme();
    final uiText = GoogleFonts.ibmPlexSansTextTheme(baseText);
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: palette.accentPrimary,
      onPrimary: palette.backgroundElevated,
      secondary: palette.accentSoft,
      onSecondary: palette.textPrimary,
      error: palette.error,
      onError: palette.backgroundElevated,
      surface: palette.backgroundElevated,
      onSurface: palette.textPrimary,
      tertiary: palette.success,
      onTertiary: palette.backgroundElevated,
      outline: palette.borderSubtle,
      surfaceContainerHighest: palette.backgroundBase,
      shadow: Colors.black.withValues(alpha: 0.16),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.backgroundBase,
      canvasColor: palette.backgroundChrome,
      textTheme: uiText.copyWith(
        displayLarge: GoogleFonts.fraunces(
          textStyle: uiText.displayLarge,
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        displayMedium: GoogleFonts.fraunces(
          textStyle: uiText.displayMedium,
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        displaySmall: GoogleFonts.fraunces(
          textStyle: uiText.displaySmall,
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
          height: 0.98,
        ),
        headlineLarge: GoogleFonts.fraunces(
          textStyle: uiText.headlineLarge,
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
          height: 1.02,
        ),
        headlineMedium: GoogleFonts.fraunces(
          textStyle: uiText.headlineMedium,
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: GoogleFonts.fraunces(
          textStyle: uiText.headlineSmall,
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.ibmPlexSans(
          textStyle: uiText.titleLarge,
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: GoogleFonts.ibmPlexSans(
          textStyle: uiText.titleMedium,
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        titleSmall: GoogleFonts.ibmPlexSans(
          textStyle: uiText.titleSmall,
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
        ),
        bodyLarge: GoogleFonts.sourceSerif4(
          textStyle: uiText.bodyLarge,
          color: palette.textPrimary,
          height: 1.68,
          fontSize: 22,
        ),
        bodyMedium: GoogleFonts.sourceSerif4(
          textStyle: uiText.bodyMedium,
          color: palette.textPrimary,
          height: 1.62,
          fontSize: 18,
        ),
        bodySmall: GoogleFonts.ibmPlexSans(
          textStyle: uiText.bodySmall,
          color: palette.textMuted,
          height: 1.45,
          fontSize: 13,
        ),
        labelLarge: GoogleFonts.ibmPlexSans(
          textStyle: uiText.labelLarge,
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: GoogleFonts.ibmPlexSans(
          textStyle: uiText.labelMedium,
          color: palette.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.backgroundElevated,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.borderSubtle),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.borderSubtle.withValues(alpha: 0.55),
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.backgroundElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 78,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.ibmPlexSans(
            color: selected ? palette.textPrimary : palette.textMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 12.5,
            letterSpacing: 0.2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? palette.textPrimary : palette.textMuted,
            size: 22,
          );
        }),
        indicatorColor: palette.accentSoft.withValues(alpha: 0.85),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.textPrimary,
          foregroundColor: palette.backgroundElevated,
          textStyle: GoogleFonts.ibmPlexSans(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.borderSubtle),
          textStyle: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.backgroundChrome,
        selectedColor: palette.accentSoft,
        disabledColor: palette.backgroundChrome.withValues(alpha: 0.7),
        side: BorderSide(color: palette.borderSubtle),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelStyle: GoogleFonts.ibmPlexSans(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: GoogleFonts.ibmPlexSans(
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.textPrimary,
        contentTextStyle: GoogleFonts.ibmPlexSans(
          color: palette.backgroundElevated,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.backgroundChrome.withValues(alpha: 0.88),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: palette.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: palette.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: palette.accentPrimary, width: 1.4),
        ),
        hintStyle: GoogleFonts.ibmPlexSans(color: palette.textMuted),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accentPrimary,
        thumbColor: palette.accentPrimary,
        inactiveTrackColor: palette.accentSoft,
        overlayColor: palette.accentSoft.withValues(alpha: 0.22),
      ),
      extensions: [palette],
    );
  }
}
