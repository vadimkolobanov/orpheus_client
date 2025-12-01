import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MaterialApp(home: WebRTCTestScreen()));
}

class WebRTCTestScreen extends StatefulWidget {
  const WebRTCTestScreen({super.key});

  @override
  State<WebRTCTestScreen> createState() => _WebRTCTestScreenState();
}

class _WebRTCTestScreenState extends State<WebRTCTestScreen> {
  RTCPeerConnection? _pc;
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  // --- КОНФИГ 1: METERED.CA (Эталон) ---
  final Map<String, dynamic> _configMetered = {
    'iceServers': [
      {
        'urls': [
          'turn:global.relay.metered.ca:80?transport=tcp',
          'turn:global.relay.metered.ca:443?transport=tcp',
          'turn:global.relay.metered.ca:80',
        ],
        'username': '0208b66b97bf51566d2c1ac7',
        'credential': 'VOt/phLyIwb/cryn',
      },
    ],
    'iceTransportPolicy': 'relay', // Только через сервер
    'sdpSemantics': 'unified-plan',
  };

  // --- КОНФИГ 2: ТВОЙ СЕРВЕР ---
  final Map<String, dynamic> _configMyServer = {
    'iceServers': [
      {
        'urls': [
          'turn:213.171.10.108:443?transport=tcp',
          'turn:213.171.10.108:3478?transport=tcp',
          'turn:213.171.10.108:3478',
        ],
        'username': 'orpheus',
        'credential': 'TEST112',
      },
    ],
    'iceTransportPolicy': 'relay', // Только через сервер
    'sdpSemantics': 'unified-plan',
  };

  void _log(String msg) {
    setState(() {
      _logs.add("${DateTime.now().toString().substring(11, 19)} $msg");
    });
    // Автоскролл вниз
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _startTest(Map<String, dynamic> config, String name) async {
    await _stop(); // Сброс перед тестом
    _log("--- ЗАПУСК ТЕСТА: $name ---");

    // 1. Права
    _log("Запрос прав...");
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.bluetoothConnect,
    ].request();

    if (!statuses[Permission.microphone]!.isGranted) {
      _log("!!! ОШИБКА: Нет прав на микрофон");
      return;
    }

    try {
      // 2. Создание PC
      _log("Создание PeerConnection...");
      _pc = await createPeerConnection(config);

      // 3. Слушатели
      _pc!.onIceConnectionState = (state) {
        _log("ICE State: $state");
      };

      _pc!.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        String type = 'UNKNOWN';
        if (candidate.candidate!.contains('typ relay')) {
          type = 'RELAY (OK)';
        } else if (candidate.candidate!.contains('typ srflx')) type = 'STUN';
        else if (candidate.candidate!.contains('typ host')) type = 'HOST';

        _log("✅ КАНДИДАТ: $type");
        _log("   IP: ${candidate.candidate?.split(' ')[4]} Port: ${candidate.candidate?.split(' ')[5]}");
      };

      // 4. Добавляем трансивер (чтобы WebRTC начал работу)
      _log("Добавление аудио-трансивера...");
      await _pc!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );

      // 5. Создаем Offer (это запускает сбор кандидатов)
      _log("Создание Offer...");
      RTCSessionDescription offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      _log("Local Description Set. Ждем кандидатов...");

    } catch (e) {
      _log("!!! ИСКЛЮЧЕНИЕ: $e");
    }
  }

  Future<void> _stop() async {
    if (_pc != null) {
      await _pc!.close();
      _pc = null;
    }
    setState(() => _logs.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("WebRTC Lab"), backgroundColor: Colors.grey[900]),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () => _startTest(_configMetered, "METERED (PAID)"),
                child: const Text("TEST METERED"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () => _startTest(_configMyServer, "MY SERVER"),
                child: const Text("TEST MY SERVER"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                border: Border.all(color: Colors.white24),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  Color color = Colors.white;
                  if (log.contains("✅")) color = Colors.greenAccent;
                  if (log.contains("!!!")) color = Colors.redAccent;
                  if (log.contains("---")) color = Colors.yellow;

                  return Text(log, style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 12));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}