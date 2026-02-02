import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/config.dart';
import 'package:orpheus_project/main.dart' show cryptoService, isAppInForeground;
import 'package:orpheus_project/services/debug_logger_service.dart';
import 'package:orpheus_project/services/network_monitor_service.dart';

class TelemetryService {
  TelemetryService._();
  static final TelemetryService instance = TelemetryService._();

  static const int _maxQueueSize = 5000;
  static const int _batchSize = 50;
  static const Duration _flushInterval = Duration(seconds: 5);

  final http.Client _httpClient = http.Client();
  final List<LogEntry> _queue = [];
  StreamSubscription<LogEntry>? _entrySubscription;
  Timer? _flushTimer;
  bool _sending = false;

  String? _deviceInfo;
  String? _osName;

  bool _enabled = true;

  Future<void> init() async {
    if (!_enabled) return;
    _deviceInfo = await _getDeviceInfo();
    _osName = _detectOs();

    _entrySubscription = DebugLogger.onEntry.listen(_onLogEntry);
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  void _onLogEntry(LogEntry entry) {
    if (!_enabled) return;
    _queue.add(entry);
    if (_queue.length > _maxQueueSize) {
      _queue.removeRange(0, _queue.length - _maxQueueSize);
    }
    if (_queue.length >= _batchSize) {
      flush();
    }
  }

  Future<void> flush() async {
    if (_sending || _queue.isEmpty) return;
    final pubkey = cryptoService.publicKeyBase64;
    if (pubkey == null || pubkey.isEmpty) return;

    _sending = true;
    final batch = _queue.take(_batchSize).toList();
    _queue.removeRange(0, batch.length);

    try {
      final payload = {
        'source': 'client',
        'entries': batch.map(_serializeEntry).toList(),
      };
      final body = json.encode(payload);

      for (final url in AppConfig.httpUrls('/api/logs/batch')) {
        final ok = await _trySend(url, pubkey, body);
        if (ok) break;
      }
    } catch (_) {
      // Ошибки телеметрии не должны влиять на приложение
    } finally {
      _sending = false;
    }
  }

  Map<String, dynamic> _serializeEntry(LogEntry entry) {
    final context = entry.context ?? const {};
    return {
      'timestamp': entry.timestamp.toIso8601String(),
      'level': entry.level.name,
      'tag': entry.tag,
      'category': entry.tag,
      'message': entry.message,
      'details': context,
      'call_id': context['call_id'],
      'peer_pubkey': context['peer_pubkey'],
      'device_info': _deviceInfo,
      'app_version': AppConfig.appVersion,
      'os': _osName,
      'network': NetworkMonitorService.instance.currentState.name,
      'app_state': isAppInForeground ? 'foreground' : 'background',
    };
  }

  Future<bool> _trySend(String url, String pubkey, String body) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Pubkey': pubkey,
        },
        body: body,
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _detectOs() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return Platform.operatingSystem;
  }

  Future<String> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return 'Android ${info.version.release} • ${info.manufacturer} ${info.model}';
      }
      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return 'iOS ${info.systemVersion} • ${info.model}';
      }
      if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        return 'Windows ${info.productName} ${info.buildNumber}';
      }
      if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        return 'macOS ${info.osRelease}';
      }
      if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        return 'Linux ${info.prettyName}';
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }

  void dispose() {
    _entrySubscription?.cancel();
    _flushTimer?.cancel();
    _httpClient.close();
  }
}
