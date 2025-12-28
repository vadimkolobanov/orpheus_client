import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/services/release_notes_service.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final resp = await _handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(resp.bodyBytes),
      resp.statusCode,
      headers: resp.headers,
      request: request,
      reasonPhrase: resp.reasonPhrase,
    );
  }
}

void main() {
  group('ReleaseNotesService (контракты)', () {
    tearDown(() {
      ReleaseNotesService.debugBaseUrlsOverride = null;
    });

    test('fetchPublicReleases: парсит список и нормализует поля', () async {
      ReleaseNotesService.debugBaseUrlsOverride = ['https://example.test'];

      final client = _FakeHttpClient((req) async {
        expect(req.url.toString(), equals('https://example.test/api/public/releases?limit=30'));
        final payload = [
          {
            'version_code': 6,
            'version_name': '1.1.0',
            'required': true,
            'download_url': '/orpheus.apk',
            'created_at': '2025-12-12T10:00:00Z',
            'public_changelog': '- A\n- B',
          }
        ];
        return http.Response.bytes(utf8.encode(jsonEncode(payload)), 200, headers: {'content-type': 'application/json'});
      });

      final service = ReleaseNotesService(httpClient: client);
      final notes = await service.fetchPublicReleases();

      expect(notes, hasLength(1));
      expect(notes.single.versionCode, equals(6));
      expect(notes.single.versionName, equals('1.1.0'));
      expect(notes.single.required, isTrue);
      expect(notes.single.downloadUrl, equals('/orpheus.apk'));
      expect(notes.single.createdAt, isNotNull);
      expect(notes.single.publicChangelog, contains('A'));
    });

    test('fetchPublicReleases: при не-2xx пробует следующий baseUrl и в конце бросает', () async {
      ReleaseNotesService.debugBaseUrlsOverride = ['https://a.test', 'https://b.test'];

      var calls = 0;
      final client = _FakeHttpClient((req) async {
        calls += 1;
        if (req.url.host == 'a.test') {
          return http.Response('nope', 500);
        }
        return http.Response('not a list', 200);
      });

      final service = ReleaseNotesService(httpClient: client);

      await expectLater(
        () => service.fetchPublicReleases(limit: 1),
        throwsA(isA<Exception>()),
      );
      expect(calls, equals(2));
    });
  });
}




