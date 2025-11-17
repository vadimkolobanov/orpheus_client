// lib/services/webrtc_service.dart

import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

enum WebRTCConnectionState { New, Connecting, Connected, Disconnected, Failed, Closed }

class WebRTCLog {
  final WebRTCConnectionState state;
  final String? iceCandidateType;
  final DateTime timestamp;

  WebRTCLog({required this.state, this.iceCandidateType, required this.timestamp});

  @override
  String toString() {
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    if (iceCandidateType != null) {
      return '[$time] Тип ICE: $iceCandidateType';
    }
    return '[$time] Состояние: $state';
  }
}

const Map<String, dynamic> rtcConfiguration = {
  'iceServers': [
    // УБИРАЕМ STUN, как вы и просили.
    // Оставляем только ваш TURN-сервер.
    {
      'urls': 'turn:213.171.10.108:3478',
      'username': 'orpheus',
      'credential': 'TEST112',
    },
  ]
};

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get remoteStream => _remoteStream;

  final _logStreamController = BehaviorSubject<List<WebRTCLog>>();
  Stream<List<WebRTCLog>> get logStream => _logStreamController.stream;
  final List<WebRTCLog> _logs = [];

  void _addLog(WebRTCConnectionState state, {String? iceCandidateType}) {
    final log = WebRTCLog(state: state, iceCandidateType: iceCandidateType, timestamp: DateTime.now());
    _logs.add(log);
    // Отправляем копию списка, чтобы виджеты гарантированно перерисовывались
    _logStreamController.add(List.from(_logs));
  }

  Future<void> initialize() async {
    if (await _requestPermissions()) {
      _localStream = await mediaDevices.getUserMedia({'audio': true, 'video': false});
    }
  }

  Future<bool> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.camera.request();
    return await Permission.microphone.isGranted;
  }

  Future<void> initiateCall({
    required Function(Map<String, dynamic> offer) onOfferCreated,
    required Function(Map<String, dynamic> candidate) onCandidateCreated,
  }) async {
    if (_localStream == null) return;
    _peerConnection = await createPeerConnection(rtcConfiguration);
    _registerPeerConnectionListeners(onCandidateCreated);
    _localStream!.getTracks().forEach((track) { _peerConnection!.addTrack(track, _localStream!); });
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    final offerMap = {'sdp': offer.sdp, 'type': offer.type};
    onOfferCreated(offerMap);
  }

  Future<void> answerCall({
    required Map<String, dynamic> offer,
    required Function(Map<String, dynamic> answer) onAnswerCreated,
    required Function(Map<String, dynamic> candidate) onCandidateCreated,
  }) async {
    if (_localStream == null) return;
    _peerConnection = await createPeerConnection(rtcConfiguration);
    _registerPeerConnectionListeners(onCandidateCreated);
    _localStream!.getTracks().forEach((track) { _peerConnection!.addTrack(track, _localStream!); });
    await handleOffer(offer, onAnswerCreated: onAnswerCreated);
  }

  void _registerPeerConnectionListeners(Function(Map<String, dynamic> candidate) onCandidateCreated) {
    _peerConnection?.onIceGatheringState = (RTCIceGatheringState state) { print('ICE gathering state: $state'); };
    _peerConnection?.onConnectionState = (RTCPeerConnectionState state) { print('Connection state: $state'); };
    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      print('ICE connection state: $state');
      WebRTCConnectionState? logState;
      switch(state) {
        case RTCIceConnectionState.RTCIceConnectionStateNew: logState = WebRTCConnectionState.New; break;
        case RTCIceConnectionState.RTCIceConnectionStateChecking: logState = WebRTCConnectionState.Connecting; break;
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted: logState = WebRTCConnectionState.Connected; break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected: logState = WebRTCConnectionState.Disconnected; break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed: logState = WebRTCConnectionState.Failed; break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed: logState = WebRTCConnectionState.Closed; break;
        default: break;
      }
      if (logState != null) _addLog(logState);
    };

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;
      String type = 'unknown';
      if (candidate.candidate!.contains('typ host')) {
        type = 'host (прямой)';
      } else if (candidate.candidate!.contains('typ srflx')) type = 'srflx (STUN)';
      else if (candidate.candidate!.contains('typ relay')) type = 'relay (TURN)';
      _addLog(WebRTCConnectionState.Connecting, iceCandidateType: type);
      final candidateMap = { 'candidate': candidate.candidate, 'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex };
      onCandidateCreated(candidateMap);
    };

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
      }
    };
  }

  Future<void> handleOffer(Map<String, dynamic> offerData, { required Function(Map<String, dynamic> answer) onAnswerCreated, }) async {
    if (_peerConnection == null) return;
    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _peerConnection!.setRemoteDescription(offer);
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    final answerMap = {'sdp': answer.sdp, 'type': answer.type};
    onAnswerCreated(answerMap);
  }

  Future<void> handleAnswer(Map<String, dynamic> answerData) async {
    if (_peerConnection == null) return;
    final answer = RTCSessionDescription(answerData['sdp'], answerData['type']);
    await _peerConnection!.setRemoteDescription(answer);
  }

  Future<void> addCandidate(Map<String, dynamic> candidateData) async {
    if (_peerConnection == null) return;
    if (candidateData['candidate'] == null) return;
    final candidate = RTCIceCandidate(candidateData['candidate'], candidateData['sdpMid'], candidateData['sdpMLineIndex']);
    await _peerConnection!.addCandidate(candidate);
  }

  Future<void> hangUp() async {
    try {
      await _localStream?.dispose();
      await _remoteStream?.dispose();
      await _peerConnection?.close();
      _peerConnection = null;
      _logs.clear();
      _logStreamController.add([]);
    } catch (e) { print("Ошибка при hangUp: $e"); }
  }
}