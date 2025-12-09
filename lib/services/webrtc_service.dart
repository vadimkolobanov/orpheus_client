import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

const Map<String, dynamic> rtcConfiguration = {
  'iceServers': [
    {
      'urls': [
        'turn:213.171.10.108:3478',
        'turn:213.171.10.108:3478?transport=tcp',
        'turn:213.171.10.108:443?transport=tcp',
      ],
      'username': 'orpheus',
      'credential': 'TEST112',
    },
  ],
  'sdpSemantics': 'unified-plan',
  'iceTransportPolicy': 'all',
  'bundlePolicy': 'max-bundle',
};

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;

  final _debugLogController = StreamController<String>.broadcast();
  Stream<String> get onDebugLog => _debugLogController.stream;

  // Внутренняя очередь кандидатов (для решения Race Condition)
  final List<RTCIceCandidate> _queuedRemoteCandidates = [];
  bool _remoteDescriptionSet = false;

  void _log(String msg) {
    print(msg);
    _debugLogController.add(msg);
  }

  Future<void> initialize() async {
    _log("--- [WebRTC] Requesting Permissions... ---");
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.bluetoothConnect,
    ].request();

    if (statuses[Permission.microphone]!.isGranted) {
      _localStream = await mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googEchoCancellation': true,
          'googNoiseSuppression': true,
          'googHighpassFilter': true,
        },
        'video': false
      });
    } else {
      _log("--- [WebRTC] ERROR: Mic Permission Denied ---");
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(Function(Map<String, dynamic> candidate) onCandidateCreated) async {
    _log("--- [WebRTC] Creating PeerConnection... ---");
    final pc = await createPeerConnection(rtcConfiguration);

    _registerPeerConnectionListeners(pc, onCandidateCreated);

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }
    return pc;
  }

  Future<void> initiateCall({
    required Function(Map<String, dynamic> offer) onOfferCreated,
    required Function(Map<String, dynamic> candidate) onCandidateCreated,
  }) async {
    _log("--- [WebRTC] INITIATING CALL (OFFER) ---");
    try {
      if (_localStream == null) await initialize();

      _peerConnection = await _createPeerConnection(onCandidateCreated);

      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });

      await _peerConnection!.setLocalDescription(offer);
      _log("--- [WebRTC] Offer created successfully ---");
      onOfferCreated({'sdp': offer.sdp, 'type': offer.type});
    } catch (e) {
      _log("--- [WebRTC] ERROR in initiateCall: $e ---");
      rethrow;
    }
  }

  Future<void> answerCall({
    required Map<String, dynamic> offer,
    required Function(Map<String, dynamic> answer) onAnswerCreated,
    required Function(Map<String, dynamic> candidate) onCandidateCreated,
  }) async {
    _log("--- [WebRTC] ANSWERING CALL ---");
    try {
      if (_localStream == null) await initialize();

      _peerConnection = await _createPeerConnection(onCandidateCreated);
      await handleOffer(offer, onAnswerCreated: onAnswerCreated);
      _log("--- [WebRTC] Answer sent successfully ---");
    } catch (e) {
      _log("--- [WebRTC] ERROR in answerCall: $e ---");
      rethrow;
    }
  }

  void _registerPeerConnectionListeners(RTCPeerConnection pc, Function(Map<String, dynamic> candidate) onCandidateCreated) {
    pc.onConnectionState = (RTCPeerConnectionState state) {
      _log('--- [WebRTC] Connection State: $state ---');
    };
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;
      onCandidateCreated({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex
      });
    };
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _log("--- [WebRTC] REMOTE TRACK RECEIVED ---");
      }
    };
  }

  Future<void> handleOffer(Map<String, dynamic> offerData, { required Function(Map<String, dynamic> answer) onAnswerCreated }) async {
    if (_peerConnection == null) return;

    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _peerConnection!.setRemoteDescription(offer);

    // ВАЖНО: Устанавливаем флаг и применяем очередь
    _remoteDescriptionSet = true;
    await _drainCandidateQueue();

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    onAnswerCreated({'sdp': answer.sdp, 'type': answer.type});
  }

  Future<void> handleAnswer(Map<String, dynamic> answerData) async {
    if (_peerConnection == null) return;

    final answer = RTCSessionDescription(answerData['sdp'], answerData['type']);
    await _peerConnection!.setRemoteDescription(answer);

    // ВАЖНО: Устанавливаем флаг и применяем очередь
    _remoteDescriptionSet = true;
    await _drainCandidateQueue();
  }

  // БЕЗОПАСНОЕ ДОБАВЛЕНИЕ КАНДИДАТА
  Future<void> addCandidate(Map<String, dynamic> candidateData) async {
    try {
      final candidate = RTCIceCandidate(
          candidateData['candidate'],
          candidateData['sdpMid'],
          (candidateData['sdpMLineIndex'] as num).toInt()
      );

      if (_peerConnection != null && _remoteDescriptionSet) {
        await _peerConnection!.addCandidate(candidate);
        _log("✅ ICE Added immediately");
      } else {
        _log("⏳ ICE Queued (Waiting for SDP)");
        _queuedRemoteCandidates.add(candidate);
      }
    } catch (e) {
      _log("❌ ICE ERROR: $e");
    }
  }

  Future<void> _drainCandidateQueue() async {
    _log("--- [WebRTC] Draining Queue (${_queuedRemoteCandidates.length}) ---");
    for (final candidate in _queuedRemoteCandidates) {
      try {
        if (_peerConnection != null) {
          await _peerConnection!.addCandidate(candidate);
        }
      } catch (e) {
        _log("❌ ICE Queue Error: $e");
      }
    }
    _queuedRemoteCandidates.clear();
  }

  Future<void> hangUp() async {
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    _remoteStream?.getTracks().forEach((track) => track.stop());
    await _remoteStream?.dispose();
    _remoteStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    _remoteDescriptionSet = false;
    _queuedRemoteCandidates.clear();
  }
}