// lib/services/panic_wipe_service.dart
// Сервис экстренного удаления данных (panic wipe)
//
// ВАЖНОЕ ОГРАНИЧЕНИЕ:
// Flutter не даёт надёжно перехватывать физическое нажатие кнопки питания без нативного кода.
// Поэтому текущая реализация использует приближение: "3 быстрых перехода приложения в background"
// (AppLifecycleState.paused), что обычно соответствует серии блокировок/разблокировок экрана
// или быстрому сворачиванию приложения.

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:orpheus_project/services/auth_service.dart';

/// Callback для уведомления о wipe
typedef PanicWipeCallback = Future<void> Function();

class PanicWipeService with WidgetsBindingObserver {
  static final PanicWipeService instance = PanicWipeService._();
  PanicWipeService._();

  /// Максимальный интервал между "нажатиями" (между событиями paused).
  /// Делаем окно шире, чтобы сценарий "заблокировал/разблокировал/заблокировал" был реалистичен.
  static const _maxInterval = Duration(seconds: 3);
  
  /// Количество нажатий для активации wipe
  static const _requiredPresses = 3;

  /// История переходов в paused
  final List<DateTime> _pauseTimestamps = [];
  
  /// Callback при активации wipe
  PanicWipeCallback? onPanicWipe;
  
  /// Флаг: wipe в процессе
  bool _isWiping = false;

  /// Инициализация сервиса
  void init() {
    WidgetsBinding.instance.addObserver(this);
    print("PANIC: Service initialized");
  }

  /// Очистка сервиса
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _onPause();
    }
  }

  void _onPause() {
    if (_isWiping) return;
    // По умолчанию выключено — чтобы нельзя было случайно “триггернуть” wipe.
    if (!AuthService.instance.config.isPanicGestureEnabled) return;
    
    final now = DateTime.now();
    
    // Удаляем старые записи
    _pauseTimestamps.removeWhere(
      (timestamp) => now.difference(timestamp) > (_maxInterval * _requiredPresses)
    );
    
    // Добавляем текущее нажатие
    _pauseTimestamps.add(now);
    // Держим только последние N событий, иначе старая история мешает срабатыванию.
    while (_pauseTimestamps.length > _requiredPresses) {
      _pauseTimestamps.removeAt(0);
    }
    
    print("PANIC: Pause detected (${_pauseTimestamps.length}/$_requiredPresses)");
    
    // Проверяем паттерн
    if (_pauseTimestamps.length >= _requiredPresses) {
      // Проверяем, что все нажатия были в пределах интервала
      bool isValidPattern = true;
      for (int i = 1; i < _pauseTimestamps.length; i++) {
        if (_pauseTimestamps[i].difference(_pauseTimestamps[i - 1]) > _maxInterval) {
          isValidPattern = false;
          break;
        }
      }
      
      if (isValidPattern) {
        _triggerPanicWipe();
      }
    }
  }

  Future<void> _triggerPanicWipe() async {
    if (_isWiping) return;
    _isWiping = true;
    
    print("PANIC: ⚠️ PANIC WIPE TRIGGERED!");
    
    _pauseTimestamps.clear();
    
    try {
      // Выполняем wipe
      await AuthService.instance.performWipe();
      
      // Уведомляем приложение
      await onPanicWipe?.call();
    } catch (e) {
      print("PANIC ERROR: Wipe failed: $e");
    } finally {
      _isWiping = false;
    }
  }

  /// Ручной вызов panic wipe (для тестирования)
  Future<void> triggerManualWipe() async {
    await _triggerPanicWipe();
  }
}

