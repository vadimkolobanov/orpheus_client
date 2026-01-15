class AppConfig {
  // ФИНАЛЬНЫЙ РЕЛИЗ 1.0.0
  static const String appVersion = "v1.1.2";

  // === ХОСТЫ (миграция домена) ===
  // Старый домен остаётся рабочим для уже выпущенных клиентов.
  static const String legacyHost = 'vadimkolobanov-orpheus-d95e.twc1.net';

  // Новый домен API/связи (цель миграции).
  static const String primaryApiHost = 'api.orpheus.click';

  /// Приоритетный список хостов API/WS.
  /// Важно: первым идёт новый домен, затем старый (fallback).
  static const List<String> apiHosts = [
    primaryApiHost,
    legacyHost,
  ];

  /// Для совместимости со старым кодом/тестами.
  /// В новых релизах это будет `api.orpheus.click`,
  /// а при проблемах сервисы будут падать обратно на `legacyHost`.
  static const String serverIp = primaryApiHost;
  // static const String serverIp = '10.0.2.2:8000'; // Для локальных тестов

  // --- Готовые URL ---
  static String webSocketUrl(String publicKey, {String? host}) {
    final encodedPublicKey = Uri.encodeComponent(publicKey);
    final h = host ?? serverIp;
    return 'wss://$h/ws/$encodedPublicKey';
  }

  static String httpUrl(String path, {String? host}) {
    final h = host ?? serverIp;
    return 'https://$h$path';
  }

  /// Перечень URL (по всем хостам) для безопасного fallback.
  static Iterable<String> httpUrls(String path) sync* {
    for (final h in apiHosts) {
      yield httpUrl(path, host: h);
    }
  }

  static Iterable<String> webSocketUrls(String publicKey) sync* {
    for (final h in apiHosts) {
      yield webSocketUrl(publicKey, host: h);
    }
  }

  // --- История обновлений (Changelog) ---
  //
  // ⚠️ ВАЖНО (политика проекта):
  // - Пользовательский "Что нового" / changelog НЕ должен вестись в клиенте.
  // - Единый источник правды для release notes: админ-панель OPHEUS_ADMIN → раздел "Версии".
  // - Сейчас клиент загружает release notes по публичному API админки:
  //   https://orpheus.click/api/public/releases
  // - Этот список оставлен как fallback (offline-safe) и может быть удалён позже.
  // - НЕ добавляйте сюда новые записи.
  static const List<Map<String, dynamic>> changelogData = [
    {
      'version': '1.1.0',
      'date': '12.12.2025',
      'changes': [
        'SECURITY: PIN-код (6 цифр) — опциональная защита входа.',
        'SECURITY: Duress code — второй PIN, показывающий пустой профиль.',
        'SECURITY: Код удаления (wipe code) — подтверждение удержанием, защита от случайного удаления.',
        'SECURITY: Auto-wipe после N неверных попыток (опционально).',
        'UI: Экран «Как пользоваться» — простая инструкция по функциям и рискам.',
        'FIX: Стабилизация поведения во время звонка: блокировка не мешает ответу/разговору.',
      ]
    },
    {
      'version': '1.0.0',
      'date': '09.12.2025',
      'changes': [
        'RELEASE: Финальный релиз Orpheus 1.0.0!',
        'NETWORK: Полная поддержка звонков в спящем режиме. Входящие проходят, даже если телефон заблокирован или приложение выгружено.',
        'NEW: Экран "Системный Монитор". Графики стабильности сети, пинг и статус шифрования в реальном времени.',
        'NEW: Новая навигация: Контакты, Система, Профиль.',
        'CORE: Система ICE Buffering. Устранена проблема соединения при ответе на звонок из Push-уведомления.',
        'UI: Обновленный дизайн профиля и QR-визитки.',
        'UI: Фирменная иконка приложения и заставка с логотипом.',
        'UI: Поле ввода сообщений теперь поддерживает многострочный текст.',
        'UI: Анимация шифрования при отправке сообщений.',
        'FIX: Исправлены ошибки дублирования звонков.',
        'FIX: Улучшена стабильность WebSocket соединения.',
      ]
    },
    {
      'version': '0.9.0-Beta',
      'date': '01.12.2025',
      'changes': [
        'CALLS: Улучшена система сигналинга для WebRTC звонков через WebSocket.',
        'CALLS: Реализована буферизация ICE кандидатов для входящих звонков.',
        'CALLS: Добавлены системные сообщения о звонках в историю чата.',
        'UI: Полностью переработанный экран звонка с анимациями и визуализацией аудио волн.',
        'UI: Отображение длительности звонка в реальном времени.',
        'DEBUG: Добавлен режим отладки с логами WebRTC и сигналинга в UI.',
      ]
    },
    {
      'version': '0.8-Beta',
      'date': '25.11.2025',
      'changes': [
        'CALLS: Полная стабилизация звонков (TURN 2.0).',
        'CALLS: Теперь отображается Имя контакта при звонке, а не ключ.',
        'NEW: Встроенная система обновлений приложения.',
        'NEW: Сканер QR-кодов для быстрого обмена контактами.',
        'FIX: Исправлены вылеты на Android 11+.',
      ]
    },
    {
      'version': '0.7-Alpha',
      'date': '21.11.2025',
      'changes': [
        'DESIGN: Новый стиль "Dark Premium" (Черный/Серебро).',
        'SECURITY: Запрет скриншотов и записи экрана.',
        'SECURITY: Биометрическая защита (палец/лицо) для экспорта ключей.',
        'NEW: Активация лицензии промокодом.',
        'UX: Удобная визитка с ID и кнопкой "Поделиться".',
      ]
    },
    {
      'version': '0.6-Alpha',
      'date': '19.11.2025',
      'changes': [
        'NEW: Push-уведомления! Теперь вы узнаете о сообщениях, даже если приложение закрыто.',
        'UI: Счетчики непрочитанных сообщений в списке контактов.',
        'UI: Галочки статуса доставки в чате.',
        'Fix: Улучшена стабильность соединения (авто-реконнект).',
      ]
    },
    {
      'version': '0.5-Alpha',
      'date': 'Initial Release',
      'changes': [
        'Релиз базовой версии.',
        'Анонимные звонки (WebRTC) и чаты.',
        'Шифрование X25519/ChaCha20.',
      ]
    },
  ];
}