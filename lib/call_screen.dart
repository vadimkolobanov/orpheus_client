// lib/call_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orpheus_project/main.dart'; // Доступ к websocketService и signalingStreamController
import 'package:orpheus_project/services/sound_service.dart';
import 'package:orpheus_project/services/webrtc_service.dart';

enum CallState { Dialing, Incoming, Connecting, Connected, Rejected, Failed }

class CallScreen extends StatefulWidget {
  final String contactPublicKey;
  // Если offer != null, значит это входящий звонок
  final Map<String, dynamic>? offer;

  const CallScreen({
    super.key,
    required this.contactPublicKey,
    this.offer,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  final _webrtcService = WebRTCService();
  final _renderer = RTCVideoRenderer();

  late StreamSubscription _signalingSubscription;
  late StreamSubscription _webrtcLogSubscription;

  late CallState _callState;
  bool _isHangingUp = false; // Флаг для защиты от двойного сброса
  bool _isSpeakerOn = false;

  final _soundService = SoundService.instance;
  late AnimationController _pulseAnimationController;
  final List<WebRTCLog> _logs = [];

  @override
  void initState() {
    super.initState();
    // Определяем начальное состояние: Входящий или Исходящий
    _callState = widget.offer != null ? CallState.Incoming : CallState.Dialing;

    // Анимация пульсации иконки
    _pulseAnimationController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2)
    )..repeat(reverse: true);

    _initRenderersAndSignaling();

    // Если мы звоним, начинаем процесс инициализации
    if (_callState == CallState.Dialing) {
      _initiateCall();
      _tryPlaySound(_soundService.playDialingSound);
    } else {
      // Если входящий, играем рингтон (в данном случае тот же звук дозвона для примера)
      _tryPlaySound(_soundService.playDialingSound);
    }
  }

  void _tryPlaySound(Future<void> Function() playFunction) {
    try {
      playFunction();
    } catch (e) {
      print("Ошибка воспроизведения звука: $e");
    }
  }

