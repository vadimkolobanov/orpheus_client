 import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:orpheus_project/services/websocket_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/crypto_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/config.dart';

/// Постоянный foreground service для гарантированной доставки уведомлений.
/// Работает постоянно (даже когда приложение закрыто), держит WebSocket соединение,
/// обрабатывает FCM и локальные уведомления.
@pragma('vm:entry-point')
class NotificationForegroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// ID канала для уведомления сервиса (минимальный приоритет, можно скрыть)
  static const String _serviceChannelId = 'orpheus_notification_service';
  static const String _serviceChannelName = 'Служба уведомлений';

  /// ID уведомления сервиса
  static const int _serviceNotificationId = 999;

  /// Инициализация сервиса (вызывается один раз при старте приложения)
  static Future<void> initialize() async {
    // Создаём канал уведомлений для сервиса (минимальный приоритет)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _serviceChannelId,
      _serviceChannelName,
      description: 'Служба для гарантированной доставки уведомлений',
      importance: Importance.low, // Низкий приоритет - не мешает пользователю
      enableVibration: false,
      playSound: false,
      showBadge: false,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Конфигурация фонового сервиса
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: true, // Автоматический запуск при старте приложения
        isForegroundMode: true, // Foreground service для выживания
        autoStartOnBoot: true, // Запуск после перезагрузки
        
        // Параметры уведомления
        notificationChannelId: _serviceChannelId,
        initialNotificationTitle: 'Orpheus',
        initialNotificationContent: 'Служба уведомлений активна',
        foregroundServiceNotificationId: _serviceNotificationId,
        
        // Тип foreground service для уведомлений (Android 14+)
        foregroundServiceTypes: [
          AndroidForegroundType.dataSync, // Для синхронизации данных/уведомлений
        ],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
    
    print("🔔 NotificationForegroundService initialized");
  }

  /// Запуск сервиса (вызывается при старте приложения)
  static Future<void> start() async {
    if (!await _service.isRunning()) {
      await _service.startService();
      print("🔔 NotificationForegroundService STARTED");
    } else {
      print("🔔 NotificationForegroundService already running");
    }
  }

  /// Остановка сервиса (обычно не требуется, но можно для отладки)
  static Future<void> stop() async {
    if (await _service.isRunning()) {
      _service.invoke("stopService");
      print("🔔 NotificationForegroundService STOPPED");
    }
  }

  /// Проверка работает ли сервис
  static Future<bool> isRunning() async {
    return await _service.isRunning();
  }

  /// Обновление статуса в уведомлении
  static void updateStatus(String status) {
    _service.invoke('updateNotification', {
      'title': 'Orpheus',
      'content': status,
    });
  }

  /// Хранилище активных звонков, обрабатываемых в main isolate
  /// Ключ: callerKey, значение: timestamp когда звонок начал обрабатываться
  static final Map<String, int> _activeCallsInMain = {};

  /// Отметить звонок как обрабатываемый в main isolate
  static void markCallHandledInMain(String callerKey) {
    _activeCallsInMain[callerKey] = DateTime.now().millisecondsSinceEpoch;
    print("🔔 Marked call as handled in main: ${callerKey.substring(0, 8)}...");
  }

  /// Проверить, обрабатывается ли звонок в main isolate
  static bool isCallHandledInMain(String callerKey) {
    final timestamp = _activeCallsInMain[callerKey];
    if (timestamp == null) return false;
    
    // Удаляем старые записи (старше 30 секунд)
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - timestamp > 30000) {
      _activeCallsInMain.remove(callerKey);
      return false;
    }
    
    return true;
  }

  /// Удалить звонок из списка активных
  static void removeCallFromMain(String callerKey) {
    _activeCallsInMain.remove(callerKey);
    print("🔔 Removed call from main tracking: ${callerKey.substring(0, 8)}...");
  }

  /// Entry point для Android foreground service
  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    print("🔔 NotificationForegroundService _onStart called");

    // Инициализация Firebase в изоляте (критично для NotificationService)
    try {
      await Firebase.initializeApp();
      print("🔔 Firebase initialized in service isolate");
    } catch (e) {
      print("🔔 ERROR initializing Firebase in service: $e");
      // Продолжаем работу даже если Firebase не инициализирован
    }

    // Инициализация локальных уведомлений в изоляте (критично для показа уведомлений)
    try {
      await NotificationService.initLocalNotificationsInIsolate();
      print("🔔 Local notifications initialized in service isolate");
    } catch (e) {
      print("🔔 ERROR initializing local notifications in service: $e");
    }

    // Инициализация сервисов в изоляте
    final cryptoService = CryptoService();
    await cryptoService.init();
    
    // Инициализация базы данных в изоляте (lazy initialization через getter)
    try {
      await DatabaseService.instance.database;
      print("🔔 DatabaseService initialized in service isolate");
    } catch (e) {
      print("🔔 ERROR initializing DatabaseService in service: $e");
    }
    
    final websocketService = WebSocketService();
    // НЕ создаем экземпляр NotificationService - используем только статические методы

    // Подключение WebSocket если есть ключи
    String? publicKey = cryptoService.publicKeyBase64;
    if (publicKey != null && publicKey.isNotEmpty) {
      print("🔔 Connecting WebSocket in service...");
      websocketService.connect(publicKey);
    }

    // Мониторинг состояния WebSocket соединения
    StreamSubscription<ConnectionStatus>? statusSubscription;
    statusSubscription = websocketService.status.listen((status) {
      String statusText;
      switch (status) {
        case ConnectionStatus.Connected:
          statusText = 'Соединение установлено';
          break;
        case ConnectionStatus.Connecting:
          statusText = 'Подключение...';
          break;
        case ConnectionStatus.Disconnected:
          statusText = 'Соединение разорвано';
          break;
      }
      
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Orpheus',
          content: statusText,
        );
      }
    });

    // Обработка сообщений WebSocket в сервисе
    StreamSubscription<String>? messageSubscription;
    messageSubscription = websocketService.stream.listen((messageJson) async {
      try {
        final messageData = json.decode(messageJson) as Map<String, dynamic>;
        final type = messageData['type'] as String?;
        
        print("🔔 WS in service: type=$type");
        
        // Обработка входящих звонков через WebSocket
        if (type == 'call-offer') {
          final senderKey = messageData['sender_pubkey'] as String?;
          final rawData = messageData['data'];
          
          if (senderKey != null && senderKey.isNotEmpty) {
            final shortKey = senderKey.length > 8 ? senderKey.substring(0, 8) : senderKey;
            print("🔔 Incoming call in service from: $shortKey...");
            
            // Проверяем, обрабатывается ли звонок уже в main isolate
            if (isCallHandledInMain(senderKey)) {
              print("🔔 Call already handled in main isolate, skipping notification");
              return;
            }
            
            // Извлекаем данные оффера
            Map<String, dynamic>? offerData;
            if (rawData != null && rawData is Map<String, dynamic>) {
              offerData = rawData;
              print("🔔 Offer data extracted in service: ${offerData.isNotEmpty}");
            }
            
            // Получаем имя контакта из базы данных
            String callerName = 'Неизвестный';
            try {
              final contact = await DatabaseService.instance.getContact(senderKey);
              if (contact != null && contact.name.isNotEmpty) {
                callerName = contact.name;
              }
            } catch (e) {
              print("🔔 ERROR getting contact name: $e");
            }
            
            // Показываем локальное уведомление о звонке только если приложение закрыто/свернуто
            // (если приложение открыто, main.dart уже обработает звонок)
            try {
              await NotificationService.showCallNotification(
                callerKey: senderKey,
                callerName: callerName,
                offerData: offerData,
              );
              print("🔔 Local call notification shown in service");
            } catch (e) {
              print("🔔 ERROR showing call notification in service: $e");
            }
          } else {
            print("🔔 WARN: call-offer received but senderKey is null or empty");
          }
        }
        
        // Обработка новых сообщений через WebSocket
        if (type == 'chat') {
          final senderKey = messageData['sender_pubkey'] as String?;
          final payload = messageData['payload'] as String?;
          
          if (senderKey != null && senderKey.isNotEmpty && payload != null && payload.isNotEmpty) {
            final shortKey = senderKey.length > 8 ? senderKey.substring(0, 8) : senderKey;
            print("🔔 New message in service from: $shortKey...");
            
            // Расшифровываем сообщение
            try {
              final decryptedMessage = await cryptoService.decrypt(senderKey, payload);
              
              // Получаем имя контакта
              String senderName = 'Новое сообщение';
              try {
                final contact = await DatabaseService.instance.getContact(senderKey);
                if (contact != null && contact.name.isNotEmpty) {
                  senderName = contact.name;
                }
              } catch (e) {
                print("🔔 ERROR getting contact name: $e");
              }
              
              // Показываем локальное уведомление о сообщении (резерв, если FCM не доставил)
              try {
                await NotificationService.showMessageNotification(
                  senderKey: senderKey,
                  senderName: senderName,
                );
                print("🔔 Local message notification shown in service");
              } catch (e) {
                print("🔔 ERROR showing message notification in service: $e");
              }
            } catch (e) {
              print("🔔 ERROR decrypting message in service: $e");
            }
          } else {
            print("🔔 WARN: chat message received but senderKey or payload is null/empty");
          }
        }
      } catch (e) {
        print("🔔 ERROR processing WS message in service: $e");
      }
    });

    // Обработка команды остановки
    service.on('stopService').listen((event) {
      print("🔔 NotificationForegroundService received stopService command");
      statusSubscription?.cancel();
      messageSubscription?.cancel();
      service.stopSelf();
    });

    // Обработка обновления уведомления (используется BackgroundCallService для звонков)
    service.on('updateNotification').listen((event) {
      if (event != null && service is AndroidServiceInstance) {
        final title = event['title'] as String? ?? 'Orpheus';
        final content = event['content'] as String? ?? 'Служба активна';
        
        service.setForegroundNotificationInfo(
          title: title,
          content: content,
        );
        print("🔔 Service notification updated: $title - $content");
      }
    });

    // Устанавливаем как foreground service
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    // Периодическая проверка соединения и переподключение при необходимости
    Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          // Проверяем состояние WebSocket
          final currentStatus = websocketService.currentStatus;
          if (currentStatus == ConnectionStatus.Disconnected) {
            print("🔔 WebSocket disconnected, attempting reconnect...");
            final currentPublicKey = cryptoService.publicKeyBase64;
            if (currentPublicKey != null && currentPublicKey.isNotEmpty) {
              websocketService.connect(currentPublicKey);
              publicKey = currentPublicKey; // Обновляем переменную
            } else {
              print("🔔 WARN: Public key is null or empty, cannot reconnect");
            }
          }
          
          // Обновляем статус в уведомлении
          String statusText;
          switch (currentStatus) {
            case ConnectionStatus.Connected:
              statusText = 'Соединение установлено';
              break;
            case ConnectionStatus.Connecting:
              statusText = 'Подключение...';
              break;
            case ConnectionStatus.Disconnected:
              statusText = 'Соединение разорвано';
              break;
          }
          
          service.setForegroundNotificationInfo(
            title: 'Orpheus',
            content: statusText,
          );
        } else {
          timer.cancel();
          statusSubscription?.cancel();
          messageSubscription?.cancel();
        }
      }
    });
  }

  /// iOS background handler
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    return true;
  }
}

