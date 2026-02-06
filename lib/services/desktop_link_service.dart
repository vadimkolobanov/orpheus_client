import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:orpheus_project/models/desktop_session_model.dart';
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/desktop_link_server.dart';

abstract class DesktopLinkStorage {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterDesktopLinkStorage implements DesktopLinkStorage {
  FlutterDesktopLinkStorage(this._inner);
  final FlutterSecureStorage _inner;

  @override
  Future<String?> read({required String key}) => _inner.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _inner.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _inner.delete(key: key);
}

enum DesktopLinkErrorCode {
  invalidPayload,
  expired,
  network,
  unknown,
}

class DesktopLinkException implements Exception {
  DesktopLinkException(this.code, this.message);

  final DesktopLinkErrorCode code;
  final String message;

  @override
  String toString() => 'DesktopLinkException($code, $message)';
}

class DesktopLinkRequest {
  DesktopLinkRequest({
    required this.desktopId,
    required this.desktopName,
    required this.desktopPubkey,
    required this.lanIp,
    required this.lanPort,
    required this.nonce,
    required this.expiresAt,
  });

  final String desktopId;
  final String desktopName;
  final String desktopPubkey;
  final String lanIp;
  final int lanPort;
  final String nonce;
  final DateTime expiresAt;

  static DesktopLinkRequest parse(String qrPayload, DateTime now) {
    Map<String, dynamic> payload;
    try {
      payload = json.decode(qrPayload) as Map<String, dynamic>;
    } catch (_) {
      throw DesktopLinkException(
        DesktopLinkErrorCode.invalidPayload,
        'QR payload is not valid JSON',
      );
    }

    if (payload['cmd'] != 'link.request') {
      throw DesktopLinkException(
        DesktopLinkErrorCode.invalidPayload,
        'Unsupported command in QR payload',
      );
    }

    final data = payload['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw DesktopLinkException(
        DesktopLinkErrorCode.invalidPayload,
        'Missing data in QR payload',
      );
    }

    final expiresMs = data['expires'];
    if (expiresMs is! int) {
      throw DesktopLinkException(
        DesktopLinkErrorCode.invalidPayload,
        'Invalid expires field',
      );
    }

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresMs);
    if (!expiresAt.isAfter(now)) {
      throw DesktopLinkException(
        DesktopLinkErrorCode.expired,
        'QR payload expired',
      );
    }

    final lanPort = data['lan_port'];
    if (lanPort is! int) {
      throw DesktopLinkException(
        DesktopLinkErrorCode.invalidPayload,
        'Invalid lan_port field',
      );
    }

    return DesktopLinkRequest(
      desktopId: data['desktop_id'] as String,
      desktopName: data['desktop_name'] as String,
      desktopPubkey: data['desktop_pubkey'] as String,
      lanIp: data['lan_ip'] as String,
      lanPort: lanPort,
      nonce: data['nonce'] as String,
      expiresAt: expiresAt,
    );
  }
}

class DesktopLinkPairingResult {
  DesktopLinkPairingResult({
    required this.otp,
    required this.session,
  });

  final String otp;
  final DesktopSession session;
}

class DesktopLinkService {
  static final DesktopLinkService instance = DesktopLinkService._();

  static DesktopLinkService createForTesting({
    required DesktopLinkStorage storage,
    DesktopLinkServer? server,
    http.Client? httpClient,
    DateTime Function()? now,
    Future<String> Function()? deviceNameProvider,
  }) {
    return DesktopLinkService._(
      storage: storage,
      server: server,
      httpClient: httpClient,
      now: now,
      deviceNameProvider: deviceNameProvider,
    );
  }

  DesktopLinkService._({
    DesktopLinkStorage? storage,
    DesktopLinkServer? server,
    http.Client? httpClient,
    DateTime Function()? now,
    Future<String> Function()? deviceNameProvider,
  })  : _storage =
            storage ?? FlutterDesktopLinkStorage(const FlutterSecureStorage()),
        _server = server ?? DesktopLinkServerImpl(),
        _httpClient = httpClient ?? http.Client(),
        _now = now ?? DateTime.now,
        _deviceNameProvider = deviceNameProvider;

  static const _sessionKey = 'desktop_link_session';

  final DesktopLinkStorage _storage;
  final DesktopLinkServer _server;
  final http.Client _httpClient;
  final DateTime Function() _now;
  final Future<String> Function()? _deviceNameProvider;

  Future<DesktopSession?> loadSession() async {
    final raw = await _storage.read(key: _sessionKey);
    return DesktopSession.tryFromJson(raw);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _sessionKey);
  }

  Future<DesktopLinkPairingResult> pairFromQr(String qrPayload) async {
    final request = DesktopLinkRequest.parse(qrPayload, _now());
    final otp = _generateOtp();
    final sessionToken = _generateSessionToken();
    final phoneName = await _getPhoneName();
    final serverInfo = await _ensureServer();

    final confirmPayload = json.encode({
      'cmd': 'link.confirm',
      'data': {
        'session_token': sessionToken,
        'otp': otp,
        'phone_name': phoneName,
        'server_port': serverInfo.port,
        'server_ip': serverInfo.ip,
      },
    });

    final uri = Uri.parse('http://${request.lanIp}:${request.lanPort}/');

    DebugLogger.info('DESKTOP_LINK', 'Sending link.confirm to $uri');

    http.Response response;
    try {
      response = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: confirmPayload,
      );
    } catch (e) {
      DebugLogger.warn('DESKTOP_LINK', 'Network error: $e');
      throw DesktopLinkException(
        DesktopLinkErrorCode.network,
        'Failed to reach desktop',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      DebugLogger.warn(
        'DESKTOP_LINK',
        'Desktop responded with status ${response.statusCode}',
      );
      throw DesktopLinkException(
        DesktopLinkErrorCode.network,
        'Desktop rejected pairing',
      );
    }

    final session = DesktopSession(
      desktopId: request.desktopId,
      desktopName: request.desktopName,
      desktopPubkey: request.desktopPubkey,
      lanIp: request.lanIp,
      lanPort: request.lanPort,
      sessionToken: sessionToken,
      otp: otp,
      phoneName: phoneName,
      createdAt: _now(),
    );

    await _storage.write(key: _sessionKey, value: session.toJson());

    return DesktopLinkPairingResult(otp: otp, session: session);
  }

  Future<DesktopLinkServerInfo> _ensureServer() async {
    if (_server.isRunning && _server.info != null) {
      return _server.info!;
    }

    try {
      return await _server.start();
    } catch (e) {
      DebugLogger.warn('DESKTOP_LINK', 'Failed to start server: $e');
      throw DesktopLinkException(
        DesktopLinkErrorCode.network,
        'Failed to start desktop link server',
      );
    }
  }

  String _generateOtp() {
    final value = Random.secure().nextInt(9000) + 1000;
    return value.toString();
  }

  String _generateSessionToken() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes);
  }

  Future<String> _getPhoneName() async {
    if (_deviceNameProvider != null) {
      return _deviceNameProvider!();
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return info.model.isNotEmpty ? info.model : 'Android';
      }
      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return info.name.isNotEmpty ? info.name : 'iPhone';
      }
    } catch (e) {
      DebugLogger.warn('DESKTOP_LINK', 'Failed to resolve device name: $e');
    }

    return 'Orpheus Phone';
  }
}
