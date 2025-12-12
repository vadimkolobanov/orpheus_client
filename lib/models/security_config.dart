// lib/models/security_config.dart
// Модель конфигурации безопасности приложения

/// Конфигурация безопасности приложения
class SecurityConfig {
  /// Включена ли защита PIN-кодом
  final bool isPinEnabled;
  
  /// Хеш основного PIN-кода (Argon2id hash)
  final String? pinHash;
  
  /// Соль для хеширования PIN
  final String? pinSalt;
  
  /// Включен ли код принуждения (duress code)
  final bool isDuressEnabled;
  
  /// Хеш кода принуждения
  final String? duressHash;
  
  /// Соль для хеширования duress кода
  final String? duressSalt;
  
  /// Количество неудачных попыток ввода PIN
  final int failedAttempts;
  
  /// Время последней неудачной попытки (для rate limiting)
  final DateTime? lastFailedAttempt;
  
  /// Включена ли биометрия
  final bool isBiometricEnabled;
  
  /// Включён ли отдельный код удаления (panic wipe code)
  final bool isWipeCodeEnabled;

  /// Хеш кода удаления
  final String? wipeCodeHash;

  /// Соль для хеширования кода удаления
  final String? wipeCodeSalt;

  /// Включен ли автоматический wipe после N неудачных попыток
  final bool isAutoWipeEnabled;
  
  /// Количество попыток до автоматического wipe
  final int autoWipeAttempts;

  /// Включён ли жест экстренного удаления (3 быстрых ухода приложения в фон)
  /// ВАЖНО: это приближение, а не “перехват кнопки питания”.
  final bool isPanicGestureEnabled;

  const SecurityConfig({
    this.isPinEnabled = false,
    this.pinHash,
    this.pinSalt,
    this.isDuressEnabled = false,
    this.duressHash,
    this.duressSalt,
    this.failedAttempts = 0,
    this.lastFailedAttempt,
    this.isBiometricEnabled = false,
    this.isWipeCodeEnabled = false,
    this.wipeCodeHash,
    this.wipeCodeSalt,
    this.isAutoWipeEnabled = false,
    this.autoWipeAttempts = 10,
    this.isPanicGestureEnabled = false,
  });

  /// Пустая конфигурация (без защиты)
  static const empty = SecurityConfig();

  /// Создать копию с изменёнными полями
  SecurityConfig copyWith({
    bool? isPinEnabled,
    String? pinHash,
    String? pinSalt,
    bool? isDuressEnabled,
    String? duressHash,
    String? duressSalt,
    int? failedAttempts,
    DateTime? lastFailedAttempt,
    bool? isBiometricEnabled,
    bool? isWipeCodeEnabled,
    String? wipeCodeHash,
    String? wipeCodeSalt,
    bool? isAutoWipeEnabled,
    int? autoWipeAttempts,
    bool? isPanicGestureEnabled,
    bool clearPinHash = false,
    bool clearDuressHash = false,
    bool clearWipeCodeHash = false,
    bool clearLastFailedAttempt = false,
  }) {
    return SecurityConfig(
      isPinEnabled: isPinEnabled ?? this.isPinEnabled,
      pinHash: clearPinHash ? null : (pinHash ?? this.pinHash),
      pinSalt: clearPinHash ? null : (pinSalt ?? this.pinSalt),
      isDuressEnabled: isDuressEnabled ?? this.isDuressEnabled,
      duressHash: clearDuressHash ? null : (duressHash ?? this.duressHash),
      duressSalt: clearDuressHash ? null : (duressSalt ?? this.duressSalt),
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lastFailedAttempt: clearLastFailedAttempt ? null : (lastFailedAttempt ?? this.lastFailedAttempt),
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      isWipeCodeEnabled: isWipeCodeEnabled ?? this.isWipeCodeEnabled,
      wipeCodeHash: clearWipeCodeHash ? null : (wipeCodeHash ?? this.wipeCodeHash),
      wipeCodeSalt: clearWipeCodeHash ? null : (wipeCodeSalt ?? this.wipeCodeSalt),
      isAutoWipeEnabled: isAutoWipeEnabled ?? this.isAutoWipeEnabled,
      autoWipeAttempts: autoWipeAttempts ?? this.autoWipeAttempts,
      isPanicGestureEnabled: isPanicGestureEnabled ?? this.isPanicGestureEnabled,
    );
  }