  Future<void> _initRenderersAndSignaling() async {
    await _renderer.initialize();

    // 1. Слушаем логи WebRTC для определения момента соединения
    _webrtcLogSubscription = _webrtcService.logStream.listen((logs) {
      if (!mounted) return;

      final lastLog = logs.isNotEmpty ? logs.last : null;
      if (lastLog == null) return;

      setState(() {
        _logs.clear();
        _logs.addAll(logs);
      });

      if (lastLog.state == WebRTCConnectionState.Connected) {
        // Соединение установлено!
        if (_callState != CallState.Connected) {
          _soundService.stopAllSounds();
          _tryPlaySound(_soundService.playConnectedSound);
          setState(() {
            _callState = CallState.Connected;
          });
        }
      } else if (lastLog.state == WebRTCConnectionState.Failed) {
        if (mounted && _callState != CallState.Failed) {
          setState(() => _callState = CallState.Failed);
          // Сообщаем о сбое и закрываемся через паузу
          Future.delayed(const Duration(seconds: 3), () => _hangUp());
        }
      }
    });

    // 2. Слушаем входящие сигналы от сервера (через контроллер в main.dart)
    _signalingSubscription = signalingStreamController.stream.listen((signal) {
      // Фильтруем сигналы: только от того, с кем говорим
      if (!mounted || signal['sender_pubkey'] != widget.contactPublicKey) return;

      final type = signal['type'] as String;

      if (type == 'call-rejected') {
        // Собеседник отклонил звонок
        _soundService.stopAllSounds();
        if (mounted) setState(() => _callState = CallState.Rejected);
        Future.delayed(const Duration(seconds: 2), () => _cleanupResourcesAndClose());

      } else if (type == 'call-answer') {
        // Собеседник ответил
        final data = signal['data'] as Map<String, dynamic>;
        _webrtcService.handleAnswer(data);
        if (mounted) setState(() => _callState = CallState.Connecting);

      } else if (type == 'ice-candidate') {
        // Прилетел ICE кандидат (путь для соединения)
        final data = signal['data'] as Map<String, dynamic>;
        _webrtcService.addCandidate(data);

      } else if (type == 'hang-up') {
        // Собеседник положил трубку
        _cleanupResourcesAndClose(remoteHangup: true);
      }
    });

    // Периодически обновляем поток видео (если есть), хотя для аудио-звонка это опционально
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_renderer.srcObject != _webrtcService.remoteStream) {
        if (mounted) setState(() {
          _renderer.srcObject = _webrtcService.remoteStream;
        });
      }
    });
  }

  // --- Логика исходящего звонка ---
  Future<void> _initiateCall() async {
    await _webrtcService.initialize();
    await _webrtcService.initiateCall(
      onOfferCreated: (offer) => websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-offer', offer),
      onCandidateCreated: (candidate) => websocketService.sendSignalingMessage(widget.contactPublicKey, 'ice-candidate', candidate),
    );
  }

  // --- Логика ответа на входящий звонок (ИСПРАВЛЕНО) ---
  void _acceptCall() async {
    // Защита от множественных нажатий
    if (_callState == CallState.Connecting || _callState == CallState.Connected) return;

    if (mounted) {
      setState(() => _callState = CallState.Connecting);
    }
    // Останавливаем рингтон входящего вызова
    _soundService.stopAllSounds();

    try {
      await _webrtcService.initialize();
      await _webrtcService.answerCall(
        offer: widget.offer!,
        onAnswerCreated: (answer) {
          // Отправляем ответ собеседнику
          websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-answer', answer);
          // Выключаем громкую связь по умолчанию (прикладываем к уху)
          _setSpeakerphone(false);
        },
        onCandidateCreated: (candidate) {
          websocketService.sendSignalingMessage(widget.contactPublicKey, 'ice-candidate', candidate);
        },
      );
    } catch (e) {
      print("Ошибка при ответе на звонок: $e");
      _hangUp();
    }
  }

  // --- Логика отклонения вызова ---
  void _rejectCall() {
    _hangUp(); // _hangUp внутри сам определит, что это отклонение, так как состояние Incoming
  }

  // --- Логика завершения звонка (ИСПРАВЛЕНО) ---
  void _hangUp() {
    if (_isHangingUp) return;
    _isHangingUp = true;

    // Определяем тип сигнала
    String signalType = 'hang-up';
    if (_callState == CallState.Incoming) {
      signalType = 'call-rejected';
    }

    // 1. Пытаемся уведомить собеседника
    try {
      websocketService.sendSignalingMessage(widget.contactPublicKey, signalType, {});
    } catch (e) {
      print("Ошибка отправки сигнала завершения: $e");
    }

    // 2. Чистим ресурсы и закрываем экран
    _cleanupResourcesAndClose();
  }

  // --- Общий метод очистки ресурсов и выхода ---
  void _cleanupResourcesAndClose({bool remoteHangup = false}) {
    _signalingSubscription.cancel();
    _webrtcLogSubscription.cancel();
    _soundService.stopAllSounds();

    // Если положили трубку удаленно или мы сбросили - играем звук завершения
    _tryPlaySound(_soundService.playDisconnectedSound);

    _webrtcService.hangUp();

    if (mounted) {
      // Даем пользователю долю секунды услышать звук завершения или увидеть статус
      // Но для отзывчивости лучше закрывать почти сразу
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  // Используется в dispose, если окно закрыли системной кнопкой "Назад"
  void _cleanupResourcesOnly() {
    _signalingSubscription.cancel();
    _webrtcLogSubscription.cancel();
    _soundService.stopAllSounds();
    _webrtcService.hangUp();
  }

  Future<void> _setSpeakerphone(bool enabled) async {
    await Helper.setSpeakerphoneOn(enabled);
    if (mounted) setState(() {
      _isSpeakerOn = enabled;
    });
  }

  @override
  void dispose() {
    _pulseAnimationController.dispose();
    _renderer.dispose();

    // Если мы выходим, а звонок формально не завершен через кнопку - завершаем его
    if (!_isHangingUp) {
      // Пытаемся отправить hang-up "вдогонку"
      try {
        websocketService.sendSignalingMessage(widget.contactPublicKey, 'hang-up', {});
      } catch (_) {}
      _cleanupResourcesOnly();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Темный фон для звонка
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.95),
      body: SafeArea(
        child: Center(
          child: Column(
            children: [
              // Скрытый рендерер видео (нужен для работы WebRTC, даже если аудио)
              SizedBox(height: 1.0, width: 1.0, child: Opacity(opacity: 0.0, child: RTCVideoView(_renderer))),

              const Spacer(flex: 1),

              // Анимированная иконка статуса
              FadeTransition(
                opacity: _pulseAnimationController.drive(CurveTween(curve: Curves.easeInOut)),
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getStatusIndicatorColor().withOpacity(0.3),
                    border: Border.all(color: _getStatusIndicatorColor(), width: 2),
                  ),
                  child: Icon(_getStatusIndicatorIcon(), color: Colors.white, size: 40),
                ),
              ),

              const SizedBox(height: 24),

              // Текстовый статус
              Text(
                _getCallStatusText(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),

              const SizedBox(height: 12),

              // Логи (для отладки) - можно скрыть в релизе
              Expanded(
                flex: 2,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: StreamBuilder<List<WebRTCLog>>(
                    stream: _webrtcService.logStream,
                    builder: (context, snapshot) {
                      final logs = snapshot.data ?? [];
                      return ListView.builder(
                        reverse: true,
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final log = logs.reversed.toList()[index];
                          return Text(
                            log.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              const Spacer(flex: 1),

              // Кнопки управления
              _buildCallActions(),

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  String _getCallStatusText() {
    switch (_callState) {
      case CallState.Dialing: return 'Вызов...';
      case CallState.Incoming: return 'Входящий звонок';
      case CallState.Connecting: return 'Соединение...';
      case CallState.Connected: return 'Звонок активен';
      case CallState.Rejected: return 'Звонок отклонен';
      case CallState.Failed: return 'Ошибка соединения';
    }
  }

  Color _getStatusIndicatorColor() {
    switch (_callState) {
      case CallState.Dialing:
      case CallState.Connecting: return Colors.blue.shade300;
      case CallState.Incoming: return Colors.green.shade300;
      case CallState.Connected: return Colors.lightGreenAccent.shade400;
      case CallState.Rejected:
      case CallState.Failed: return Colors.red.shade300;
    }
  }

  IconData _getStatusIndicatorIcon() {
    switch (_callState) {
      case CallState.Dialing:
      case CallState.Connecting: return Icons.phone_forwarded_outlined;
      case CallState.Incoming: return Icons.ring_volume_outlined;
      case CallState.Connected: return Icons.mic_none_outlined;
      case CallState.Rejected:
      case CallState.Failed: return Icons.phone_disabled_outlined;
    }
  }

  Widget _buildCallActions() {
    if (_callState == CallState.Rejected || _callState == CallState.Failed) {
      return const SizedBox(height: 76);
    }

    if (_callState == CallState.Connected) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            backgroundColor: Colors.white.withOpacity(0.2),
            onPressed: () => _setSpeakerphone(!_isSpeakerOn),
          ),
          _buildActionButton(
            icon: Icons.call_end,
            backgroundColor: Colors.redAccent,
            onPressed: _hangUp,
          ),
          // Заглушка для микрофона (пока без функционала Mute)
          _buildActionButton(
            icon: Icons.mic_off_outlined,
            backgroundColor: Colors.white.withOpacity(0.2),
            onPressed: () {},
          ),
        ],
      );
    } else if (_callState == CallState.Incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildActionButton(
            icon: Icons.call_end,
            backgroundColor: Colors.redAccent,
            onPressed: _rejectCall,
          ),
          _buildActionButton(
            icon: Icons.call,
            backgroundColor: Colors.green,
            onPressed: _acceptCall,
          ),
        ],
      );
    } else {
      // Dialing or Connecting
      // Всегда даем возможность сбросить, даже если соединяемся
      return _buildActionButton(
        icon: Icons.call_end,
        backgroundColor: Colors.redAccent,
        onPressed: _hangUp,
      );
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback onPressed,
  }) {
    return IconButton.filled(
      style: IconButton.styleFrom(
        backgroundColor: backgroundColor,
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(20),
      ),
      icon: Icon(icon, color: Colors.white, size: 36),
      onPressed: onPressed,
    );
  }
}