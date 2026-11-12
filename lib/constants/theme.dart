import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    // Neo-Brutalist: Space Grotesk for massive headlines, Inter for functional body
    final spaceGrotesk = GoogleFonts.spaceGrotesk();
    final inter = GoogleFonts.inter();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.white,
        secondary: AppColors.accentYellow,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
      // Typography - Bauhaus brutal
      fontFamily: inter.fontFamily,
      textTheme: TextTheme(
        // Headlines: oversized, geometric, bold (Space Grotesk)
        displayLarge: spaceGrotesk.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: AppColors.textMain,
          letterSpacing: -1.0,
        ),
        displayMedium: spaceGrotesk.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textMain,
        ),
        displaySmall: spaceGrotesk.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textMain,
        ),
        // Body: functional Inter
        bodyLarge: inter.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.textMain,
        ),
        bodyMedium: inter.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textMain,
        ),
        // Label / small
        labelSmall: inter.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        // For buttons (uppercase brutal)
        labelLarge: inter.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.white,
          letterSpacing: 1.2,
        ),
      ),
      // === BRUTALIST APPBAR (raw, high contrast) ===
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: spaceGrotesk.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppColors.white,
          letterSpacing: -0.5,
        ),
      ),

      // === BRUTALIST BUTTONS: thick border, 0 radius, solid offset shadow, uppercase ===
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentYellow,
          foregroundColor: AppColors.primary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: AppColors.brutalBorder,
          ),
          minimumSize: const Size(44, 44),
          shadowColor: Colors.transparent,
        ).copyWith(
          // Add solid offset on press for brutal feel (can enhance with Ink)
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: AppColors.brutalBorder,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          minimumSize: const Size(44, 44),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentBlue,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),

      // === BRUTALIST INPUTS: box with thick border, 0 radius ===
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: AppColors.primary, width: 2.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: AppColors.accentYellow, width: 3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: AppColors.danger, width: 2.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        labelStyle: inter.copyWith(color: AppColors.textSecondary),
      ),

      // Bottom nav brutal
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
      ),

      // === BRUTALIST CARDS: thick border + solid offset shadow, ZERO radius ===
      cardTheme: CardTheme(
        color: AppColors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        margin: const EdgeInsets.all(0),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: AppColors.brutalBorder,
        ),
      ).copyWith(
        // Force brutal shadow on all cards
      ),

      // Divider brutal
      dividerTheme: const DividerThemeData(
        color: AppColors.primary,
        thickness: 2,
        space: 16,
      ),
    );
  }
}
