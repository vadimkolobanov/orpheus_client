import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:orpheus_project/call_screen.dart';
import 'package:orpheus_project/license_screen.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/screens/lock_screen.dart';
import 'package:orpheus_project/services/auth_service.dart';
import 'package:orpheus_project/services/background_call_service.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/incoming_call_buffer.dart';
import 'package:orpheus_project/services/incoming_message_handler.dart';
import 'package:orpheus_project/services/network_monitor_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/panic_wipe_service.dart';
import 'package:orpheus_project/services/call_state_service.dart';
import 'package:orpheus_project/services/presence_service.dart';
import 'package:orpheus_project/services/call_native_ui_service.dart';
import 'package:orpheus_project/services/telecom_pending_actions_service.dart';
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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Потоки для обновлений UI
final StreamController<String> messageUpdateController = StreamController.broadcast();
final StreamController<Map<String, dynamic>> signalingStreamController = StreamController.broadcast();

/// Буфер входящих сигналов звонка (ICE candidates и т.п.)
final IncomingCallBuffer incomingCallBuffer = IncomingCallBuffer.instance;

bool _hasKeys = false;

/// Глобальный флаг: приложение в foreground (активно)?
bool isAppInForeground = true;

void main() async {
  // КРИТИЧНО: самый ранний лог до любой инициализации
  print('[MAIN] ========== main() STARTED ==========');
  
  WidgetsFlutterBinding.ensureInitialized();
  print('[MAIN] WidgetsFlutterBinding initialized');
  
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
  } catch (e) {
    print("INIT ERROR: $e");
    DebugLogger.error('APP', 'INIT ERROR: $e');
  }

  // Android Telecom: если приложение стартует из системного incoming UI (Answer),
  // важно съесть pending accept ДО того, как мы начнём обрабатывать WS call-offer,
  // иначе возможна гонка (offer придёт раньше и autoAnswer не сработает).
  try {
    await TelecomPendingActionsService.instance.consumeNativePendingAccept();
  } catch (_) {}

  // 4. Криптография
  DebugLogger.info('APP', 'Инициализация криптографии...');
  _hasKeys = await cryptoService.init();
  DebugLogger.info('APP', 'Ключи: ${_hasKeys ? "ЕСТЬ" : "НЕТ"}');

  // 5. Сервис авторизации (PIN, duress)
  DebugLogger.info('APP', 'Инициализация AuthService...');
  await authService.init();
  DebugLogger.info('APP', 'AuthService: PIN=${authService.config.isPinEnabled}, duress=${authService.config.isDuressEnabled}');

  // 6. Panic Wipe Service (тройное нажатие кнопки питания)
  panicWipeService.init();
  panicWipeService.onPanicWipe = () async {
    DebugLogger.warn('APP', '⚠️ PANIC WIPE EXECUTED');
    // После wipe перезапускаем приложение
    _hasKeys = false;
  };

  // 7. Network Monitor Service (мониторинг сети для реконнекта)
  DebugLogger.info('APP', 'Инициализация NetworkMonitorService...');
  await NetworkMonitorService.instance.init();
  DebugLogger.success('APP', 'NetworkMonitorService инициализирован');

  // 8. WebSocket подключение
  if (_hasKeys && cryptoService.publicKeyBase64 != null) {
    DebugLogger.info('APP', 'Подключение WebSocket...');
    websocketService.connect(cryptoService.publicKeyBase64!);
  }

  // 9. Слушаем сообщения
  _listenForMessages();

  DebugLogger.success('APP', '✅ Приложение запущено');
  runApp(const MyApp());
}

