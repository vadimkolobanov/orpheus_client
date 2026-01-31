import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/license_screen.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/models/message_retention_policy.dart';
import 'package:orpheus_project/screens/lock_screen.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/incoming_call_buffer.dart';
import 'package:orpheus_project/services/incoming_message_handler.dart';
import 'package:orpheus_project/services/network_monitor_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/panic_wipe_service.dart';
import 'package:orpheus_project/services/message_cleanup_service.dart';
import 'package:orpheus_project/services/call_state_service.dart';
import 'package:orpheus_project/services/presence_service.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/theme/app_theme.dart';
import 'package:orpheus_project/welcome_screen.dart';
import 'package:orpheus_project/screens/home_screen.dart';

// Глобальные сервисы
final cryptoService = CryptoService();
final websocketService = WebSocketService();
final presenceService = PresenceService(websocketService);
final notificationService = NotificationService();
final authService = AuthService.instance;
final panicWipeService = PanicWipeService.instance;
final messageCleanupService = MessageCleanupService.instance;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Потоки для обновлений UI
final StreamController<String> messageUpdateController = StreamController.broadcast();
final StreamController<Map<String, dynamic>> signalingStreamController = StreamController.broadcast();

/// Буфер входящих сигналов звонка (ICE candidates и т.п.)
final IncomingCallBuffer incomingCallBuffer = IncomingCallBuffer.instance;

bool _hasKeys = false;

/// Глобальный флаг: приложение в foreground (активно)?
bool isAppInForeground = true;

/// Данные отложенного звонка (если пользователь принял звонок, но приложение заблокировано)
class PendingCallData {
  final String callerKey;
  final Map<String, dynamic>? offerData;
  final DateTime timestamp;
  /// Если true — звонок уже принят через CallKit, нужен автоответ
  final bool autoAnswer;
  
  PendingCallData({required this.callerKey, this.offerData, this.autoAnswer = true}) 
      : timestamp = DateTime.now();
  
  /// Проверка что звонок ещё актуален (не старше 30 секунд)
  bool get isValid => DateTime.now().difference(timestamp).inSeconds < 30;
}

PendingCallData? _pendingCall;

/// Флаг: ожидается открытие CallScreen из CallKit (блокирует дубли из WebSocket)
bool _isProcessingCallKitAnswer = false;

/// Sentry DSN для мониторинга ошибок
const String _sentryDsn = 'https://7d6801508e29bc2e4f5b93b986147cdc@o4509485705265152.ingest.de.sentry.io/4510682122879056';

Future<void> main() async {
  // Sentry инициализация с перехватом всех ошибок
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      // Версия приложения для отслеживания регрессий
      options.release = 'orpheus@1.1.1+7';
      options.environment = 'production';
      // Отслеживание производительности (10% транзакций)
      options.tracesSampleRate = 0.1;
      // Отключаем отправку PII (персональных данных)
      options.sendDefaultPii = false;
      // Фильтруем breadcrumbs от чувствительных данных
      options.beforeBreadcrumb = (Breadcrumb? breadcrumb, Hint _hint) {
        // Не логируем содержимое сообщений
        if (breadcrumb?.category == 'message' || 
            breadcrumb?.message?.contains('encrypted') == true) {
          return null;
        }
        return breadcrumb;
      };
    },
    appRunner: () async {
      await _initializeApp();
      runApp(const MyApp());
    },
  );
}

