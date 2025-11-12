// lib/services/webrtc_service.dart

import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

// --- ИЗМЕНЕНИЕ ЗДЕСЬ: Добавляем ваш TURN-сервер в конфигурацию ---
const Map<String, dynamic> rtcConfiguration = {
  'iceServers': [
    // Мы по-прежнему оставляем STUN-сервер от Google. Он быстрый и бесплатный.
    // Клиент сначала попробует соединиться через него.
    {'urls': 'stun:stun.l.google.com:19302'},

    // Если STUN не справится (как в случае со звонком в РФ),
    // клиент будет использовать ваш TURN-сервер как запасной вариант.
    {
      'urls': 'turn:213.171.10.108:3478', // Адрес вашего сервера и порт
      'username': 'orpheus',               // Имя пользователя из конфига
      'credential': 'TEST112',             // Пароль из конфига
    },
  ]
};
// --- КОНЕЦ ИЗМЕНЕНИЯ ---

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get remoteStream => _remoteStream;

  Future<void> initialize() async {
    if (await _requestPermissions()) {
      _localStream = await mediaDevices.getUserMedia({'audio': true, 'video': false});
    } else {
      print("Не удалось получить разрешения на использование микрофона.");
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
    if (_localStream == null) {
      print("Локальный аудиопоток не инициализирован!");
      return;
    }

    _peerConnection = await createPeerConnection(rtcConfiguration);

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      print("Найден ICE Candidate: ${candidate.candidate}");
      final candidateMap = {
        'candidate': candidate.candidate, 'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      onCandidateCreated(candidateMap);
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      print("Получен удаленный аудиопоток!");
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
      }
    };

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
    if (_localStream == null) {
      print("Локальный аудиопоток не инициализирован!");
      return;
    }

    _peerConnection = await createPeerConnection(rtcConfiguration);

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      final candidateMap = {
        'candidate': candidate.candidate, 'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      onCandidateCreated(candidateMap);
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
      }
    };

    await handleOffer(offer, onAnswerCreated: onAnswerCreated);
  }

  Future<void> handleOffer(Map<String, dynamic> offerData, {
    required Function(Map<String, dynamic> answer) onAnswerCreated,
  }) async {
    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _peerConnection!.setRemoteDescription(offer);

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    final answerMap = {'sdp': answer.sdp, 'type': answer.type};
    onAnswerCreated(answerMap);
  }

  Future<void> handleAnswer(Map<String, dynamic> answerData) async {
    final answer = RTCSessionDescription(answerData['sdp'], answerData['type']);
    await _peerConnection!.setRemoteDescription(answer);
  }

  Future<void> addCandidate(Map<String, dynamic> candidateData) async {
    if (candidateData['candidate'] == null) return;
    final candidate = RTCIceCandidate(
      candidateData['candidate'], candidateData['sdpMid'], candidateData['sdpMLineIndex'],
    );
    await _peerConnection!.addCandidate(candidate);
  }

  Future<void> hangUp() async {
    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
      await _remoteStream?.dispose();
      await _peerConnection?.close();
      _peerConnection = null;
      _localStream = null;
      _remoteStream = null;
      print("Звонок завершен, ресурсы очищены.");
    } catch (e) {
      print("Ошибка при завершении звонка: $e");
    }
  }
}