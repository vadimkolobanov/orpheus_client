import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/services/sound_service.dart';
import 'package:orpheus_project/services/webrtc_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/models/chat_message_model.dart';

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
  final _webrtcService = WebRTCService();
  final _renderer = RTCVideoRenderer();

  StreamSubscription? _signalingSubscription;
  StreamSubscription? _webrtcLogSubscription;

  CallState _callState = CallState.Dialing;

  bool _isSpeakerOn = false;
  bool _isMicMuted = false;
  bool _isDisposed = false;
  bool _messagesSent = false; // Флаг для отслеживания отправки системных сообщений

  // --- ЛОГИРОВАНИЕ В UI ---
  bool _showDebugLogs = false; // Флаг видимости
  final List<String> _debugLogs = []; // Список логов
  final ScrollController _logScrollController = ScrollController();

  late AnimationController _pulseController;
  late AnimationController _particlesController;
  late AnimationController _waveController;
  Timer? _durationTimer;
  final Stopwatch _stopwatch = Stopwatch();
  String _durationText = "00:00";
  String _debugStatus = "Init";

  String _displayName = "Аноним";
  
  // Для визуализации аудио волн
  final List<double> _audioWaveData = List.generate(20, (_) => 0.0);

  @override
  void initState() {
    super.initState();

    _displayName = widget.contactPublicKey.substring(0, 8);
    _resolveContactName();

    _callState = widget.offer != null ? CallState.Incoming : CallState.Dialing;

    _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2)
    )..repeat(reverse: false);

    _particlesController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 8)
    )..repeat();

    _waveController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500)
    );

    _initCallSequence();
  }

  // Метод добавления лога на экран
  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _debugLogs.add("${DateTime.now().toString().substring(11, 19)} $message");
    });
    // Автоскролл вниз
    if (_showDebugLogs) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_logScrollController.hasClients) {
          _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _resolveContactName() async {
    try {
      final contacts = await DatabaseService.instance.getContacts();
      final found = contacts.firstWhere(
            (c) => c.publicKey == widget.contactPublicKey,
        orElse: () => null as dynamic,
      );

      if (found.toString() != 'null') {
        if (mounted) {
          setState(() {
            _displayName = found.name;
          });
        }
      }
    } catch (e) {
      print("Ошибка поиска имени: $e");
    }
  }

  Future<void> _initCallSequence() async {
    await _renderer.initialize();

    // Подписка на логи WebRTC (из сервиса)
    _webrtcLogSubscription = _webrtcService.onDebugLog.listen((log) {
      _addLog(log); // Выводим на экран

      // Обновляем статус для юзера
      if (log.contains("Connected")) {
        if (_callState != CallState.Connected) _onConnected();
      } else if (log.contains("Failed")) {
        if (!_isDisposed) _onError("Сбой (ICE)");
      }
      
      // Привязываем удалённый поток к renderer когда он становится доступным
      if (log.contains("REMOTE TRACK RECEIVED") || log.contains("Remote stream assigned")) {
        _attachRemoteStream();
      }
    });

    // Подписка на Сигналинг (WebSocket)
    _signalingSubscription = signalingStreamController.stream.listen((signal) async {
      // Логируем входящий сигнал
      _addLog("📥 IN: ${signal['type']} from ${signal['sender_pubkey'].toString().substring(0, 6)}...");

      if (_isDisposed || signal['sender_pubkey'] != widget.contactPublicKey) {
        _addLog("❌ DROPPED: Wrong sender");
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
        _onRemoteHangup();
      }
    });

    // Применяем накопленные кандидаты из буфера (для входящих звонков)
    if (_callState == CallState.Incoming) {
      final bufferedCandidates = getAndClearIncomingCallBuffer(widget.contactPublicKey);
      if (bufferedCandidates.isNotEmpty) {
        _addLog("📦 Применение ${bufferedCandidates.length} накопленных ICE кандидатов");
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

  void _onConnected() {
    SoundService.instance.stopAllSounds();
    SoundService.instance.playConnectedSound();

    if (mounted) {
      setState(() => _callState = CallState.Connected);
      _waveController.repeat(); // Запускаем волны при соединении
      
      // Привязываем удалённый поток при соединении
      _attachRemoteStream();
    }

    // Симуляция аудио волн во время звонка
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
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
    
    // Периодическая проверка и привязка удалённого потока
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _isDisposed || _callState != CallState.Connected) {
        timer.cancel();
        return;
      }
      // Проверяем, привязан ли удалённый поток
      if (_webrtcService.remoteStream != null && _renderer.srcObject != _webrtcService.remoteStream) {
        _attachRemoteStream();
      }
    });

    _stopwatch.start();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final elapsed = _stopwatch.elapsed;
      final min = elapsed.inMinutes.toString().padLeft(2, '0');
      final sec = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      setState(() => _durationText = "$min:$sec");
    });
  }

  void _onRemoteHangup() {
    if (_isDisposed || _messagesSent) return;
    SoundService.instance.stopAllSounds();
    SoundService.instance.playDisconnectedSound();
    
    // Сохраняем состояние до изменения
    final wasConnected = _callState == CallState.Connected;
    
    if (mounted) setState(() => _callState = CallState.Rejected);
    
    // Отправляем системное сообщение о завершении звонка
    if (wasConnected) {
      // Для меня: входящий звонок
      _saveCallStatusMessageLocally("Входящий звонок", false);
      // Для контакта: исходящий звонок
      _sendCallStatusMessageToContact("Исходящий звонок");
      _messagesSent = true;
    }
    
    Future.delayed(const Duration(seconds: 1), _safePop);
  }

  void _onError(String msg) {
    if (_isDisposed) return;
    if (mounted) setState(() => _callState = CallState.Failed);
    Future.delayed(const Duration(seconds: 2), _safePop);
  }

  Future<void> _startOutgoingCall() async {
    try {
      await _webrtcService.initiateCall(
        onOfferCreated: (offer) {
          _addLog("📤 OUT: call-offer");
          websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-offer', offer);
        },
        onCandidateCreated: (cand) {
          _addLog("📤 OUT: ice-candidate");
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
          _addLog("📤 OUT: call-answer");
          websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-answer', ans);
        },
        onCandidateCreated: (cand) {
          _addLog("📤 OUT: ice-candidate");
          websocketService.sendSignalingMessage(widget.contactPublicKey, 'ice-candidate', cand);
        },
      );
    } catch (e) {
      _onError("Connect Error");
    }
  }

  void _endCallButton() async {
    if (_isDisposed) return;
    
    // Сохраняем текущее состояние
    final currentState = _callState;
    String signal = currentState == CallState.Incoming ? 'call-rejected' : 'hang-up';
    
    // Отправляем системные сообщения о звонке
    if (currentState == CallState.Connected) {
      // Звонок был завершен после соединения
      // Для меня: исходящий звонок
      await _saveCallStatusMessageLocally("Исходящий звонок", true);
      // Для контакта: входящий звонок
      await _sendCallStatusMessageToContact("Входящий звонок");
    } else if (currentState == CallState.Incoming) {
      // Входящий звонок был отклонен
      // Для меня: пропущен звонок
      await _saveCallStatusMessageLocally("Пропущен звонок", false);
      // Контакту не нужно отправлять, так как он уже знает, что звонок был отклонен
    } else if (currentState == CallState.Dialing) {
      // Исходящий звонок был отменен до ответа
      // Для меня: исходящий звонок (локально)
      await _saveCallStatusMessageLocally("Исходящий звонок", true);
      // Для контакта: пропущен звонок
      await _sendCallStatusMessageToContact("Пропущен звонок");
    }
    
    // Помечаем, что сообщения уже отправлены, чтобы не дублировать в dispose
    _messagesSent = true;
    
    websocketService.sendSignalingMessage(widget.contactPublicKey, signal, {});
    _safePop();
  }

  void _safePop() {
    if (_isDisposed) return;
    // Очищаем буфер кандидатов при завершении звонка
    getAndClearIncomingCallBuffer(widget.contactPublicKey);
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // Функция для отправки системного сообщения о звонке в чат (только локально)
  Future<void> _saveCallStatusMessageLocally(String messageText, bool isSentByMe) async {
    try {
      final callMessage = ChatMessage(
        text: messageText,
        isSentByMe: isSentByMe,
        status: MessageStatus.sent,
        isRead: true,
      );

      // Сохраняем сообщение в локальную БД
      await DatabaseService.instance.addMessage(callMessage, widget.contactPublicKey);

      // Обновляем UI чата
      messageUpdateController.add(widget.contactPublicKey);
    } catch (e) {
      print("Ошибка сохранения системного сообщения о звонке: $e");
    }
  }

  // Функция для отправки системного сообщения о звонке контакту (через WebSocket)
  Future<void> _sendCallStatusMessageToContact(String messageText) async {
    try {
      final payload = await cryptoService.encrypt(widget.contactPublicKey, messageText);
      websocketService.sendChatMessage(widget.contactPublicKey, payload);
    } catch (e) {
      print("Ошибка отправки системного сообщения о звонке контакту: $e");
    }
  }

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

  // Привязка удалённого аудио потока к renderer для воспроизведения
  void _attachRemoteStream() {
    final remoteStream = _webrtcService.remoteStream;
    if (remoteStream != null && mounted) {
      try {
        // Проверяем, не привязан ли уже другой поток
        if (_renderer.srcObject != remoteStream) {
          _renderer.srcObject = remoteStream;
          _addLog("✅ Удалённый аудио поток привязан к renderer");
        }
        
        // Убеждаемся, что локальный поток НЕ воспроизводится (только отправляется)
        final localStream = _webrtcService.localStream;
        if (localStream != null) {
          // Локальный поток должен только отправляться через PeerConnection, не воспроизводиться
          // Это предотвращает эхо от собственного голоса
          // В WebRTC локальный поток автоматически не воспроизводится при добавлении через addTrack
        }
      } catch (e) {
        _addLog("❌ Ошибка привязки удалённого потока: $e");
      }
    } else if (remoteStream == null && _callState == CallState.Connected) {
      // Если поток еще не получен, но соединение установлено, попробуем позже
      _addLog("⏳ Ожидание удалённого потока...");
    }
  }

  @override
  void dispose() {
    // Очищаем буфер кандидатов при завершении звонка
    getAndClearIncomingCallBuffer(widget.contactPublicKey);
    
    // Отправляем системные сообщения только если они еще не были отправлены в _endCallButton
    if (!_messagesSent && !_isDisposed) {
      final finalState = _callState;
      
      if (finalState == CallState.Connected || finalState == CallState.Dialing) {
        try {
          websocketService.sendSignalingMessage(widget.contactPublicKey, 'hang-up', {});
          
          // Отправляем системные сообщения о завершении звонка при dispose
          if (finalState == CallState.Connected) {
            // Для меня: исходящий звонок
            _saveCallStatusMessageLocally("Исходящий звонок", true);
            // Для контакта: входящий звонок
            _sendCallStatusMessageToContact("Входящий звонок");
          } else if (finalState == CallState.Dialing) {
            // Исходящий звонок был отменен до ответа
            // Для меня: исходящий звонок (локально)
            _saveCallStatusMessageLocally("Исходящий звонок", true);
            // Для контакта: пропущен звонок
            _sendCallStatusMessageToContact("Пропущен звонок");
          }
        } catch (_) {}
      } else if (finalState == CallState.Incoming) {
        // Если входящий звонок был закрыт без ответа
        // Для меня: пропущен звонок
        _saveCallStatusMessageLocally("Пропущен звонок", false);
      }
    }
    
    _isDisposed = true;
    _pulseController.dispose();
    _particlesController.dispose();
    _waveController.dispose();
    
    // Очищаем renderer перед dispose
    try {
      _renderer.srcObject = null;
    } catch (e) {
      print("Ошибка очистки renderer: $e");
    }
    _renderer.dispose();
    
    _stopwatch.stop();
    _durationTimer?.cancel();
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
          // Анимированный градиентный фон
          AnimatedBuilder(
            animation: _particlesController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(
                        const Color(0xFF1A1A1A),
                        const Color(0xFF0A1A2A),
                        (0.5 + 0.5 * (0.5 + 0.5 * _particlesController.value)).clamp(0.0, 1.0),
                      )!,
                      const Color(0xFF000000),
                    ],
                  ),
                ),
              );
            },
          ),

          // Анимированные частицы (эффект "звездного неба")
          CustomPaint(
            painter: ParticlesPainter(_particlesController.value),
            child: Container(),
          ),

          // Концентрические волны вокруг аватара (только при соединении)
          if (_callState == CallState.Connected)
            AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return CustomPaint(
                  painter: WavePainter(_waveController.value),
                  child: Container(),
                );
              },
            ),

          SizedBox(height: 0, width: 0, child: RTCVideoView(_renderer)),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),

                // --- СКРЫТАЯ КНОПКА ЛОГОВ ---
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showDebugLogs = !_showDebugLogs;
                    });
                  },
                  child: const Text("Secure Call", style: TextStyle(color: Colors.white54, fontSize: 14, decoration: TextDecoration.underline)),
                ),

                const SizedBox(height: 10),

                Text(
                  _displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                if (_callState == CallState.Connected)
                  Text(_durationText, style: const TextStyle(color: Color(0xFF6AD394), fontSize: 24, fontFamily: "monospace"))
                else
                  Column(
                    children: [
                      Text(_getStatusText(), style: const TextStyle(color: Colors.grey, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(_debugStatus, style: const TextStyle(color: Colors.red, fontSize: 10)),
                    ],
                  ),

                const Spacer(),

                // --- АВАТАР С УЛУЧШЕННОЙ АНИМАЦИЕЙ ---
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Множественные пульсирующие кольца
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
                    // Главный аватар с эффектом свечения
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

                // Визуализация аудио волн (только при соединении)
                if (_callState == CallState.Connected) ...[
                  const SizedBox(height: 30),
                  _buildAudioVisualizer(),
                ],

                const Spacer(),

                _buildControlPanel(),

                const SizedBox(height: 60),
              ],
            ),
          ),

          // --- ОВЕРЛЕЙ С ЛОГАМИ ---
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
                        const Text("DEBUG LOGS", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
                          final log = _debugLogs[index];
                          Color color = Colors.white;
                          if (log.contains("OUT:")) color = Colors.blueAccent;
                          if (log.contains("IN:")) color = Colors.greenAccent;
                          if (log.contains("RELAY")) color = Colors.orangeAccent;
                          if (log.contains("ERROR") || log.contains("Failed") || log.contains("DROPPED")) color = Colors.redAccent;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(log, style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace')),
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

  Widget _buildControlPanel() {
    if (_callState == CallState.Incoming) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildActionBtn(Icons.call_end, Colors.red, "ОТКЛОНИТЬ", _endCallButton),
            _buildActionBtn(Icons.call, Colors.green, "ОТВЕТИТЬ", _acceptCall),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlBtn(
              icon: _isMicMuted ? Icons.mic_off : Icons.mic,
              isActive: _isMicMuted,
              label: "Микрофон",
              onTap: _toggleMic,
            ),
            _buildControlBtn(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
              isActive: _isSpeakerOn,
              label: "Динамик",
              onTap: _toggleSpeaker,
            ),
          ],
        ),
        const SizedBox(height: 40),
        _buildActionBtn(Icons.call_end, Colors.redAccent, "ЗАВЕРШИТЬ", _endCallButton),
      ],
    );
  }

  Widget _buildControlBtn({required IconData icon, required bool isActive, required String label, required VoidCallback onTap}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive 
                  ? Colors.white 
                  : Colors.white.withOpacity(0.1),
              border: Border.all(
                color: isActive 
                    ? const Color(0xFF6AD394).withOpacity(0.5)
                    : Colors.white.withOpacity(0.2),
                width: 2,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFF6AD394).withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
            ),
            child: Icon(
              icon,
              size: 28,
              color: isActive ? Colors.black : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isActive ? const Color(0xFF6AD394) : Colors.grey,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildActionBtn(IconData icon, Color color, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: 1.0),
            duration: const Duration(milliseconds: 200),
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.5),
                        blurRadius: 25,
                        spreadRadius: 3,
                      ),
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 36, color: Colors.white),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: color.withOpacity(0.5),
                blurRadius: 10,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getStatusText() {
    switch (_callState) {
      case CallState.Dialing: return "Вызов...";
      case CallState.Incoming: return "Входящий звонок";
      case CallState.Connecting: return "Соединение...";
      case CallState.Rejected: return "Завершен";
      case CallState.Failed: return "Сбой";
      default: return "";
    }
  }

  // Визуализатор аудио волн
  Widget _buildAudioVisualizer() {
    return Container(
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
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6AD394).withOpacity(0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
            height: height.clamp(5.0, 50.0),
          );
        }),
      ),
    );
  }
}

// Кастомный painter для анимированных частиц
class ParticlesPainter extends CustomPainter {
  final double animationValue;

  ParticlesPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6AD394).withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Создаем частицы в случайных позициях (детерминированные для производительности)
    for (int i = 0; i < 30; i++) {
      final x = (i * 137.5) % size.width;
      final y = (i * 197.3 + animationValue * 200) % size.height;
      final radius = 1.5 + (i % 3) * 0.5;
      
      canvas.drawCircle(
        Offset(x, y),
        radius,
        paint..color = const Color(0xFF6AD394).withOpacity(0.2 + (i % 3) * 0.1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Кастомный painter для волн
class WavePainter extends CustomPainter {
  final double animationValue;

  WavePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2 - 100; // Примерная позиция аватара

    final paint = Paint()
      ..color = const Color(0xFF6AD394)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Рисуем концентрические волны
    for (int i = 0; i < 3; i++) {
      final radius = 80 + (animationValue * 100) + (i * 30);
      final opacity = (1.0 - animationValue - i * 0.2).clamp(0.0, 0.5);
      
      canvas.drawCircle(
        Offset(centerX, centerY),
        radius,
        paint..color = const Color(0xFF6AD394).withOpacity(opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}