/// Основная инициализация приложения
Future<void> _initializeApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  DebugLogger.info('APP', '🚀 Orpheus запускается...');

  // Intl (DateFormat) требует инициализации таблиц локали.
  // Без этого DateFormat(..., 'ru') падает с LocaleDataException на некоторых устройствах/локалях (например en-US).
  Intl.defaultLocale = 'ru';
  await initializeDateFormatting('ru');

  try {
    // 1. Firebase
    DebugLogger.info('APP', 'Инициализация Firebase...');
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    DebugLogger.success('APP', 'Firebase инициализирован');
    
    // 2. Уведомления (простая инициализация)
    DebugLogger.info('APP', 'Инициализация уведомлений...');
    await notificationService.init();
    DebugLogger.success('APP', 'Уведомления инициализированы');

    // 3. BackgroundCallService — НЕ инициализируем на старте.
    // Он будет lazy-инициализирован при первом звонке (см. BackgroundCallService.startCallService()).
  } catch (e, stackTrace) {
    print("INIT ERROR: $e");
    DebugLogger.error('APP', 'INIT ERROR: $e');
    // Отправляем ошибку инициализации в Sentry
    await Sentry.captureException(e, stackTrace: stackTrace);
  }

  // 4. Криптография
  DebugLogger.info('APP', 'Инициализация криптографии...');
  _hasKeys = await cryptoService.init();
  DebugLogger.info('APP', 'Ключи: ${_hasKeys ? "ЕСТЬ" : "НЕТ"}');

  // 5. Сервис авторизации (PIN, duress)
  DebugLogger.info('APP', 'Инициализация AuthService...');
  await authService.init();
  DebugLogger.info('APP', 'AuthService: PIN=${authService.config.isPinEnabled}, duress=${authService.config.isDuressEnabled}');

  // 5.5. Сервис автоочистки сообщений (зависит от AuthService)
  DebugLogger.info('APP', 'Инициализация MessageCleanupService...');
  await messageCleanupService.init();
  DebugLogger.info('APP', 'MessageCleanupService: retention=${authService.messageRetention.displayName}');

  // 6. Panic Wipe Service (тройное нажатие кнопки питания)
  panicWipeService.init();
  panicWipeService.onPanicWipe = () async {
    DebugLogger.warn('APP', '⚠️ PANIC WIPE EXECUTED');
    // После wipe перезапускаем приложение
    _hasKeys = false;
  };

  // 7. Network Monitor Service (мониторинг сети для реконнекта)
  DebugLogger.info('APP', 'Инициализация NetworkMonitorService.');
  await NetworkMonitorService.instance.init();
  DebugLogger.success('APP', 'NetworkMonitorService инициализирован');

  // 8. WebSocket подключение
  if (_hasKeys && cryptoService.publicKeyBase64 != null) {
    DebugLogger.info('APP', 'Подключение WebSocket...');
    websocketService.connect(cryptoService.publicKeyBase64!);
  }

  // 9. Слушаем сообщения
  _listenForMessages();
  
  // 10. Инициализация CallKit для нативного UI звонков
  DebugLogger.info('APP', 'Инициализация CallKit...');
  _initCallKit();
  DebugLogger.success('APP', 'CallKit инициализирован');

  DebugLogger.success('APP', '✅ Приложение запущено');
}

/// Инициализация CallKit для обработки нативного UI входящих звонков
void _initCallKit() {
  // Слушаем события от CallKit (принять/отклонить звонок)
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
    if (event == null) return;
    
    DebugLogger.info('CALLKIT', 'Event: ${event.event}, body keys: ${event.body?.keys.toList()}');
    
    switch (event.event) {
      case Event.actionCallAccept:
        // Пользователь принял звонок через нативный UI
        await _handleCallKitAccept(event.body);
        break;
        
      case Event.actionCallDecline:
        // Пользователь отклонил звонок через нативный UI
        await _handleCallKitDecline(event.body);
        break;
        
      case Event.actionCallEnded:
        // Звонок завершён
        DebugLogger.info('CALLKIT', 'Звонок завершён');
        break;
        
      case Event.actionCallTimeout:
        // Таймаут - никто не ответил
        DebugLogger.info('CALLKIT', 'Таймаут звонка');
        await _handleCallKitDecline(event.body);
        break;
        
      default:
        break;
    }
  });
  
  // Проверяем, есть ли активный звонок при запуске приложения
  // (если приложение было запущено из нативного UI)
  _checkActiveCallOnStart();
}

/// Рекурсивно конвертирует Map<Object?, Object?> → Map<String, dynamic>
Map<String, dynamic> _convertToStringDynamicMap(dynamic input) {
  if (input is Map<String, dynamic>) return input;
  if (input is Map) {
    return input.map((key, value) {
      final stringKey = key?.toString() ?? '';
      if (value is Map) {
        return MapEntry(stringKey, _convertToStringDynamicMap(value));
      }
      return MapEntry(stringKey, value);
    });
  }
  return {};
}

