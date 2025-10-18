// lib/src/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  // Brand palette
  static const int _primaryHex = 0xFF00426A; // dark brand blue
  static const int _onSurfaceHex = 0xFFB2B4B3; // light grey text
  static const int _accentHex = 0xFFF1C400; // sparing accent (yellow)

  static ThemeData dark() {
    final seed = const Color(_primaryHex);

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
    );

    final cs = base.colorScheme.copyWith(
      primary: seed,
      onPrimary: Colors.white,
      surface: seed, // use brand blue as surfaces
      onSurface: const Color(_onSurfaceHex),
      secondary: const Color(_accentHex),
      onSecondary: Colors.black,
    );

    return base.copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      canvasColor: cs.surface,

      // <-- This is the line that fixes your build error
      cardTheme: CardThemeData(
        color: cs.surface,
        elevation: 1,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),

      listTileTheme: ListTileThemeData(
        textColor: cs.onSurface,
        iconColor: cs.onSurface,
        subtitleTextStyle: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.85),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurface,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 20,
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cs.secondary, // accent
          foregroundColor: cs.onSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surface.withValues(alpha: 0.25),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.secondary, width: 1.5),
        ),
        labelStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.9)),
        hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
      ),

      dividerTheme: DividerThemeData(
        color: cs.onSurface.withValues(alpha: 0.2),
        thickness: 1,
      ),
    );
  }
}
