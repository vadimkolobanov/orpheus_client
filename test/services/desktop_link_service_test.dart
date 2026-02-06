import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/models/desktop_session_model.dart';
import 'package:orpheus_project/services/desktop_link_service.dart';
import 'package:orpheus_project/services/desktop_link_server.dart';

class _InMemoryDesktopLinkStorage implements DesktopLinkStorage {
  final Map<String, String> _kv = {};

  @override
  Future<String?> read({required String key}) async => _kv[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _kv[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _kv.remove(key);
  }
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._response);

  final http.Response _response;
  Uri? lastUrl;
  String? lastMethod;
  Map<String, String> lastHeaders = {};
  String? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUrl = request.url;
    lastMethod = request.method;
    lastHeaders = request.headers;
    final bodyBytes = await request.finalize().toBytes();
    lastBody = utf8.decode(bodyBytes);

    return http.StreamedResponse(
      Stream.value(utf8.encode(_response.body)),
      _response.statusCode,
      headers: _response.headers,
      reasonPhrase: _response.reasonPhrase,
    );
  }
}

class _FakeDesktopLinkServer implements DesktopLinkServer {
  _FakeDesktopLinkServer(this._info);

  DesktopLinkServerInfo _info;
  bool _running = false;

  @override
  DesktopLinkServerInfo? get info => _running ? _info : null;

  @override
  bool get isRunning => _running;

  @override
  Future<DesktopLinkServerInfo> start({int port = 8765}) async {
    _running = true;
    return _info;
  }

  @override
  Future<void> stop() async {
    _running = false;
  }
}

void main() {
  group('DesktopLinkService', () {
    test('parseQrPayload: возвращает структуру при валидном QR', () {
      final now = DateTime(2026, 2, 4, 12, 0);
      final payload = json.encode({
        'cmd': 'link.request',
        'data': {
          'desktop_id': 'desk-1',
          'desktop_name': 'Windows PC',
          'desktop_pubkey': 'pubkey',
          'lan_ip': '192.168.1.10',
          'lan_port': 8766,
          'nonce': 'nonce',
          'expires': now.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
        }
      });

      final request = DesktopLinkRequest.parse(payload, now);
      expect(request.desktopId, 'desk-1');
      expect(request.desktopName, 'Windows PC');
      expect(request.lanIp, '192.168.1.10');
      expect(request.lanPort, 8766);
    });

    test('parseQrPayload: просроченный QR — ошибка expired', () {
      final now = DateTime(2026, 2, 4, 12, 0);
      final payload = json.encode({
        'cmd': 'link.request',
        'data': {
          'desktop_id': 'desk-1',
          'desktop_name': 'Windows PC',
          'desktop_pubkey': 'pubkey',
          'lan_ip': '192.168.1.10',
          'lan_port': 8766,
          'nonce': 'nonce',
          'expires': now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
        }
      });

      expect(
        () => DesktopLinkRequest.parse(payload, now),
        throwsA(
          isA<DesktopLinkException>()
              .having((e) => e.code, 'code', DesktopLinkErrorCode.expired),
        ),
      );
    });

    test('pairFromQr: отправляет link.confirm и сохраняет сессию', () async {
      final now = DateTime(2026, 2, 4, 12, 0);
      final payload = json.encode({
        'cmd': 'link.request',
        'data': {
          'desktop_id': 'desk-1',
          'desktop_name': 'Windows PC',
          'desktop_pubkey': 'pubkey',
          'lan_ip': '192.168.1.10',
          'lan_port': 8766,
          'nonce': 'nonce',
          'expires': now.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
        }
      });

      final storage = _InMemoryDesktopLinkStorage();
      final client = _RecordingClient(http.Response('ok', 200));
      final server = _FakeDesktopLinkServer(
        DesktopLinkServerInfo(ip: '192.168.1.20', port: 8765),
      );

      final service = DesktopLinkService.createForTesting(
        storage: storage,
        server: server,
        httpClient: client,
        now: () => now,
        deviceNameProvider: () async => 'TestPhone',
      );

      final result = await service.pairFromQr(payload);

      expect(client.lastUrl.toString(), 'http://192.168.1.10:8766/');
      expect(client.lastMethod, 'POST');
      expect(client.lastHeaders['Content-Type'], startsWith('application/json'));

      final body = json.decode(client.lastBody!) as Map<String, dynamic>;
      expect(body['cmd'], 'link.confirm');
      expect(body['data']['otp'], result.otp);
      expect(body['data']['session_token'], isNotEmpty);
      expect(body['data']['phone_name'], 'TestPhone');
      expect(body['data']['server_ip'], '192.168.1.20');
      expect(body['data']['server_port'], 8765);

      final stored = await storage.read(key: 'desktop_link_session');
      final session = DesktopSession.tryFromJson(stored);
      expect(session, isNotNull);
      expect(session!.desktopId, 'desk-1');
      expect(session.otp, result.otp);
    });
  });
}