/// Извлекает extra из CallKit body (обрабатывает разные типы)
Map<String, dynamic>? _extractExtraFromBody(Map<String, dynamic>? body) {
  if (body == null) return null;
  
  final rawExtra = body['extra'];
  DebugLogger.info('CALLKIT', 'rawExtra type: ${rawExtra?.runtimeType}');
  
  if (rawExtra == null) return null;
  
  // Случай 1: уже Map<String, dynamic>
  if (rawExtra is Map<String, dynamic>) {
    DebugLogger.info('CALLKIT', 'extra is Map<String, dynamic>');
    return rawExtra;
  }
  
  // Случай 2: Map<Object?, Object?> или LinkedHashMap
  if (rawExtra is Map) {
    DebugLogger.info('CALLKIT', 'extra is Map (converting...)');
    return _convertToStringDynamicMap(rawExtra);
  }
  
  // Случай 3: JSON строка
  if (rawExtra is String) {
    DebugLogger.info('CALLKIT', 'extra is String (parsing JSON...)');
    try {
      final decoded = json.decode(rawExtra);
      if (decoded is Map) {
        return _convertToStringDynamicMap(decoded);
      }
    } catch (e) {
      DebugLogger.error('CALLKIT', 'Ошибка парсинга extra JSON: $e');
    }
  }
  
  return null;
}

/// Проверка активного звонка при запуске приложения
Future<void> _checkActiveCallOnStart() async {
  // Ждём пока Navigator будет готов (первый кадр отрисован)
  await Future.delayed(const Duration(milliseconds: 300));
  
  // Сначала проверяем pending call (сохранён из _handleCallKitAccept когда Navigator был null)
  if (_pendingCall != null && _pendingCall!.isValid) {
    DebugLogger.info('CALLKIT', '📞 Найден pending call, открываю CallScreen');
    final pending = _pendingCall!;
    _pendingCall = null;
    _navigateToCallScreen(pending.callerKey, pending.offerData, autoAnswer: pending.autoAnswer);
    return;
  }
  
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    DebugLogger.info('CALLKIT', 'Проверка активных звонков: ${calls.length}');
    
    if (calls.isNotEmpty) {
      DebugLogger.info('CALLKIT', 'Найден активный звонок при запуске');
      
      // КРИТИЧНО: блокируем дубли из WebSocket
      _isProcessingCallKitAnswer = true;
      
      // Конвертируем первый звонок в Map<String, dynamic>
      final rawCall = calls.first;
      Map<String, dynamic> call;
      if (rawCall is Map<String, dynamic>) {
        call = rawCall;
      } else if (rawCall is Map) {
        call = _convertToStringDynamicMap(rawCall);
      } else {
        DebugLogger.error('CALLKIT', 'Неизвестный тип call: ${rawCall.runtimeType}');
        _isProcessingCallKitAnswer = false;
        return;
      }
      
      DebugLogger.info('CALLKIT', 'Active call keys: ${call.keys.toList()}');
      
      // Парсим extra
      final extra = _extractExtraFromBody(call);
      String? callerKey = extra?['callerKey'] as String?;
      
      // Fallback на буфер
      if (callerKey == null) {
        callerKey = incomingCallBuffer.lastCallerKey;
        DebugLogger.info('CALLKIT', 'callerKey from buffer: $callerKey');
      }
      
      if (callerKey != null) {
        DebugLogger.info('CALLKIT', 'Открываю CallScreen для активного звонка: $callerKey');
        
        // Формируем extra
        Map<String, dynamic> callExtra = extra ?? {};
        if (callExtra['offerData'] == null) {
          final bufferOffer = incomingCallBuffer.lastOfferData;
          if (bufferOffer != null) {
            callExtra['offerData'] = json.encode(bufferOffer);
          }
        }
        callExtra['callerKey'] = callerKey;
        
        _openCallScreenFromCallKit(callerKey, callExtra);
      } else {
        DebugLogger.warn('CALLKIT', 'callerKey is null, не могу открыть CallScreen');
        _isProcessingCallKitAnswer = false;
      }
    }
  } catch (e) {
    DebugLogger.error('CALLKIT', 'Ошибка проверки активного звонка: $e');
    _isProcessingCallKitAnswer = false;
  }
}

