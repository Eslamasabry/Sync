import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class ReaderPalette extends ThemeExtension<ReaderPalette> {
  const ReaderPalette({
    required this.backgroundBase,
    required this.backgroundElevated,
    required this.textPrimary,
    required this.textMuted,
    required this.accentPrimary,
    required this.accentSoft,
    required this.borderSubtle,
    required this.success,
    required this.error,
  });

  final Color backgroundBase;
  final Color backgroundElevated;
  final Color textPrimary;
  final Color textMuted;
  final Color accentPrimary;
  final Color accentSoft;
  final Color borderSubtle;
  final Color success;
  final Color error;

  static ReaderPalette of(BuildContext context) {
    return Theme.of(context).extension<ReaderPalette>()!;
  }

  @override
  ReaderPalette copyWith({
    Color? backgroundBase,
    Color? backgroundElevated,
    Color? textPrimary,
    Color? textMuted,
    Color? accentPrimary,
    Color? accentSoft,
    Color? borderSubtle,
    Color? success,
    Color? error,
  }) {
    return ReaderPalette(
      backgroundBase: backgroundBase ?? this.backgroundBase,
      backgroundElevated: backgroundElevated ?? this.backgroundElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentSoft: accentSoft ?? this.accentSoft,
      borderSubtle: borderSubtle ?? this.borderSubtle,
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
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

class SyncTheme {
  static ThemeData paper() {
    const palette = ReaderPalette(
      backgroundBase: Color(0xFFF6F0E2),
      backgroundElevated: Color(0xFFFFF9ED),
      textPrimary: Color(0xFF241A12),
      textMuted: Color(0xFF6A5849),
      accentPrimary: Color(0xFFB8742A),
      accentSoft: Color(0xFFE6C79B),
      borderSubtle: Color(0xFFD8C8AE),
      success: Color(0xFF3F6B45),
      error: Color(0xFFA33A2B),
    );
    return _buildTheme(brightness: Brightness.light, palette: palette);
  }

  static ThemeData night() {
    const palette = ReaderPalette(
      backgroundBase: Color(0xFF171411),
      backgroundElevated: Color(0xFF211C17),
      textPrimary: Color(0xFFF4E7CF),
      textMuted: Color(0xFFC6B79E),
      accentPrimary: Color(0xFFE29A47),
      accentSoft: Color(0xFF5B4327),
      borderSubtle: Color(0xFF3D332A),
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
        headlineMedium: GoogleFonts.fraunces(
          textStyle: uiText.headlineMedium,
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.ibmPlexSans(
          textStyle: uiText.titleLarge,
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.sourceSerif4(
          textStyle: uiText.bodyLarge,
          color: palette.textPrimary,
          height: 1.5,
          fontSize: 20,
        ),
        bodyMedium: GoogleFonts.sourceSerif4(
          textStyle: uiText.bodyMedium,
          color: palette.textPrimary,
          height: 1.5,
          fontSize: 18,
        ),
        labelLarge: GoogleFonts.ibmPlexSans(
          textStyle: uiText.labelLarge,
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
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
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accentPrimary,
        thumbColor: palette.accentPrimary,
        inactiveTrackColor: palette.accentSoft,
      ),
      extensions: [palette],
    );
  }
}