void _listenForMessages() {
  final handler = IncomingMessageHandler(
    crypto: _IncomingCryptoAdapter(cryptoService),
    database: _IncomingDatabaseAdapter(DatabaseService.instance),
    notifications: _IncomingNotificationsAdapter(),
    callBuffer: incomingCallBuffer,
    openCallScreen: ({required contactPublicKey, required offer}) {
      final shouldAutoAnswer =
          TelecomPendingActionsService.instance.shouldAutoAnswerForCaller(contactPublicKey);
      if (shouldAutoAnswer) {
        TelecomPendingActionsService.instance.markAutoAnswerConsumed();
      }
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (context) => CallScreen(
          contactPublicKey: contactPublicKey,
          offer: offer,
          autoAnswer: shouldAutoAnswer,
        ),
      ));
    },
    emitSignaling: (msg) => signalingStreamController.add(msg),
    emitChatUpdate: (senderKey) => messageUpdateController.add(senderKey),
    isAppInForeground: () => isAppInForeground,
    isCallActive: () => CallStateService.instance.isCallActive.value,
    suppressCallNotification: (senderKey) =>
        TelecomPendingActionsService.instance.shouldAutoAnswerForCaller(senderKey),
    tryShowTelecomIncoming: ({
      required String senderPublicKey,
      required String callerName,
      required Map<String, dynamic> offer,
      required int? serverTsMs,
      required String? callId,
    }) async {
      // Best-effort: поднимаем Telecom UI в фоне, кешируя offer в native.
      final ok = await CallNativeUiService.showTelecomIncomingCall(
        callerKey: senderPublicKey,
        callerName: callerName,
        offerJson: json.encode(offer),
        callId: callId,
        serverTsMs: serverTsMs,
      );
      return ok;
    },
  );

  websocketService.stream.listen((messageJson) async {
    try {
      await handler.handleRawMessage(messageJson);
    } catch (e) {
      DebugLogger.error('MAIN', 'Message Handler Error: $e');
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

    // Android Telecom: забираем pending Answer/Reject из нативной части (best-effort).
    _consumeTelecomPendingActionsBestEffort();

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

  Future<void> _consumeTelecomPendingActionsBestEffort() async {
    try {
      DebugLogger.info('MAIN', '_consumeTelecomPendingActionsBestEffort started');
      
      // ВАЖНО: consumeNativePendingAccept() уже был вызван в main() при старте.
      // Здесь мы сначала проверяем, есть ли уже pending в ПАМЯТИ (от предыдущего consume).
      // Если нет — пробуем снова из native (на случай если resumed без полного перезапуска).
      
      var callerKey = TelecomPendingActionsService.instance.peekPendingAcceptedCallerKey();
      DebugLogger.info('MAIN', 'Existing pending in memory: ${callerKey != null ? "yes ($callerKey)" : "no"}');
      
      if (callerKey == null) {
        // Пробуем забрать из native (возможно resumed без перезапуска)
        final hasAccept = await TelecomPendingActionsService.instance.consumeNativePendingAccept();
        DebugLogger.info('MAIN', 'consumeNativePendingAccept: hasAccept=$hasAccept');
        if (hasAccept) {
          callerKey = TelecomPendingActionsService.instance.peekPendingAcceptedCallerKey();
        }
      }
      
      if (callerKey != null && callerKey.isNotEmpty) {
        DebugLogger.info('MAIN', 'Pending accept for callerKey=$callerKey');
        
        final offer =
            TelecomPendingActionsService.instance.takePendingAcceptedOfferIfMatches(callerKey);
        DebugLogger.info('MAIN', 'Offer from pending: ${offer != null ? "present" : "null"}');
        
        // Если offer_data уже есть (кеш из native/WS) — откроем CallScreen и сразу ответим.
        // Если offer_data НЕТ (часто при FCM data-only из-за лимита 4KB), всё равно открываем CallScreen,
        // но он будет ждать поздний call-offer по WS (IncomingWaitingOffer) и авто-ответит когда offer появится.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          DebugLogger.info('MAIN', 'Opening CallScreen for Telecom accept (offer=${offer != null})');
          navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (context) => CallScreen(
              contactPublicKey: callerKey!,
              offer: offer, // может быть null
              autoAnswer: true,
            ),
          ));
          // НЕ очищаем autoAnswer сразу, если offer нет — он нужен чтобы подавить нотификации/дубли,
          // пока offer не придёт и CallScreen не ответит.
          if (offer != null) {
            TelecomPendingActionsService.instance.markAutoAnswerConsumed();
          }
        });
      }

      // 2) Reject: best-effort отправка по WS (если соединение поднято/поднимется быстро).
      final rejectedCallerKey =
          await TelecomPendingActionsService.instance.consumeNativePendingRejectCallerKey();
      if (rejectedCallerKey != null && rejectedCallerKey.isNotEmpty) {
        DebugLogger.info('MAIN', 'Sending call-rejected for $rejectedCallerKey');
        websocketService.sendSignalingMessage(rejectedCallerKey, 'call-rejected', {});
      }
    } catch (e) {
      DebugLogger.error('MAIN', '_consumeTelecomPendingActionsBestEffort error: $e');
    }
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
      // ВАЖНО: если пользователь нажал Answer/Reject в нативном incoming UI,
      // приложение может просто "resumed" (без полного перезапуска) — нужно забрать pending действия здесь.
      _consumeTelecomPendingActionsBestEffort();
      // Переподключение WebSocket при возврате в приложение
      if (cryptoService.publicKeyBase64 != null) {
        websocketService.connect(cryptoService.publicKeyBase64!);
      }
    } else if (state == AppLifecycleState.paused) {
      DebugLogger.info('LIFECYCLE', 'Приложение в background');
      // Блокируем приложение при сворачивании (если PIN включен),
      // но НЕ во время активного звонка (иначе может помешать ответу/разговору).
      if (authService.config.isPinEnabled && !_isLocked && !CallStateService.instance.isCallActive.value) {
        authService.lock();
        setState(() => _isLocked = true);
        DebugLogger.info('LIFECYCLE', '🔒 App locked on pause');
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