/// Обработка принятия звонка через CallKit
Future<void> _handleCallKitAccept(Map<String, dynamic>? body) async {
  DebugLogger.info('CALLKIT', '📥 ACCEPT body: $body');
  
  // КРИТИЧНО: блокируем открытие CallScreen из WebSocket пока обрабатываем CallKit
  _isProcessingCallKitAnswer = true;
  
  final callId = body?['id'] as String?;
  
  // Используем надёжный парсинг extra
  final extra = _extractExtraFromBody(body);
  DebugLogger.info('CALLKIT', '📥 extra parsed: ${extra?.keys.toList()}');
  
  String? callerKey = extra?['callerKey'] as String?;
  DebugLogger.info('CALLKIT', '📥 callerKey from extra: $callerKey');
  
  // ВАЖНО: НЕ вызываем endAllCalls() здесь!
  // При перезапуске приложения из killed state, _checkActiveCallOnStart() 
  // должен найти активный звонок. CallScreen сам вызовет endAllCalls() при инициализации.
  
  // Если callerKey из extra null, пробуем буфер
  if (callerKey == null) {
    DebugLogger.warn('CALLKIT', '⚠️ callerKey null, проверяю буфер...');
    callerKey = incomingCallBuffer.lastCallerKey;
    DebugLogger.info('CALLKIT', '📥 callerKey from buffer: $callerKey');
  }
  
  DebugLogger.info('CALLKIT', '✅ Звонок принят: callId=$callId, callerKey=$callerKey');
  
  // Открываем CallScreen
  if (callerKey != null) {
    // Формируем extra для CallScreen
    Map<String, dynamic> callExtra = extra ?? {};
    
    // Если offerData не в extra, берём из буфера
    if (callExtra['offerData'] == null) {
      final bufferOffer = incomingCallBuffer.lastOfferData;
      if (bufferOffer != null) {
        callExtra['offerData'] = json.encode(bufferOffer);
        DebugLogger.info('CALLKIT', '📥 offerData взят из буфера');
      }
    }
    
    callExtra['callerKey'] = callerKey;
    _openCallScreenFromCallKit(callerKey, callExtra);
  } else {
    DebugLogger.error('CALLKIT', '❌ callerKey is null! Нет данных для звонка!');
    _isProcessingCallKitAnswer = false; // Сбрасываем флаг при ошибке
    // Скрываем UI только при ошибке
    await FlutterCallkitIncoming.endAllCalls();
  }
}

/// Обработка отклонения звонка через CallKit
Future<void> _handleCallKitDecline(Map<String, dynamic>? body) async {
  DebugLogger.info('CALLKIT', '📥 DECLINE body: $body');
  
  // Сбрасываем флаг обработки CallKit
  _isProcessingCallKitAnswer = false;
  
  final callId = body?['id'] as String?;
  
  // Используем надёжный парсинг extra
  final extra = _extractExtraFromBody(body);
  String? callerKey = extra?['callerKey'] as String?;
  
  DebugLogger.info('CALLKIT', '📥 callerKey from extra: $callerKey');
  
  // Fallback: используем данные из буфера
  if (callerKey == null) {
    callerKey = incomingCallBuffer.lastCallerKey;
    DebugLogger.info('CALLKIT', '📥 callerKey from buffer: $callerKey');
  }
  
  DebugLogger.info('CALLKIT', '❌ Звонок отклонён: callId=$callId, callerKey=$callerKey');
  
  // Скрываем нативный UI СРАЗУ
  await FlutterCallkitIncoming.endAllCalls();
  
  // Очищаем буфер
  incomingCallBuffer.clearLastIncomingCall();
  
  // Отправляем call-rejected через WebSocket
  if (callerKey != null) {
    if (websocketService.currentStatus == ConnectionStatus.Connected) {
      websocketService.sendSignalingMessage(callerKey, 'call-rejected', {});
      DebugLogger.info('CALLKIT', '✅ Отправлен call-rejected к $callerKey');
    } else {
      DebugLogger.warn('CALLKIT', '⚠️ WebSocket не подключен, call-rejected не отправлен');
    }
  } else {
    DebugLogger.error('CALLKIT', '❌ callerKey null, не могу отправить call-rejected');
  }
}

