// lib/call_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/services/sound_service.dart';
import 'package:orpheus_project/services/webrtc_service.dart';

enum CallState { Dialing, Incoming, Connecting, Connected, Rejected, Failed }

class CallScreen extends StatefulWidget {
  final String contactPublicKey;
  final Map<String, dynamic>? offer;
  const CallScreen({super.key, required this.contactPublicKey, this.offer});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  final _webrtcService = WebRTCService();
  final _renderer = RTCVideoRenderer();
  late StreamSubscription _signalingSubscription;
  late StreamSubscription _webrtcLogSubscription;
  late CallState _callState;
  bool _isHangingUp = false;
  bool _isSpeakerOn = false;
  final _soundService = SoundService.instance;
  late AnimationController _pulseAnimationController;
  final List<WebRTCLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _callState = widget.offer != null ? CallState.Incoming : CallState.Dialing;
    _pulseAnimationController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _initRenderersAndSignaling();
    if (_callState == CallState.Dialing) {
      _initiateCall();
      _tryPlaySound(_soundService.playDialingSound);
    }
  }

  void _tryPlaySound(Future<void> Function() playFunction) { try { playFunction(); } catch (e) { print("Ошибка воспроизведения звука: $e"); } }

  Future<void> _initRenderersAndSignaling() async {
    await _renderer.initialize();
    _webrtcLogSubscription = _webrtcService.logStream.listen((logs) {
      if (!mounted) return;

      final lastLog = logs.isNotEmpty ? logs.last : null;
      if (lastLog == null) return;

      setState(() {
        _logs.clear();
        _logs.addAll(logs);
      });

      if (lastLog.state == WebRTCConnectionState.Connected) {
        if (_callState != CallState.Connected) {
          _soundService.stopAllSounds();
          _tryPlaySound(_soundService.playConnectedSound);
          setState(() { _callState = CallState.Connected; });
        }
      } else if (lastLog.state == WebRTCConnectionState.Failed) {
        if (mounted && _callState != CallState.Failed) {
          setState(() => _callState = CallState.Failed);
          // --- ИСПРАВЛЕНИЕ ЗДЕСЬ: Отправляем сигнал о сбое ---
          // Мы сообщаем собеседнику, что у нас произошла ошибка.
          Future.delayed(const Duration(seconds: 3), () => _cleanupAndClose(isInitiator: true, signalType: 'hang-up'));
        }
      }
    });

    _signalingSubscription = signalingStreamController.stream.listen((signal) {
      if (!mounted || signal['sender_pubkey'] != widget.contactPublicKey) return;
      final type = signal['type'] as String;

      if (type == 'call-rejected') {
        _soundService.stopAllSounds();
        if (mounted) setState(() => _callState = CallState.Rejected);
        Future.delayed(const Duration(seconds: 2), () => _cleanupAndClose(isInitiator: false));
      } else if (type == 'call-answer') {
        final data = signal['data'] as Map<String, dynamic>;
        _webrtcService.handleAnswer(data);
        if (mounted) setState(() => _callState = CallState.Connecting); // Переходим в Connecting после ответа
      } else if (type == 'ice-candidate') {
        final data = signal['data'] as Map<String, dynamic>;
        _webrtcService.addCandidate(data);
      } else if (type == 'hang-up') {
        _cleanupAndClose(isInitiator: false);
      }
    });

    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_renderer.srcObject != _webrtcService.remoteStream) {
        if (mounted) setState(() { _renderer.srcObject = _webrtcService.remoteStream; });
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
    if (mounted) setState(() => _callState = CallState.Connecting);
    await _webrtcService.initialize();
    await _webrtcService.answerCall(
      offer: widget.offer!,
      onAnswerCreated: (answer) {
        websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-answer', answer);
        _setSpeakerphone(false);
      },
      onCandidateCreated: (candidate) => websocketService.sendSignalingMessage(widget.contactPublicKey, 'ice-candidate', candidate),
    );
  }

  void _rejectCall() { _cleanupAndClose(isInitiator: true, signalType: 'call-rejected'); }
  void _hangUp() { _cleanupAndClose(isInitiator: true, signalType: 'hang-up'); }

  void _cleanupAndClose({bool isInitiator = true, String? signalType}) {
    if (_isHangingUp) return;
    _isHangingUp = true;
    if (isInitiator && signalType != null) {
      websocketService.sendSignalingMessage(widget.contactPublicKey, signalType, {});
    }
    _signalingSubscription.cancel();
    _webrtcLogSubscription.cancel();
    _soundService.stopAllSounds();
    _tryPlaySound(_soundService.playDisconnectedSound);
    _webrtcService.hangUp();
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _setSpeakerphone(bool enabled) async { await Helper.setSpeakerphoneOn(enabled); if (mounted) setState(() { _isSpeakerOn = enabled; }); }

  @override
  void dispose() {
    _pulseAnimationController.dispose();
    _signalingSubscription.cancel();
    _webrtcLogSubscription.cancel();
    _renderer.dispose();
    _soundService.stopAllSounds();
    if (!_isHangingUp) {
      _cleanupAndClose(isInitiator: true, signalType: 'hang-up');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.95),
      body: SafeArea(child: Center(child: Column(
        children: [
          SizedBox(height: 1.0, width: 1.0, child: Opacity(opacity: 0.0, child: RTCVideoView(_renderer))),
          const Spacer(flex: 1),
          FadeTransition(
            opacity: _pulseAnimationController.drive(CurveTween(curve: Curves.easeInOut)),
            child: Container(
              width: 100, height: 100,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _getStatusIndicatorColor().withOpacity(0.3), border: Border.all(color: _getStatusIndicatorColor(), width: 2)),
              child: Icon(_getStatusIndicatorIcon(), color: Colors.white, size: 40),
            ),
          ),
          const SizedBox(height: 24),
          Text(_getCallStatusText(), style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
          const SizedBox(height: 12),
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: StreamBuilder<List<WebRTCLog>>(
                stream: _webrtcService.logStream,
                builder: (context, snapshot) {
                  final logs = snapshot.data ?? [];
                  return ListView.builder(
                    reverse: true,
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs.reversed.toList()[index];
                      return Text(log.toString(), textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontFamily: 'monospace'));
                    },
                  );
                },
              ),
            ),
          ),
          const Spacer(flex: 1),
          _buildCallActions(),
          const SizedBox(height: 60),
        ],
      ))),
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

  Color _getStatusIndicatorColor() { switch (_callState) { case CallState.Dialing: case CallState.Connecting: return Colors.blue.shade300; case CallState.Incoming: return Colors.green.shade300; case CallState.Connected: return Colors.lightGreenAccent.shade400; case CallState.Rejected: case CallState.Failed: return Colors.red.shade300; } }
  IconData _getStatusIndicatorIcon() { switch (_callState) { case CallState.Dialing: case CallState.Connecting: return Icons.phone_forwarded_outlined; case CallState.Incoming: return Icons.ring_volume_outlined; case CallState.Connected: return Icons.mic_none_outlined; case CallState.Rejected: case CallState.Failed: return Icons.phone_disabled_outlined; } }

  Widget _buildCallActions() {
    if (_callState == CallState.Rejected || _callState == CallState.Failed) { return const SizedBox(height: 76); }
    if (_callState == CallState.Connected) {
      return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _buildActionButton(icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down, backgroundColor: Colors.white.withOpacity(0.2), onPressed: () => _setSpeakerphone(!_isSpeakerOn)),
        _buildActionButton(icon: Icons.call_end, backgroundColor: Colors.redAccent, onPressed: _hangUp),
        _buildActionButton(icon: Icons.mic_off_outlined, backgroundColor: Colors.white.withOpacity(0.2), onPressed: () {}),
      ]);
    } else if (_callState == CallState.Incoming) {
      return Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _buildActionButton(icon: Icons.call_end, backgroundColor: Colors.redAccent, onPressed: _rejectCall),
        _buildActionButton(icon: Icons.call, backgroundColor: Colors.green, onPressed: _acceptCall),
      ]);
    } else { // Dialing or Connecting
      // --- ИСПРАВЛЕНИЕ ЗДЕСЬ: Показываем кнопку "Положить трубку" всегда ---
      return _buildActionButton(icon: Icons.call_end, backgroundColor: Colors.redAccent, onPressed: _hangUp);
    }
  }

  Widget _buildActionButton({required IconData icon, required Color backgroundColor, required VoidCallback onPressed}) {
    return IconButton.filled(style: IconButton.styleFrom(backgroundColor: backgroundColor, shape: const CircleBorder(), padding: const EdgeInsets.all(20)),
      icon: Icon(icon, color: Colors.white, size: 36),
      onPressed: onPressed,
    );
  }
}