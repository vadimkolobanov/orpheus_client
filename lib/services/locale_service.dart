import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис управления локалью приложения
class LocaleService extends ChangeNotifier {
  static final LocaleService _instance = LocaleService._internal();
  static LocaleService get instance => _instance;
  
  LocaleService._internal();
  
  static const String _localeKey = 'app_locale';
  
  /// Поддерживаемые локали
  static const List<Locale> supportedLocales = [
    Locale('en'), // English (основной)
    Locale('ru'), // Русский
  ];
  
  /// Текущая выбранная локаль (null = системная)
  Locale? _selectedLocale;
  Locale? get selectedLocale => _selectedLocale;
  
  /// Эффективная локаль (с учётом системной)
  Locale get effectiveLocale {
    if (_selectedLocale != null) {
      return _selectedLocale!;
    }
    // Определяем по системной локали
    final systemLocale = PlatformDispatcher.instance.locale;
    for (final supported in supportedLocales) {
      if (supported.languageCode == systemLocale.languageCode) {
        return supported;
      }
    }
    // Fallback на английский
    return const Locale('en');
  }
  
  /// Инициализация сервиса
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLocale = prefs.getString(_localeKey);
    
    if (savedLocale != null && savedLocale.isNotEmpty) {
      _selectedLocale = Locale(savedLocale);
    }
  }
  
  /// Установить локаль
  /// [locale] = null означает "использовать системную"
  Future<void> setLocale(Locale? locale) async {
    _selectedLocale = locale;
    
    final prefs = await SharedPreferences.getInstance();
    if (locale != null) {
      await prefs.setString(_localeKey, locale.languageCode);
    } else {
      await prefs.remove(_localeKey);
    }
    
    notifyListeners();
  }
  
  /// Проверка: используется ли системная локаль
  bool get isSystemLocale => _selectedLocale == null;
  
  /// Получить название языка на его родном языке
  static String getLanguageName(Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return 'English';
      case 'ru':
        return 'Русский';
      default:
        return locale.languageCode;
    }
  }
  
  /// Получить название текущего языка для отображения
  String get currentLanguageName {
    if (_selectedLocale == null) {
      return 'Auto';
    }
    return getLanguageName(_selectedLocale!);
  }
}
