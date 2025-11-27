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
}

// --- КОНФИГУРАЦИЯ ICE (TURN/STUN) ---
// Обновлено для работы через порт 443 (обход блокировок)
const Map<String, dynamic> rtcConfiguration = {
  'iceServers': [
    // 1. STUN (Определение IP)
    {
      'urls': 'stun:213.171.10.108:3478',
    },
    // 2. TURN UDP (Стандартный порт 3478) - Самый быстрый
    {
      'urls': 'turn:213.171.10.108:3478',
      'username': 'orpheus',
      'credential': 'TEST112',
    },
    // 3. TURN TCP (Порт 443) - "Серебряная пуля" для обхода фаерволов
    // Работает, если на сервере в конфиге turnserver.conf есть listening-port=443
    {
      'urls': 'turn:213.171.10.108:443?transport=tcp',
      'username': 'orpheus',
      'credential': 'TEST112',
    },
  ],
  'sdpSemantics': 'unified-plan',
  // 'relay' = только через сервер (максимальная анонимность, скрывает IP).
  // 'all' = разрешает P2P (лучше качество, но палит IP собеседнику).
  // Для Production Secure Messenger лучше использовать 'relay', но нужен мощный сервер.
  // Пока оставляем 'all' для лучшего качества связи.
  'iceTransportPolicy': 'all',
  'bundlePolicy': 'max-bundle',
  'rtcpMuxPolicy': 'require',
};

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;

  final _logStreamController = BehaviorSubject<List<WebRTCLog>>();
  Stream<List<WebRTCLog>> get logStream => _logStreamController.stream;
  final List<WebRTCLog> _logs = [];

  // Очередь кандидатов (защита от гонки данных)
  final List<RTCIceCandidate> _queuedRemoteCandidates = [];
  bool _remoteDescriptionSet = false;

  void _addLog(WebRTCConnectionState state, {String? iceCandidateType}) {
    final log = WebRTCLog(state: state, iceCandidateType: iceCandidateType, timestamp: DateTime.now());
    _logs.add(log);
    if (!_logStreamController.isClosed) {
      _logStreamController.add(List.from(_logs));
    }
  }

  Future<void> initialize() async {
    // Запрашиваем разрешения заранее
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.bluetoothConnect, // Нужно для гарнитур на Android 12+
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
      print("WebRTC Error: Нет прав на микрофон");
      _addLog(WebRTCConnectionState.Failed);
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(Function(Map<String, dynamic> candidate) onCandidateCreated) async {
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
    if (_localStream == null) await initialize();

    _peerConnection = await _createPeerConnection(onCandidateCreated);

    // Создаем Offer
    RTCSessionDescription offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });

    await _peerConnection!.setLocalDescription(offer);

    onOfferCreated({'sdp': offer.sdp, 'type': offer.type});
  }

  Future<void> answerCall({
    required Map<String, dynamic> offer,
    required Function(Map<String, dynamic> answer) onAnswerCreated,
    required Function(Map<String, dynamic> candidate) onCandidateCreated,
  }) async {
    if (_localStream == null) await initialize();

    _peerConnection = await _createPeerConnection(onCandidateCreated);

    await handleOffer(offer, onAnswerCreated: onAnswerCreated);
  }

  void _registerPeerConnectionListeners(RTCPeerConnection pc, Function(Map<String, dynamic> candidate) onCandidateCreated) {
    pc.onConnectionState = (RTCPeerConnectionState state) {
      print('WebRTC Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _addLog(WebRTCConnectionState.Connected);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _addLog(WebRTCConnectionState.Failed);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _addLog(WebRTCConnectionState.Closed);
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      print('WebRTC ICE state: $state');
      WebRTCConnectionState? logState;
      switch(state) {
        case RTCIceConnectionState.RTCIceConnectionStateChecking: logState = WebRTCConnectionState.Connecting; break;
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted: logState = WebRTCConnectionState.Connected; break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected: logState = WebRTCConnectionState.Disconnected; break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed: logState = WebRTCConnectionState.Failed; break;
        default: break;
      }
      if (logState != null) _addLog(logState);
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;

      // Логируем тип кандидата (relay, srflx, host) для отладки
      String type = 'unknown';
      if (candidate.candidate!.contains('typ relay')) type = 'RELAY (TURN)';
      else if (candidate.candidate!.contains('typ srflx')) type = 'P2P (STUN)';
      else if (candidate.candidate!.contains('typ host')) type = 'LOCAL';

      print("WebRTC Generated Candidate: $type");

      onCandidateCreated({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex
      });
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        // По умолчанию звук идет в динамик (earpiece), переключение на громкую связь управляется из UI
        Helper.setSpeakerphoneOn(false);
      }
    };
  }

  Future<void> handleOffer(Map<String, dynamic> offerData, { required Function(Map<String, dynamic> answer) onAnswerCreated, }) async {
    if (_peerConnection == null) return;

    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _peerConnection!.setRemoteDescription(offer);

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

    _remoteDescriptionSet = true;
    await _drainCandidateQueue();
  }

  Future<void> addCandidate(Map<String, dynamic> candidateData) async {
    if (_peerConnection == null) return;

    final candidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex']
    );

    if (_remoteDescriptionSet) {
      await _peerConnection!.addCandidate(candidate);
    } else {
      _queuedRemoteCandidates.add(candidate);
    }
  }

  Future<void> _drainCandidateQueue() async {
    for (final candidate in _queuedRemoteCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _queuedRemoteCandidates.clear();
  }

  Future<void> hangUp() async {
    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
      _localStream = null;

      await _peerConnection?.close();
      _peerConnection = null;

      _remoteDescriptionSet = false;
      _queuedRemoteCandidates.clear();

      _logs.clear();
      _logStreamController.add([]);
    } catch (e) { print("Ошибка при hangUp: $e"); }
  }
}