/// Открыть CallScreen после принятия звонка через CallKit
/// autoAnswer=true означает что звонок уже принят через нативный UI
void _openCallScreenFromCallKit(String callerKey, Map<String, dynamic>? extra, {bool autoAnswer = true}) {
  // Получаем offer data если есть
  Map<String, dynamic>? offerData;
  final offerJson = extra?['offerData'] as String?;
  if (offerJson != null) {
    try {
      offerData = json.decode(offerJson) as Map<String, dynamic>;
    } catch (_) {}
  }
  
  DebugLogger.info('CALLKIT', 'Открываю CallScreen, offer: ${offerData != null}, autoAnswer: $autoAnswer');
  
  // Если приложение заблокировано (PIN) — сохраняем звонок как pending
  // CallScreen откроется после разблокировки
  if (authService.requiresUnlock) {
    DebugLogger.info('CALLKIT', '🔒 Приложение заблокировано, сохраняю pending call');
    _pendingCall = PendingCallData(callerKey: callerKey, offerData: offerData, autoAnswer: autoAnswer);
    return;
  }
  
  // Открываем CallScreen сразу с autoAnswer
  _navigateToCallScreen(callerKey, offerData, autoAnswer: autoAnswer);
}

/// Навигация на CallScreen (используется напрямую и после разблокировки)
void _navigateToCallScreen(String callerKey, Map<String, dynamic>? offerData, {bool autoAnswer = false}) {
  // Проверяем что нет уже активного звонка
  if (CallStateService.instance.isCallActive.value) {
    DebugLogger.warn('CALLKIT', 'Уже есть активный звонок, игнорирую');
    _isProcessingCallKitAnswer = false; // Сбрасываем флаг
    return;
  }
  
  // КРИТИЧНО: Если Navigator ещё не инициализирован (приложение запускается из killed state),
  // сохраняем pending call — он будет обработан в _checkActiveCallOnStart() или при первом frame
  if (navigatorKey.currentState == null) {
    DebugLogger.warn('CALLKIT', '⚠️ Navigator ещё null, сохраняю pending call');
    _pendingCall = PendingCallData(callerKey: callerKey, offerData: offerData, autoAnswer: autoAnswer);
    _isProcessingCallKitAnswer = false;
    return;
  }
  
  // Очищаем буфер после использования
  incomingCallBuffer.clearLastIncomingCall();
  
  DebugLogger.info('CALLKIT', '📞 Навигация на CallScreen для $callerKey, hasOffer=${offerData != null}, autoAnswer=$autoAnswer');
  
  // ВАЖНО: При возврате из background, Navigator может быть не готов к навигации.
  // Ждём следующий кадр чтобы гарантировать что UI восстановлен.
  // Также добавляем fallback таймер на случай если приложение в background и кадры не рендерятся.
  bool callbackExecuted = false;
  
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (callbackExecuted) return; // Защита от дублей
    callbackExecuted = true;
    
    // Ещё раз проверяем состояние
    if (CallStateService.instance.isCallActive.value) {
      DebugLogger.warn('CALLKIT', 'Звонок уже активен после postFrame, пропускаю');
      _isProcessingCallKitAnswer = false;
      return;
    }
    
    if (navigatorKey.currentState == null) {
      // Если Navigator всё ещё null — сохраняем pending call для обработки при resumed
      DebugLogger.warn('CALLKIT', '⚠️ Navigator null после postFrame, сохраняю pending call');
      _pendingCall = PendingCallData(callerKey: callerKey, offerData: offerData, autoAnswer: autoAnswer);
      _isProcessingCallKitAnswer = false;
      return;
    }
    
    DebugLogger.info('CALLKIT', '📞 Открываю CallScreen (postFrame)');
    navigatorKey.currentState!.push(MaterialPageRoute(
      builder: (context) => CallScreen(
        contactPublicKey: callerKey,
        offer: offerData,
        autoAnswer: autoAnswer,
      ),
    ));
    
    // Скрываем CallKit UI после успешной навигации
    FlutterCallkitIncoming.endAllCalls();
    
    // Сбрасываем флаг после успешной навигации
    Future.delayed(const Duration(milliseconds: 100), () {
      _isProcessingCallKitAnswer = false;
    });
  });
  
  // Fallback: если callback не выполнился за 2 секунды (приложение в background),
  // сохраняем pending call для обработки при resumed
  Future.delayed(const Duration(seconds: 2), () {
    if (!callbackExecuted) {
      DebugLogger.warn('CALLKIT', '⏰ PostFrame callback не выполнился за 2с, сохраняю pending call');
      callbackExecuted = true;
      _pendingCall = PendingCallData(callerKey: callerKey, offerData: offerData, autoAnswer: autoAnswer);
      _isProcessingCallKitAnswer = false;
    }
  });
}

