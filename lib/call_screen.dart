// lib/call_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/services/webrtc_service.dart';

enum CallState { Dialing, Incoming, Connected }

class CallScreen extends StatefulWidget {
  final String contactPublicKey;
  final Map<String, dynamic>? offer;

  const CallScreen({super.key, required this.contactPublicKey, this.offer});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _webrtcService = WebRTCService();
  final _renderer = RTCVideoRenderer();
  late StreamSubscription _signalingSubscription;
  late CallState _callState;
  bool _isHangingUp = false;

  // --- НОВОЕ СОСТОЯНИЕ: Для управления громкой связью ---
  bool _isSpeakerOn = false;

  @override
  void initState() {
    super.initState();
    _callState = widget.offer != null ? CallState.Incoming : CallState.Dialing;
    _initRenderersAndSignaling();

    if (_callState == CallState.Dialing) {
      _initiateCall();
    }
  }

  Future<void> _initRenderersAndSignaling() async {
    await _renderer.initialize();

    _signalingSubscription = signalingStreamController.stream.listen((signal) {
      if (!mounted || signal['sender_pubkey'] != widget.contactPublicKey) return;
      final type = signal['type'] as String;
      final data = signal['data'] as Map<String, dynamic>;

      if (type == 'call-answer') {
        _webrtcService.handleAnswer(data);
        setState(() => _callState = CallState.Connected);
        // --- НОВОЕ: Устанавливаем ушной динамик по умолчанию при соединении ---
        _setSpeakerphone(false);
      } else if (type == 'ice-candidate') {
        _webrtcService.addCandidate(data);
      } else if (type == 'hang-up' || type == 'call-rejected') {
        _cleanupAndClose();
      }
    });

    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_renderer.srcObject != _webrtcService.remoteStream) {
        setState(() { _renderer.srcObject = _webrtcService.remoteStream; });
      }
    });
  }

  Future<void> _initiateCall() async {
    await _webrtcService.initialize();
    await _webrtcService.initiateCall(
      onOfferCreated: (offer) => websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-offer', offer),
      onCandidateCreated: (candidate) => websocketService.sendSignalingMessage(widget.contactPublicKey, 'ice-candidate', candidate),
    );
  }

  void _acceptCall() async {
    setState(() => _callState = CallState.Connected);
    await _webrtcService.initialize();
    await _webrtcService.answerCall(
      offer: widget.offer!,
      onAnswerCreated: (answer) {
        websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-answer', answer);
        // --- НОВОЕ: Устанавливаем ушной динамик по умолчанию при принятии звонка ---
        _setSpeakerphone(false);
      },
      onCandidateCreated: (candidate) => websocketService.sendSignalingMessage(widget.contactPublicKey, 'ice-candidate', candidate),
    );
  }

  void _rejectCall() {
    websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-rejected', {});
    _cleanupAndClose();
  }

  void _hangUp() {
    websocketService.sendSignalingMessage(widget.contactPublicKey, 'hang-up', {});
    _cleanupAndClose();
  }

  Future<void> _cleanupAndClose() async {
    if (_isHangingUp) return;
    _isHangingUp = true;

    await _webrtcService.hangUp();

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  // --- НОВЫЙ МЕТОД: Для переключения динамиков ---
  Future<void> _setSpeakerphone(bool enabled) async {
    // Helper.setSpeakerphoneOn() - это метод из flutter_webrtc
    // Он переключает аудиовыход.
    await Helper.setSpeakerphoneOn(enabled);
    setState(() {
      _isSpeakerOn = enabled;
    });
  }

  @override
  void dispose() {
    _signalingSubscription.cancel();
    _renderer.dispose();
    if (!_isHangingUp) {
      _webrtcService.hangUp();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.95),
      body: SafeArea(
        child: Center(
          child: Column(
            children: [
              SizedBox(height: 1.0, width: 1.0, child: Opacity(opacity: 0.0, child: RTCVideoView(_renderer))),
              const Spacer(flex: 2),
              Text(
                _getCallStatusText(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                widget.contactPublicKey.substring(0, 16),
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
              ),
              const Spacer(flex: 3),
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
      case CallState.Connected: return 'Звонок активен';
    }
  }

  Widget _buildCallActions() {
    if (_callState == CallState.Connected) {
      // --- НОВОЕ: Отображаем панель управления активным звонком ---
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Кнопка переключения на громкую связь
          _buildActionButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            backgroundColor: Colors.white.withOpacity(0.2),
            onPressed: () => _setSpeakerphone(!_isSpeakerOn),
          ),
          // Кнопка завершения звонка
          _buildActionButton(
            icon: Icons.call_end,
            backgroundColor: Colors.redAccent,
            onPressed: _hangUp,
          ),
          // Пустая кнопка-заглушка для симметрии (в будущем можно добавить "выключить микрофон")
          _buildActionButton(
            icon: Icons.mic_off_outlined,
            backgroundColor: Colors.white.withOpacity(0.2),
            onPressed: () { /* TODO: Mute microphone */ },
          ),
        ],
      );
    }
    else if (_callState == CallState.Incoming) {
      // Кнопки "Принять" и "Отклонить"
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
    } else { // Dialing
      // Одна кнопка "Положить трубку"
      return _buildActionButton(
        icon: Icons.call_end,
        backgroundColor: Colors.redAccent,
        onPressed: _hangUp,
      );
    }
  }

  Widget _buildActionButton({required IconData icon, required Color backgroundColor, required VoidCallback onPressed}) {
    return IconButton.filled(
      style: IconButton.styleFrom(
        backgroundColor: backgroundColor,
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(20), // Немного уменьшим паддинг
      ),
      icon: Icon(icon, color: Colors.white, size: 36), // Уменьшим иконку
      onPressed: onPressed,
    );
  }
}