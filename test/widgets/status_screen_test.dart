import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/screens/status_screen.dart';

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
  testWidgets('StatusScreen: smoke (без таймеров) и отображает заголовок', (tester) async {
    final client = _FakeHttpClient((req) async {
      if (req.url.toString().startsWith('http://ip-api.com/json/')) {
        return http.Response(jsonEncode({'countryCode': 'US', 'country': 'United States'}), 200);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StatusScreen(
          httpClient: client,
          disableTimersForTesting: true,
          debugPublicKeyBase64: 'ABCDEFGH1234',
          // databaseService/websocket/messageUpdates оставляем дефолтными: тест smoke.
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('СИСТЕМНЫЙ МОНИТОР'), findsOneWidget);
  });
}