/// Обработать отложенный звонок после разблокировки
void processPendingCallAfterUnlock() {
  final pending = _pendingCall;
  _pendingCall = null;
  
  if (pending == null) return;
  
  if (!pending.isValid) {
    DebugLogger.warn('CALLKIT', '⏰ Pending call устарел (>${30}s), игнорирую');
    return;
  }
  
  DebugLogger.info('CALLKIT', '🔓 Обработка pending call после разблокировки, autoAnswer=${pending.autoAnswer}');
  _navigateToCallScreen(pending.callerKey, pending.offerData, autoAnswer: pending.autoAnswer);
}

/// Проверка активных CallKit звонков при возврате из background
/// Fallback на случай если pending call был потерян, но CallKit показывает активный звонок
Future<void> _checkActiveCallOnResumed() async {
  // Если уже есть активный звонок или обрабатывается ответ — выходим
  if (CallStateService.instance.isCallActive.value || _isProcessingCallKitAnswer) {
    return;
  }
  
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls.isEmpty) return;
    
    DebugLogger.info('LIFECYCLE', '📞 Найден активный CallKit звонок при resumed');
    
    // Блокируем дубли
    _isProcessingCallKitAnswer = true;
    
    // Конвертируем первый звонок
    final rawCall = calls.first;
    Map<String, dynamic> call;
    if (rawCall is Map<String, dynamic>) {
      call = rawCall;
    } else if (rawCall is Map) {
      call = _convertToStringDynamicMap(rawCall);
    } else {
      DebugLogger.error('LIFECYCLE', 'Неизвестный тип call: ${rawCall.runtimeType}');
      _isProcessingCallKitAnswer = false;
      return;
    }
    
    // Парсим extra
    final extra = _extractExtraFromBody(call);
    String? callerKey = extra?['callerKey'] as String?;
    
    // Fallback на буфер
    if (callerKey == null) {
      callerKey = incomingCallBuffer.lastCallerKey;
    }
    
    if (callerKey != null) {
      DebugLogger.info('LIFECYCLE', '📞 Открываю CallScreen для активного звонка (resumed)');
      
      Map<String, dynamic> callExtra = extra ?? {};
      if (callExtra['offerData'] == null) {
        final bufferOffer = incomingCallBuffer.lastOfferData;
        if (bufferOffer != null) {
          callExtra['offerData'] = json.encode(bufferOffer);
        }
      }
      callExtra['callerKey'] = callerKey;
      
      _openCallScreenFromCallKit(callerKey, callExtra);
    } else {
      DebugLogger.warn('LIFECYCLE', '⚠️ callerKey is null при resumed, пропускаю');
      _isProcessingCallKitAnswer = false;
    }
  } catch (e) {
    DebugLogger.error('LIFECYCLE', 'Ошибка проверки CallKit при resumed: $e');
    _isProcessingCallKitAnswer = false;
  }
}

void _listenForMessages() {
  final handler = IncomingMessageHandler(
    crypto: _IncomingCryptoAdapter(cryptoService),
    database: _IncomingDatabaseAdapter(DatabaseService.instance),
    notifications: _IncomingNotificationsAdapter(),
    callBuffer: incomingCallBuffer,
    openCallScreen: ({required contactPublicKey, required offer}) {
      // ВАЖНО: используем централизованную навигацию с проверками
      // Если приложение в foreground, WebSocket может доставить call-offer
      // но если CallKit уже обрабатывает ответ - игнорируем дубль
      if (_isProcessingCallKitAnswer) {
        DebugLogger.info('CALL', '📞 Игнорирую call-offer из WS: CallKit уже обрабатывает');
        return;
      }
      if (CallStateService.instance.isCallActive.value) {
        DebugLogger.info('CALL', '📞 Игнорирую call-offer из WS: уже есть активный звонок');
        return;
      }
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (context) => CallScreen(contactPublicKey: contactPublicKey, offer: offer),
      ));
    },
    emitSignaling: (msg) => signalingStreamController.add(msg),
    emitChatUpdate: (senderKey) => messageUpdateController.add(senderKey),
    isAppInForeground: () => isAppInForeground,
    // КРИТИЧНО: передаём проверку активного звонка И обработки CallKit
    isCallActive: () => CallStateService.instance.isCallActive.value || _isProcessingCallKitAnswer,
  );

  websocketService.stream.listen((messageJson) async {
    try {
      await handler.handleRawMessage(messageJson);
    } catch (e, stackTrace) {
      DebugLogger.error('MAIN', 'Message Handler Error: $e');
      // Отправляем ошибку обработки сообщений в Sentry
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  });
}

