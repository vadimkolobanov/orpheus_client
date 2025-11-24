// lib/theme/app_theme.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color background = Color(0xFF050505);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color primarySilver = Color(0xFFB0BEC5);
  static const Color accentSilver = Color(0xFFECEFF1);
  static const Color textWhite = Color(0xFFEEEEEE);
  static const Color textGrey = Color(0xFFAAAAAA);
  static const Color errorRed = Color(0xFFCF6679);

  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark();

    return baseTheme.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primarySilver,
        onPrimary: Colors.black,
        secondary: accentSilver,
        surface: surface,
        onSurface: textWhite,
        error: errorRed,
      ),

      // ТИПОГРАФИКА
      textTheme: GoogleFonts.robotoTextTheme(baseTheme.textTheme).copyWith(
        titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textWhite),
        titleMedium: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textWhite),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.4, color: textWhite),
        bodyMedium: const TextStyle(fontSize: 14, color: textGrey),
      ),

      // APP BAR
      appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: primarySilver,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: primarySilver,
            letterSpacing: 1.5,
          )
      ),

      // КАРТОЧКИ
      cardTheme: CardThemeData(
        color: surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      ),

      // ДИАЛОГИ (ИСПРАВЛЕНИЕ БЕЛОГО ТЕКСТА)
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF202020), // Темно-серый фон
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: primarySilver, width: 0.5)
        ),
        titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primarySilver),
        contentTextStyle: const TextStyle(color: textWhite, fontSize: 16),
      ),

      // ПОЛЯ ВВОДА
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF121212),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primarySilver, width: 1.5),
        ),
      ),

      // КНОПКИ
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primarySilver,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          )
      ),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: primarySilver)
      ),
      iconTheme: const IconThemeData(color: primarySilver),
    );
  }
}