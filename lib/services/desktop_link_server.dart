import 'dart:async';
import 'dart:io';

import 'package:orpheus_project/services/debug_logger_service.dart';

class DesktopLinkServerInfo {
  DesktopLinkServerInfo({
    required this.ip,
    required this.port,
  });

  final String ip;
  final int port;
}

abstract class DesktopLinkServer {
  bool get isRunning;
  DesktopLinkServerInfo? get info;

  Future<DesktopLinkServerInfo> start({int port});
  Future<void> stop();
}

class DesktopLinkServerImpl implements DesktopLinkServer {
  HttpServer? _server;
  DesktopLinkServerInfo? _info;
  WebSocket? _client;
  StreamSubscription? _serverSubscription;

  @override
  bool get isRunning => _server != null;

  @override
  DesktopLinkServerInfo? get info => _info;

  @override
  Future<DesktopLinkServerInfo> start({int port = 8765}) async {
    if (_info != null && _server != null) {
      return _info!;
    }

    final ip = await _resolveLocalIp();
    DebugLogger.info('DESKTOP_LINK', 'Starting WS server on $ip:$port');

    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
    } catch (e) {
      DebugLogger.warn('DESKTOP_LINK', 'Failed to bind WS server: $e');
      rethrow;
    }

    _info = DesktopLinkServerInfo(ip: ip, port: _server!.port);

    _serverSubscription = _server!.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('WebSocket upgrade required')
          ..close();
        return;
      }

      final socket = await WebSocketTransformer.upgrade(request);
      _client = socket;
      DebugLogger.success('DESKTOP_LINK', 'Desktop connected via WebSocket');

      socket.listen(
        (data) {
          DebugLogger.info('DESKTOP_LINK', 'WS message: $data');
        },
        onDone: () {
          DebugLogger.info('DESKTOP_LINK', 'Desktop disconnected');
          _client = null;
        },
        onError: (error) {
          DebugLogger.warn('DESKTOP_LINK', 'WS error: $error');
          _client = null;
        },
      );
    });

    return _info!;
  }

  @override
  Future<void> stop() async {
    await _client?.close();
    _client = null;
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _server?.close(force: true);
    _server = null;
    _info = null;
  }

  Future<String> _resolveLocalIp() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        final ip = address.address;
        if (!_isLinkLocal(ip)) {
          return ip;
        }
      }
    }

    throw StateError('No LAN IP detected');
  }

  bool _isLinkLocal(String ip) => ip.startsWith('169.254.');
}
