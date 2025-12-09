import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/services/background_call_service.dart';
import 'package:orpheus_project/services/notification_service.dart';
import 'package:orpheus_project/services/sound_service.dart';
import 'package:orpheus_project/services/webrtc_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/models/chat_message_model.dart';
import 'package:orpheus_project/widgets/call/background_painters.dart';
import 'package:orpheus_project/widgets/call/control_panel.dart';

enum CallState { Dialing, Incoming, Connecting, Connected, Rejected, Failed }

class CallScreen extends StatefulWidget {
  final String contactPublicKey;
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
  // Сервисы
  final _webrtcService = WebRTCService();
  final _renderer = RTCVideoRenderer();

  // Подписки
  StreamSubscription? _signalingSubscription;
  StreamSubscription? _webrtcLogSubscription;

  // Состояние звонка
  CallState _callState = CallState.Dialing;
  String _displayName = "Аноним";
  String _debugStatus = "Init";
  String _durationText = "00:00";

  // Управление устройствами
  bool _isSpeakerOn = false;
  bool _isMicMuted = false;

  // Флаги жизненного цикла
  bool _isDisposed = false;
  bool _messagesSent = false;

  // Логирование
  bool _showDebugLogs = false;
  final List<String> _debugLogs = [];
  final ScrollController _logScrollController = ScrollController();

  // Анимации
  late AnimationController _pulseController;
  late AnimationController _particlesController;
  late AnimationController _waveController;

  // Таймеры
  Timer? _durationTimer;
  final Stopwatch _stopwatch = Stopwatch();

  // Визуализация аудио
  final List<double> _audioWaveData = List.generate(20, (_) => 0.0);
  Timer? _waveTimer;

