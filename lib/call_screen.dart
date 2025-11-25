// lib/call_screen.dart

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orpheus_project/main.dart';
import 'package:orpheus_project/services/sound_service.dart';
import 'package:orpheus_project/services/webrtc_service.dart';

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

  late AnimationController _pulseController;
  Timer? _durationTimer;
  final Stopwatch _stopwatch = Stopwatch();
  String _durationText = "00:00";
  String _debugStatus = "Init";

  @override
  void initState() {
    super.initState();
    _callState = widget.offer != null ? CallState.Incoming : CallState.Dialing;

    _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2)
    )..repeat(reverse: false);

    _initCallSequence();
  }

  Future<void> _initCallSequence() async {
    await _renderer.initialize();

    _webrtcLogSubscription = _webrtcService.logStream.listen((logs) {
      if (_isDisposed || logs.isEmpty) return;
      final state = logs.last.state;

      if (mounted) {
        setState(() => _debugStatus = state.toString().split('.').last);
      }

      if (state == WebRTCConnectionState.Connected) {
        if (_callState != CallState.Connected) _onConnected();
      } else if (state == WebRTCConnectionState.Failed) {
        if (!_isDisposed) _onError("Сбой (ICE)");
      } else if (state == WebRTCConnectionState.Closed) {
        if (!_isDisposed && _callState == CallState.Connected) _onError("Завершен");
      }
    });

    _signalingSubscription = signalingStreamController.stream.listen((signal) async {
      if (_isDisposed || signal['sender_pubkey'] != widget.contactPublicKey) return;

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
    if (mounted) setState(() => _callState = CallState.Rejected);
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
        onOfferCreated: (offer) => websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-offer', offer),
        onCandidateCreated: (cand) => websocketService.sendSignalingMessage(widget.contactPublicKey, 'ice-candidate', cand),
      );
    } catch (e) {
      _onError("Mic Error");
    }
  }

  void _acceptCall() async {
    SoundService.instance.stopAllSounds();
    if (mounted) setState(() => _callState = CallState.Connecting);
    try {
      await _webrtcService.answerCall(
        offer: widget.offer!,
        onAnswerCreated: (ans) => websocketService.sendSignalingMessage(widget.contactPublicKey, 'call-answer', ans),
        onCandidateCreated: (cand) => websocketService.sendSignalingMessage(widget.contactPublicKey, 'ice-candidate', cand),
      );
    } catch (e) {
      _onError("Connect Error");
    }
  }

  void _endCallButton() {
    if (_isDisposed) return;
    String signal = _callState == CallState.Incoming ? 'call-rejected' : 'hang-up';
    websocketService.sendSignalingMessage(widget.contactPublicKey, signal, {});
    _safePop();
  }

  void _safePop() {
    if (_isDisposed) return;
    _isDisposed = true;
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  void _toggleMic() {
    // Безопасное переключение микрофона
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

    if (_callState == CallState.Connected || _callState == CallState.Dialing) {
      try {
        websocketService.sendSignalingMessage(widget.contactPublicKey, 'hang-up', {});
      } catch (_) {}
    }

    _webrtcService.hangUp();
    super.dispose();
  }

  // --- UI ---

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
                Text("Orpheus Secure", style: TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 10),
                Text(
                  _callState == CallState.Connected ? "Собеседник" : widget.contactPublicKey.substring(0, 8),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
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
                    const CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey,
                      child: Icon(Icons.person, size: 60, color: Colors.white),
                    ),
                  ],
                ),

                const Spacer(),

                _buildControlPanel(),

                const SizedBox(height: 60),
              ],
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