  /// Сериализация в Map для хранения
  Map<String, dynamic> toMap() {
    return {
      'isPinEnabled': isPinEnabled,
      'pinHash': pinHash,
      'pinSalt': pinSalt,
      'isDuressEnabled': isDuressEnabled,
      'duressHash': duressHash,
      'duressSalt': duressSalt,
      'failedAttempts': failedAttempts,
      'lastFailedAttempt': lastFailedAttempt?.toIso8601String(),
      'isBiometricEnabled': isBiometricEnabled,
      'isWipeCodeEnabled': isWipeCodeEnabled,
      'wipeCodeHash': wipeCodeHash,
      'wipeCodeSalt': wipeCodeSalt,
      'isAutoWipeEnabled': isAutoWipeEnabled,
      'autoWipeAttempts': autoWipeAttempts,
      'isPanicGestureEnabled': isPanicGestureEnabled,
    };
  }

  /// Десериализация из Map
  factory SecurityConfig.fromMap(Map<String, dynamic> map) {
    return SecurityConfig(
      isPinEnabled: map['isPinEnabled'] ?? false,
      pinHash: map['pinHash'],
      pinSalt: map['pinSalt'],
      isDuressEnabled: map['isDuressEnabled'] ?? false,
      duressHash: map['duressHash'],
      duressSalt: map['duressSalt'],
      failedAttempts: map['failedAttempts'] ?? 0,
      lastFailedAttempt: map['lastFailedAttempt'] != null 
          ? DateTime.tryParse(map['lastFailedAttempt']) 
          : null,
      isBiometricEnabled: map['isBiometricEnabled'] ?? false,
      isWipeCodeEnabled: map['isWipeCodeEnabled'] ?? false,
      wipeCodeHash: map['wipeCodeHash'],
      wipeCodeSalt: map['wipeCodeSalt'],
      isAutoWipeEnabled: map['isAutoWipeEnabled'] ?? false,
      autoWipeAttempts: map['autoWipeAttempts'] ?? 10,
      isPanicGestureEnabled: map['isPanicGestureEnabled'] ?? false,
    );
  }

  /// Проверить, нужно ли показывать экран блокировки
  bool get requiresUnlock => isPinEnabled && pinHash != null;

  /// Проверить, заблокирован ли вход из-за превышения попыток
  bool get isLockedOut {
    if (lastFailedAttempt == null) return false;
    
    // Прогрессивная блокировка
    final lockDuration = _getLockDuration(failedAttempts);
    if (lockDuration == null) return false;
    
    final unlockTime = lastFailedAttempt!.add(lockDuration);
    return DateTime.now().isBefore(unlockTime);
  }

  /// Получить время до разблокировки
  Duration? get timeUntilUnlock {
    if (!isLockedOut || lastFailedAttempt == null) return null;
    
    final lockDuration = _getLockDuration(failedAttempts);
    if (lockDuration == null) return null;
    
    final unlockTime = lastFailedAttempt!.add(lockDuration);
    final remaining = unlockTime.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  /// Получить длительность блокировки в зависимости от количества попыток
  Duration? _getLockDuration(int attempts) {
    if (attempts < 5) return null;
    if (attempts < 7) return const Duration(seconds: 30);
    if (attempts < 10) return const Duration(minutes: 1);
    if (attempts < 15) return const Duration(minutes: 5);
    if (attempts < 20) return const Duration(minutes: 15);
    return const Duration(minutes: 30);
  }

  /// Проверить, нужен ли автоматический wipe
  bool get shouldAutoWipe => isAutoWipeEnabled && failedAttempts >= autoWipeAttempts;

  @override
  String toString() {
    return 'SecurityConfig(pin: $isPinEnabled, duress: $isDuressEnabled, wipeCode: $isWipeCodeEnabled, bio: $isBiometricEnabled, panicGesture: $isPanicGestureEnabled, attempts: $failedAttempts)';
  }
}

/// Результат проверки PIN
enum PinVerifyResult {
  /// Успешная проверка основного PIN
  success,
  
  /// Успешная проверка duress кода — показать пустой профиль
  duress,

  /// Введён код удаления — требуется подтверждение wipe
  wipeCode,
  
  /// Неверный PIN
  invalid,
  
  /// Временная блокировка из-за превышения попыток
  lockedOut,
  
  /// Требуется автоматический wipe
  autoWipe,
}

