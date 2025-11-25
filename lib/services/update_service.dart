import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orpheus_project/config.dart';

class UpdateService {
  static bool _isUpdateDialogShown = false;

  // Главный метод проверки
  static Future<void> checkForUpdate(BuildContext context) async {
    if (_isUpdateDialogShown) return; // Не спамить окнами

    try {
      // 1. Узнаем свою версию (из pubspec.yaml, цифра после +)
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      print("UPDATE: Текущая сборка: $currentBuildNumber");

      // 2. Спрашиваем сервер
      // Запрос идет к API, которое читает версию из БД
      final url = Uri.parse(AppConfig.httpUrl('/api/check-update'));
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        int serverBuildNumber = data['version_code'];
        String downloadUrl = data['download_url'];
        String versionName = data['version_name'];
        bool isRequired = data['required'] ?? false;

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

  static void _showUpdateDialog(BuildContext context, String version, String urlPath, bool required) {
    _isUpdateDialogShown = true;

    // Формируем полную ссылку
    String fullUrl = urlPath.startsWith("http")
        ? urlPath
        : AppConfig.httpUrl(urlPath);

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
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      print('Could not launch $url');
    }
  }
}