import 'dart:convert';

import 'package:http/http.dart' as http;

class ReleaseNote {
  final int versionCode;
  final String versionName;
  final bool required;
  final String downloadUrl;
  final DateTime? createdAt;
  final String publicChangelog;

  ReleaseNote({
    required this.versionCode,
    required this.versionName,
    required this.required,
    required this.downloadUrl,
    required this.createdAt,
    required this.publicChangelog,
  });

  factory ReleaseNote.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] as String?;
    DateTime? createdAt;
    if (createdAtRaw != null && createdAtRaw.trim().isNotEmpty) {
      createdAt = DateTime.tryParse(createdAtRaw);
    }

    return ReleaseNote(
      versionCode: (json['version_code'] as num).toInt(),
      versionName: (json['version_name'] as String?) ?? '',
      required: (json['required'] as bool?) ?? false,
      downloadUrl: (json['download_url'] as String?) ?? '',
      createdAt: createdAt,
      publicChangelog: (json['public_changelog'] as String?) ?? '',
    );
  }
}

class ReleaseNotesService {
  /// Публичный сайт (orpheus.click) обслуживает public API админки.
  /// В проде это должен быть домен сайта.
  static const List<String> _baseUrls = [
    'https://orpheus.click',
  ];

  Future<List<ReleaseNote>> fetchPublicReleases({int limit = 30}) async {
    Object? lastError;

    for (final base in _baseUrls) {
      final url = Uri.parse('$base/api/public/releases?limit=$limit');
      try {
        final res = await http
            .get(url, headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 8));

        if (res.statusCode < 200 || res.statusCode >= 300) {
          lastError = 'HTTP ${res.statusCode}';
          continue;
        }

        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is! List) {
          lastError = 'Bad JSON shape';
          continue;
        }

        return decoded
            .whereType<Map<String, dynamic>>()
            .map(ReleaseNote.fromJson)
            .toList();
      } catch (e) {
        lastError = e;
        continue;
      }
    }

    throw Exception('Не удалось загрузить release notes: $lastError');
  }
}


