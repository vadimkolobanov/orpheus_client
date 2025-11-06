// lib/theme/app_theme.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // --- Наши цветовые константы ---
  static const Color primaryColor = Color(0xFF2B4F60);    // Глубокий сине-зеленый
  static const Color backgroundColor = Color(0xFFF2F5F7); // Светло-серый фон
  static const Color surfaceColor = Colors.white;         // Цвет карточек
  static const Color textColor = Color(0xFF1E2022);       // Основной темный текст

  // --- Наша светлая тема ---
  static ThemeData get lightTheme {
    final baseTheme = ThemeData.light();

    return baseTheme.copyWith(
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: baseTheme.colorScheme.copyWith(
          primary: primaryColor,
          background: backgroundColor,
          surface: surfaceColor,
          onPrimary: Colors.white,
          onBackground: textColor,
          onSurface: textColor,
        ),

        // --- ГЛАВНОЕ ИСПРАВЛЕНИЕ ЦВЕТА ТЕКСТА ---
        // Мы явно указываем цвет для каждого важного стиля текста.
        // Это надежнее, чем .apply(), и предотвращает проблемы с наследованием.
        textTheme: GoogleFonts.robotoTextTheme(baseTheme.textTheme).copyWith(
          titleLarge: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          titleMedium: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
          bodyLarge: const TextStyle(fontSize: 17, height: 1.4, color: textColor),
          bodyMedium: const TextStyle(fontSize: 16, color: textColor),
          labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),

        appBarTheme: const AppBarTheme(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 1,
            titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
        ),
        cardTheme: CardThemeData(
          elevation: 0.5,
          color: surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
            )
        )
    );
  }
}