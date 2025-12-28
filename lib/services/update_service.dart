import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orpheus_project/config.dart';

class UpdateService {
  static bool _isUpdateDialogShown = false;

  static const Duration _networkTimeout = Duration(seconds: 5);

  // ===== Test hooks (DI/overrides) =====
  @visibleForTesting
  static int? debugCurrentBuildNumberOverride;

  /// Override для HTTP GET (например, чтобы симулировать timeout первого хоста и success второго).
  @visibleForTesting
  static Future<http.Response> Function(Uri uri)? debugHttpGet;

  /// Override для launchUrl (чтобы не дергать платформенный плагин в тестах).
  @visibleForTesting
  static Future<bool> Function(Uri url, {LaunchMode mode})? debugLaunchUrl;

  /// Сбросить флаги/override’ы между тестами.
  @visibleForTesting
  static void debugResetForTesting() {
    _isUpdateDialogShown = false;
    debugCurrentBuildNumberOverride = null;
    debugHttpGet = null;
    debugLaunchUrl = null;
  }

  @visibleForTesting
  static Future<http.Response?> debugGetWithFallbackForTesting(String path) {
    return _getWithFallback(path);
  }

  static Future<int> _getCurrentBuildNumber() async {
    final override = debugCurrentBuildNumberOverride;
    if (override != null) return override;

    // 1. Узнаем свою версию (из pubspec.yaml, цифра после +)
    final packageInfo = await PackageInfo.fromPlatform();
    return int.tryParse(packageInfo.buildNumber) ?? 0;
  }

  // Главный метод проверки
  static Future<void> checkForUpdate(BuildContext context) async {
    if (_isUpdateDialogShown) return; // Не спамить окнами

    try {
      final currentBuildNumber = await _getCurrentBuildNumber();

      print("UPDATE: Текущая сборка: $currentBuildNumber");

      // 2. Спрашиваем сервер
      // Запрос идет к API, которое читает версию из БД
      final response = await _getWithFallback('/api/check-update');

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);

        // Стараемся быть устойчивыми к типам (int vs string).
        final serverBuildNumberRaw = data['version_code'];
        final serverBuildNumber = switch (serverBuildNumberRaw) {
          int v => v,
          String v => int.tryParse(v) ?? 0,
          _ => 0,
        };
        final downloadUrl = (data['download_url'] ?? '').toString();
        final versionName = (data['version_name'] ?? '').toString();
        final isRequired = (data['required'] == true);

        print("UPDATE: Версия на сервере: $serverBuildNumber");

        // 3. Если на сервере версия больше -> предлагаем обновить
        if (serverBuildNumber > currentBuildNumber) {
          if (context.mounted) {
            _showUpdateDialog(context, versionName, downloadUrl, isRequired);
          }
        }
      }
    } catch (e) {
      print("UPDATE ERROR: $e");
    }
  }

  /// Запрос с fallback по списку `AppConfig.apiHosts`.
  /// Возвращает первый успешный ответ (HTTP 200..499/500 тоже как ответ),
  /// либо null если не удалось достучаться ни до одного хоста.
  static Future<http.Response?> _getWithFallback(String path) async {
    final httpGet = debugHttpGet ?? http.get;
    for (final urlStr in AppConfig.httpUrls(path)) {
      try {
        final uri = Uri.parse(urlStr);
        final resp = await httpGet(uri).timeout(_networkTimeout);
        return resp;
      } catch (_) {
        // пробуем следующий хост
        continue;
      }
    }
    return null;
  }

  static String resolveDownloadUrl(String urlPath) {
    // Абсолютные ссылки (например update.orpheus.click) используем как есть.
    if (urlPath.startsWith("http://") || urlPath.startsWith("https://")) {
      return urlPath;
    }
    // Относительные ссылки резолвим через текущий serverIp (новый домен в новых релизах).
    return AppConfig.httpUrl(urlPath);
  }

  static void _showUpdateDialog(BuildContext context, String version, String urlPath, bool required) {
    _isUpdateDialogShown = true;

    // Формируем полную ссылку
    String fullUrl = resolveDownloadUrl(urlPath);

    showDialog(
      context: context,
      barrierDismissible: !required, // Блокируем закрытие, если обновление обязательно
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.grey)),
        title: const Text("ДОСТУПНО ОБНОВЛЕНИЕ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Text(
          "Вышла новая версия $version.\n"
              "${required ? 'Это критическое обновление безопасности.' : 'Рекомендуем обновить приложение для стабильной работы.'}",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          if (!required)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _isUpdateDialogShown = false;
              },
              child: const Text("ПОЗЖЕ", style: TextStyle(color: Colors.grey)),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB0BEC5)),
            onPressed: () {
              _launchBrowser(fullUrl);
              if (!required) {
                Navigator.pop(context);
                _isUpdateDialogShown = false;
              }
            },
            child: const Text("СКАЧАТЬ", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Future<void> _launchBrowser(String urlString) async {
    final Uri url = Uri.parse(urlString);
    // Открываем во внешнем браузере, чтобы скачивание прошло надежно
    final launcher = debugLaunchUrl ?? launchUrl;
    if (!await launcher(url, mode: LaunchMode.externalApplication)) {
      print('Could not launch $url');
    }
  }
}