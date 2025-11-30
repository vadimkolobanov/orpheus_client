import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/services/sound_service.dart';
import 'package:orpheus_project/services/webrtc_service.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/services/crypto_service.dart';
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

  // --- ЛОГИРОВАНИЕ В UI ---
  bool _showDebugLogs = false; // Флаг видимости
  final List<String> _debugLogs = []; // Список логов
  final ScrollController _logScrollController = ScrollController();

  late AnimationController _pulseController;
  Timer? _durationTimer;
  final Stopwatch _stopwatch = Stopwatch();
  String _durationText = "00:00";
  String _debugStatus = "Init";

  String _displayName = "Аноним";

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

      if (found != null && found.toString() != 'null') {
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

    if (mounted) setState(() => _callState = CallState.Connected);

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
    if (_isDisposed) return;
    SoundService.instance.stopAllSounds();
    SoundService.instance.playDisconnectedSound();
    
    // Сохраняем состояние до изменения
    final wasConnected = _callState == CallState.Connected;
    
    if (mounted) setState(() => _callState = CallState.Rejected);
    
    // Отправляем системное сообщение о завершении звонка
    if (wasConnected) {
      _sendCallStatusMessage("Входящий звонок", false);
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
      await _sendCallStatusMessage("Исходящий звонок", true);
      await _sendCallStatusMessage("Входящий звонок", false);
    } else if (currentState == CallState.Incoming) {
      // Входящий звонок был отклонен
      await _sendCallStatusMessage("Пропущен звонок", false);
    } else if (currentState == CallState.Dialing) {
      // Исходящий звонок был отменен до ответа - отправляем тому, кому звонили
      await _sendCallStatusMessage("Пропущен звонок", false);
    }
    
    websocketService.sendSignalingMessage(widget.contactPublicKey, signal, {});
    _safePop();
  }

  void _safePop() {
    if (_isDisposed) return;
    _isDisposed = true;
    // Очищаем буфер кандидатов при завершении звонка
    getAndClearIncomingCallBuffer(widget.contactPublicKey);
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // Функция для отправки системного сообщения о звонке в чат
  Future<void> _sendCallStatusMessage(String messageText, bool isSentByMe) async {
    try {
      final callMessage = ChatMessage(
        text: messageText,
        isSentByMe: isSentByMe,
        status: MessageStatus.sent,
        isRead: true,
      );

      // Сохраняем сообщение в локальную БД
      await DatabaseService.instance.addMessage(callMessage, widget.contactPublicKey);

      // Отправляем через WebSocket (зашифрованное)
      try {
        final payload = await cryptoService.encrypt(widget.contactPublicKey, messageText);
        websocketService.sendChatMessage(widget.contactPublicKey, payload);
      } catch (e) {
        print("Ошибка отправки системного сообщения о звонке: $e");
      }

      // Обновляем UI чата
      messageUpdateController.add(widget.contactPublicKey);
    } catch (e) {
      print("Ошибка создания системного сообщения о звонке: $e");
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

  @override
  void dispose() {
    _isDisposed = true;
    _pulseController.dispose();
    _renderer.dispose();
    _stopwatch.stop();
    _durationTimer?.cancel();
    _signalingSubscription?.cancel();
    _webrtcLogSubscription?.cancel();
    SoundService.instance.stopAllSounds();

    // Очищаем буфер кандидатов при завершении звонка
    getAndClearIncomingCallBuffer(widget.contactPublicKey);

    // Сохраняем состояние перед dispose
    final finalState = _callState;
    
    if (finalState == CallState.Connected || finalState == CallState.Dialing) {
      try {
        websocketService.sendSignalingMessage(widget.contactPublicKey, 'hang-up', {});
        
        // Отправляем системные сообщения о завершении звонка при dispose
        if (finalState == CallState.Connected) {
          _sendCallStatusMessage("Исходящий звонок", true);
          _sendCallStatusMessage("Входящий звонок", false);
        } else if (finalState == CallState.Dialing) {
          _sendCallStatusMessage("Пропущен звонок", false);
        }
      } catch (_) {}
    } else if (finalState == CallState.Incoming) {
      // Если входящий звонок был закрыт без ответа
      _sendCallStatusMessage("Пропущен звонок", false);
    }

    _webrtcService.hangUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1A1A), Color(0xFF000000)],
              ),
            ),
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

                // --- АВАТАР ---
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_callState != CallState.Failed && _callState != CallState.Rejected)
                      ScaleTransition(
                        scale: Tween(begin: 1.0, end: 1.5).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut)),
                        child: FadeTransition(
                          opacity: Tween(begin: 0.5, end: 0.0).animate(_pulseController),
                          child: Container(
                            width: 150, height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                            ),
                          ),
                        ),
                      ),
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[800],
                      child: Text(
                        _displayName.isNotEmpty ? _displayName[0].toUpperCase() : "?",
                        style: const TextStyle(fontSize: 40, color: Colors.white),
                      ),
                    ),
                  ],
                ),

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
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.white : Colors.white.withOpacity(0.1),
            ),
            child: Icon(icon, size: 28, color: isActive ? Colors.black : Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))
      ],
    );
  }

  Widget _buildActionBtn(IconData icon, Color color, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 15)],
            ),
            child: Icon(icon, size: 36, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
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
}