class _IncomingCryptoAdapter implements IncomingMessageCrypto {
  _IncomingCryptoAdapter(this._crypto);
  final CryptoService _crypto;
  @override
  Future<String> decrypt(String senderPublicKeyBase64, String encryptedPayload) {
    return _crypto.decrypt(senderPublicKeyBase64, encryptedPayload);
  }
}

class _IncomingDatabaseAdapter implements IncomingMessageDatabase {
  _IncomingDatabaseAdapter(this._db);
  final DatabaseService _db;

  @override
  Future<void> addMessage(ChatMessage message, String contactPublicKey) {
    return _db.addMessage(message, contactPublicKey);
  }

  @override
  Future<String?> getContactName(String publicKey) async {
    try {
      final contact = await _db.getContact(publicKey);
      if (contact != null && contact.name.trim().isNotEmpty) {
        return contact.name;
      }
    } catch (_) {}
    return null;
  }
}

class _IncomingNotificationsAdapter implements IncomingMessageNotifications {
  @override
  Future<void> showCallNotification({required String callerName}) {
    return NotificationService.showCallNotification(callerName: callerName);
  }

  @override
  Future<void> hideCallNotification() {
    return NotificationService.hideCallNotification();
  }

  @override
  Future<void> showMessageNotification({required String senderName}) {
    return NotificationService.showMessageNotification(senderName: senderName);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isLicensed = false;
  bool _isCheckCompleted = false;
  late bool _keysExist;
  bool _isLocked = false;
  StreamSubscription<String>? _licenseSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keysExist = _hasKeys;
    _isLocked = authService.requiresUnlock;
    
    // Подписываемся на panic wipe
    panicWipeService.onPanicWipe = () async {
      DebugLogger.warn('APP', '⚠️ PANIC WIPE - restarting app');
      if (mounted) {
        setState(() {
          _keysExist = false;
        });
      }
    };
    
    print("🔑 Keys exist: $_keysExist | Public key: ${cryptoService.publicKeyBase64?.substring(0, 20) ?? 'NULL'}...");
    print("🔒 Locked: $_isLocked | PIN enabled: ${authService.config.isPinEnabled}");

    // Слушаем статус лицензии
    _licenseSubscription = websocketService.stream.listen((message) {
      try {
        // Быстрый фильтр — не парсим JSON на каждом сообщении.
        if (!message.contains('license-status') && !message.contains('payment-confirmed')) return;

        final data = json.decode(message);
        if (data['type'] == 'license-status') {
          print("📋 License status received: ${data['status']}");
          setState(() {
            _isLicensed = (data['status'] == 'active');
            _isCheckCompleted = true;
          });
          _licenseSubscription?.cancel();
          _licenseSubscription = null;
        } else if (data['type'] == 'payment-confirmed') {
          print("💳 Payment confirmed!");
          setState(() {
            _isLicensed = true;
            _isCheckCompleted = true;
          });
          _licenseSubscription?.cancel();
          _licenseSubscription = null;
        }
      } catch (_) {}
    });

    // Таймаут на проверку лицензии (10 секунд)
    // Если за это время не получили ответ — показываем экран лицензии
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && !_isCheckCompleted) {
        print("⚠️ License check timeout - showing license screen");
        setState(() {
          _isCheckCompleted = true;
          _isLicensed = false;
        });
      }
    });
  }

  void _onAuthComplete() {
    setState(() => _keysExist = true);
    if (cryptoService.publicKeyBase64 != null) {
      websocketService.connect(cryptoService.publicKeyBase64!);
    }
  }

  void _onUnlocked() {
    DebugLogger.info('APP', '🔓 App unlocked');
    setState(() => _isLocked = false);
    
    // Обработать отложенный звонок если есть
    // Используем небольшую задержку чтобы UI успел перестроиться
    Future.delayed(const Duration(milliseconds: 300), () {
      processPendingCallAfterUnlock();
    });
  }

  void _onDuressMode() {
    DebugLogger.warn('APP', '🔓 App unlocked in DURESS MODE');
    setState(() => _isLocked = false);
    // В duress mode приложение работает, но показывает пустой профиль
  }

  Future<void> _onWipe(WipeReason reason) async {
    final label = switch (reason) {
      WipeReason.wipeCode => 'WIPE CODE',
      WipeReason.autoWipe => 'AUTO WIPE',
    };
    DebugLogger.warn('APP', '⚠️ $label: выполняется полный WIPE');
    await authService.performWipe();
    if (!mounted) return;
    setState(() {
      _keysExist = false;
      _isLocked = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _licenseSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Логируем изменение состояния
    DebugLogger.info('LIFECYCLE', 'State: $state');
    
    // Обновляем глобальный флаг состояния приложения
    isAppInForeground = (state == AppLifecycleState.resumed);
    
    if (state == AppLifecycleState.resumed) {
      DebugLogger.info('LIFECYCLE', 'Приложение в foreground, переподключение WS...');
      // Переподключение WebSocket при возврате в приложение
      if (cryptoService.publicKeyBase64 != null) {
        websocketService.connect(cryptoService.publicKeyBase64!);
      }
      // Проверка автоочистки сообщений при возвращении в foreground
      messageCleanupService.onAppResumed();
      
      // КРИТИЧНО: Обработка отложенного звонка при возврате из background
      // Если пользователь принял звонок через CallKit, но Navigator был ещё не готов,
      // звонок сохранился в _pendingCall. Обрабатываем его сейчас.
      // Задержка даёт время Flutter engine полностью восстановить UI.
      if (_pendingCall != null && _pendingCall!.isValid && !_isLocked) {
        DebugLogger.info('LIFECYCLE', '📞 Найден pending call при resumed, обрабатываю');
        Future.delayed(const Duration(milliseconds: 300), () {
          processPendingCallAfterUnlock();
        });
      } else if (!_isLocked && !CallStateService.instance.isCallActive.value) {
        // Fallback: проверяем активные CallKit звонки
        // На случай если pending call был null, но пользователь принял звонок через CallKit
        // и приложение развернулось, но _handleCallKitAccept ещё не успел сработать
        Future.delayed(const Duration(milliseconds: 500), () {
          _checkActiveCallOnResumed();
        });
      }
    } else if (state == AppLifecycleState.paused) {
      DebugLogger.info('LIFECYCLE', 'Приложение в background');
      // Блокируем приложение при сворачивании (если PIN включен),
      // но НЕ во время активного звонка и НЕ если есть pending call (иначе может помешать ответу/разговору).
      final hasActiveCall = CallStateService.instance.isCallActive.value;
      final hasPendingCall = _pendingCall != null && _pendingCall!.isValid;
      
      if (authService.config.isPinEnabled && !_isLocked && !hasActiveCall && !hasPendingCall) {
        authService.lock();
        setState(() => _isLocked = true);
        DebugLogger.info('LIFECYCLE', '🔒 App locked on pause');
      } else if (hasPendingCall) {
        DebugLogger.info('LIFECYCLE', '📞 Не блокирую - есть pending call');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orpheus',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    // 1. Нет ключей — экран приветствия
    if (!_keysExist) {
      return WelcomeScreen(onAuthComplete: _onAuthComplete);
    }
    
    // 2. Приложение заблокировано — экран блокировки
    if (_isLocked) {
      return LockScreen(
        onUnlocked: _onUnlocked,
        onDuressMode: _onDuressMode,
        onWipe: _onWipe,
      );
    }
    
    // 3. Проверка лицензии не завершена — загрузка
    if (!_isCheckCompleted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    // 4. Лицензия активна — главный экран
    if (_isLicensed) {
      return const HomeScreen();
    }
    
    // 5. Нет лицензии — экран лицензии
    return LicenseScreen(onLicenseConfirmed: () => setState(() => _isLicensed = true));
  }
}