  @override
  void initState() {
    super.initState();

    _displayName = widget.contactPublicKey.substring(0, 8);
    _resolveContactName();

    _callState = widget.offer != null ? CallState.Incoming : CallState.Dialing;

    // 1. Запуск foreground service для звонка
    _startBackgroundMode();

    // 2. Скрываем уведомление о входящем звонке (экран уже открыт)
    NotificationService.hideCallNotification();

    // 3. Анимации
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: false);

    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // 4. Старт WebRTC
    _initCallSequence();
  }

  Future<void> _startBackgroundMode() async {
    await BackgroundCallService.startCallService();
  }

  Future<void> _resolveContactName() async {
    try {
      final contacts = await DatabaseService.instance.getContacts();
      final found = contacts.firstWhere(
        (c) => c.publicKey == widget.contactPublicKey,
        orElse: () => null as dynamic,
      );

      if (found.toString() != 'null' && mounted) {
        setState(() {
          _displayName = found.name;
        });
      }
    } catch (_) {}
  }

  Future<void> _initCallSequence() async {
    await _renderer.initialize();

    // Подписка на логи WebRTC
    _webrtcLogSubscription = _webrtcService.onDebugLog.listen((log) {
      _addLog(log);

      if (log.contains("Connected")) {
        if (_callState != CallState.Connected) _onConnected();
      } else if (log.contains("Failed")) {
        if (!_isDisposed) _onError("Сбой (ICE)");
      }

      if (log.contains("REMOTE TRACK RECEIVED") || log.contains("Remote stream assigned")) {
        _attachRemoteStream();
      }
    });

    // Подписка на сигналы WebSocket
    _signalingSubscription = signalingStreamController.stream.listen((signal) async {
      if (_isDisposed || signal['sender_pubkey'] != widget.contactPublicKey) {
        return;
      }

      final type = signal['type'];
      final data = signal['data'];

      if (type == 'call-answer') {
        if (mounted) setState(() => _debugStatus = "Answer received");
        await _webrtcService.handleAnswer(data);
        if (_callState != CallState.Connected && mounted) {
          setState(() => _callState = CallState.Connecting);
        }
      } else if (type == 'ice-candidate') {
        await _webrtcService.addCandidate(data);
      } else if (type == 'hang-up' || type == 'call-rejected') {
        _addLog("📞 Получен $type - завершаем звонок");
        _onRemoteHangup();
      }
    });

    // Применяем буферизованные ICE кандидаты
    if (_callState == CallState.Incoming) {
      final bufferedCandidates = getAndClearIncomingCallBuffer(widget.contactPublicKey);
      if (bufferedCandidates.isNotEmpty) {
        _addLog("📦 Применение ${bufferedCandidates.length} буферизованных кандидатов");
        for (final candidateMsg in bufferedCandidates) {
          final data = candidateMsg['data'] as Map<String, dynamic>;
          await _webrtcService.addCandidate(data);
        }
      }
    }

    if (_callState == CallState.Dialing) {
      SoundService.instance.playDialingSound();
      _startOutgoingCall();
    } else {
      SoundService.instance.playDialingSound();
    }
  }

  // --- ЛОГИКА ЗВОНКА ---

  Future<void> _startOutgoingCall() async {
    try {
      await _webrtcService.initiateCall(
        onOfferCreated: (offer) {
          _addLog("📤 call-offer");
          websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-offer', offer);
        },
        onCandidateCreated: (cand) {
          _addLog("📤 ice-candidate");
          websocketService.sendSignalingMessage(widget.contactPublicKey, 'ice-candidate', cand);
        },
      );
    } catch (e) {
      _addLog("ERROR: $e");
      _onError("Mic Error");
    }
  }

  void _acceptCall() async {
    SoundService.instance.stopAllSounds();
    if (mounted) setState(() => _callState = CallState.Connecting);

    try {
      await _webrtcService.answerCall(
        offer: widget.offer!,
        onAnswerCreated: (ans) {
          _addLog("📤 call-answer");
          websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-answer', ans);
        },
        onCandidateCreated: (cand) {
          _addLog("📤 ice-candidate");
          websocketService.sendSignalingMessage(widget.contactPublicKey, 'ice-candidate', cand);
        },
      );
    } catch (e) {
      _onError("Connect Error");
    }
  }

  void _endCallButton() async {
    if (_messagesSent) return;  // Предотвращаем повторные вызовы
    _messagesSent = true;

    final currentState = _callState;
    String signal = currentState == CallState.Incoming ? 'call-rejected' : 'hang-up';

    // СНАЧАЛА отправляем hang-up сигнал
    print("📞 Отправка $signal к ${widget.contactPublicKey.substring(0, 8)}...");
    websocketService.sendSignalingMessage(widget.contactPublicKey, signal, {});

    // Небольшая задержка чтобы WebSocket успел отправить сообщение
    await Future.delayed(const Duration(milliseconds: 100));

    // Системные сообщения в чат
    if (currentState == CallState.Connected) {
      _saveCallStatusMessageLocally("Исходящий звонок", true);
      _sendCallStatusMessageToContact("Входящий звонок");
    } else if (currentState == CallState.Incoming) {
      _saveCallStatusMessageLocally("Пропущен звонок", false);
    } else if (currentState == CallState.Dialing) {
      _saveCallStatusMessageLocally("Исходящий звонок", true);
      _sendCallStatusMessageToContact("Пропущен звонок");
    }

    _safePop();
  }

  void _onRemoteHangup() {
    if (_isDisposed || _messagesSent) return;
    SoundService.instance.stopAllSounds();
    SoundService.instance.playDisconnectedSound();

    final wasConnected = _callState == CallState.Connected;
    if (mounted) setState(() => _callState = CallState.Rejected);

    if (wasConnected) {
      _saveCallStatusMessageLocally("Входящий звонок", false);
      _sendCallStatusMessageToContact("Исходящий звонок");
      _messagesSent = true;
    }

    Future.delayed(const Duration(seconds: 1), _safePop);
  }

  void _onConnected() {
    SoundService.instance.stopAllSounds();
    SoundService.instance.playConnectedSound();

    if (mounted) {
      setState(() => _callState = CallState.Connected);
      _waveController.repeat();
      _attachRemoteStream();
    }

    // Анимация волн
    _waveTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _isDisposed || _callState != CallState.Connected) {
        timer.cancel();
        return;
      }
      setState(() {
        for (int i = 0; i < _audioWaveData.length; i++) {
          _audioWaveData[i] = (0.2 + (i % 3) * 0.1) +
              (DateTime.now().millisecondsSinceEpoch % 1000) / 1000 * 0.3;
        }
      });
    });

    // Таймер длительности
    _stopwatch.start();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final elapsed = _stopwatch.elapsed;
      final min = elapsed.inMinutes.toString().padLeft(2, '0');
      final sec = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      setState(() => _durationText = "$min:$sec");
      
      // Обновляем уведомление foreground service
      BackgroundCallService.updateCallDuration(_durationText, _displayName);
    });
  }

  void _onError(String msg) {
    if (_isDisposed) return;
    if (mounted) setState(() => _callState = CallState.Failed);
    Future.delayed(const Duration(seconds: 2), _safePop);
  }

  void _safePop() {
    getAndClearIncomingCallBuffer(widget.contactPublicKey);
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // --- УПРАВЛЕНИЕ МЕДИА ---

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  void _toggleMic() {
    final tracks = _webrtcService.localStream?.getAudioTracks();
    if (tracks != null && tracks.isNotEmpty) {
      setState(() => _isMicMuted = !_isMicMuted);
      tracks[0].enabled = !_isMicMuted;
    }
  }

  void _attachRemoteStream() {
    final remoteStream = _webrtcService.remoteStream;
    if (remoteStream != null && mounted) {
      if (_renderer.srcObject != remoteStream) {
        _renderer.srcObject = remoteStream;
      }
    }
  }

  // --- СИСТЕМНЫЕ СООБЩЕНИЯ ---

  Future<void> _saveCallStatusMessageLocally(String messageText, bool isSentByMe) async {
    try {
      final callMessage = ChatMessage(
        text: messageText,
        isSentByMe: isSentByMe,
        status: MessageStatus.sent,
        isRead: true,
      );
      await DatabaseService.instance.addMessage(callMessage, widget.contactPublicKey);
      messageUpdateController.add(widget.contactPublicKey);
    } catch (e) {
      print("Error saving local msg: $e");
    }
  }

  Future<void> _sendCallStatusMessageToContact(String messageText) async {
    try {
      final payload = await cryptoService.encrypt(widget.contactPublicKey, messageText);
      websocketService.sendChatMessage(widget.contactPublicKey, payload);
    } catch (e) {
      print("Error sending remote msg: $e");
    }
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _debugLogs.add("${DateTime.now().toString().substring(11, 19)} $message");
    });
    if (_showDebugLogs) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_logScrollController.hasClients) {
          _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
        }
      });
    }
  }

  String _getStatusText() {
    switch (_callState) {
      case CallState.Dialing:
        return "Вызов...";
      case CallState.Incoming:
        return "Входящий звонок";
      case CallState.Connecting:
        return "Соединение...";
      case CallState.Rejected:
        return "Завершен";
      case CallState.Failed:
        return "Сбой";
      default:
        return "";
    }
  }

  @override
  void dispose() {
    // 1. Останавливаем foreground service
    BackgroundCallService.stopCallService();

    // 2. Чистим буфер
    getAndClearIncomingCallBuffer(widget.contactPublicKey);

    // 3. Отправляем HangUp если закрыли свайпом (не через кнопку)
    if (!_messagesSent) {
      final finalState = _callState;
      print("📞 Dispose: отправка hang-up (state=$finalState)");
      
      if (finalState == CallState.Connected || finalState == CallState.Dialing) {
        websocketService.sendSignalingMessage(widget.contactPublicKey, 'hang-up', {});

        if (finalState == CallState.Connected) {
          _saveCallStatusMessageLocally("Исходящий звонок", true);
          _sendCallStatusMessageToContact("Входящий звонок");
        } else if (finalState == CallState.Dialing) {
          _saveCallStatusMessageLocally("Исходящий звонок", true);
          _sendCallStatusMessageToContact("Пропущен звонок");
        }
      } else if (finalState == CallState.Incoming) {
        websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-rejected', {});
        _saveCallStatusMessageLocally("Пропущен звонок", false);
      }
    }

    _isDisposed = true;
    _pulseController.dispose();
    _particlesController.dispose();
    _waveController.dispose();
    _renderer.srcObject = null;
    _renderer.dispose();
    _stopwatch.stop();
    _durationTimer?.cancel();
    _waveTimer?.cancel();
    _signalingSubscription?.cancel();
    _webrtcLogSubscription?.cancel();
    SoundService.instance.stopAllSounds();

    _webrtcService.hangUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Анимированный фон
          CallBackground(controller: _particlesController),

          // 2. Частицы
          CustomPaint(
            painter: ParticlesPainter(_particlesController.value),
            child: Container(),
          ),

          // 3. Волны (только если Connected)
          if (_callState == CallState.Connected)
            AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) => CustomPaint(
                painter: WavePainter(_waveController.value),
                child: Container(),
              ),
            ),

          // Скрытый VideoView для аудио
          SizedBox(height: 0, width: 0, child: RTCVideoView(_renderer)),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),

                // Скрытая кнопка логов
                GestureDetector(
                  onTap: () => setState(() => _showDebugLogs = !_showDebugLogs),
                  child: const Text(
                    "Secure Call",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Имя контакта
                Text(
                  _displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Статус или Таймер
                if (_callState == CallState.Connected)
                  Text(
                    _durationText,
                    style: const TextStyle(
                      color: Color(0xFF6AD394),
                      fontSize: 24,
                      fontFamily: "monospace",
                    ),
                  )
                else
                  Column(
                    children: [
                      Text(
                        _getStatusText(),
                        style: const TextStyle(color: Colors.grey, fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _debugStatus,
                        style: const TextStyle(color: Colors.red, fontSize: 10),
                      ),
                    ],
                  ),

                const Spacer(),

                // Аватар с анимацией пульсации
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_callState != CallState.Failed && _callState != CallState.Rejected)
                      ...List.generate(3, (index) {
                        return ScaleTransition(
                          scale: Tween(begin: 1.0, end: 1.8 + index * 0.3).animate(
                            CurvedAnimation(
                              parent: _pulseController,
                              curve: Interval(index * 0.2, 1.0, curve: Curves.easeOut),
                            ),
                          ),
                          child: FadeTransition(
                            opacity: Tween(begin: 0.4 - index * 0.1, end: 0.0).animate(
                              CurvedAnimation(
                                parent: _pulseController,
                                curve: Interval(index * 0.2, 1.0, curve: Curves.easeOut),
                              ),
                            ),
                            child: Container(
                              width: 150 + index * 30,
                              height: 150 + index * 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF6AD394).withOpacity(0.3 - index * 0.1),
                                  width: 2 - index * 0.3,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: _callState == CallState.Connected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF6AD394).withOpacity(0.5),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ]
                            : [],
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: _callState == CallState.Connected
                            ? const Color(0xFF6AD394).withOpacity(0.2)
                            : Colors.grey[800],
                        child: Text(
                          _displayName.isNotEmpty ? _displayName[0].toUpperCase() : "?",
                          style: TextStyle(
                            fontSize: 40,
                            color: _callState == CallState.Connected
                                ? const Color(0xFF6AD394)
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Визуализатор звука
                if (_callState == CallState.Connected) ...[
                  const SizedBox(height: 30),
                  Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(_audioWaveData.length, (index) {
                        final height = _audioWaveData[index] * 50;
                        return Container(
                          width: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6AD394),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          height: height.clamp(5.0, 50.0),
                        );
                      }),
                    ),
                  ),
                ],

                const Spacer(),

                // Панель управления
                CallControlPanel(
                  isIncoming: _callState == CallState.Incoming,
                  isMicMuted: _isMicMuted,
                  isSpeakerOn: _isSpeakerOn,
                  onToggleMic: _toggleMic,
                  onToggleSpeaker: _toggleSpeaker,
                  onEndCall: _endCallButton,
                  onAcceptCall: _acceptCall,
                ),

                const SizedBox(height: 60),
              ],
            ),
          ),

          // Оверлей с логами
          if (_showDebugLogs)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.85),
                padding: const EdgeInsets.only(top: 50, bottom: 20, left: 10, right: 10),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "DEBUG LOGS",
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => setState(() => _showDebugLogs = false),
                        )
                      ],
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _logScrollController,
                        itemCount: _debugLogs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              _debugLogs[index],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
