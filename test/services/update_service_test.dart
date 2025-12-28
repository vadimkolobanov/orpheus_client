import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus_project/services/update_service.dart';
import 'package:orpheus_project/config.dart';

void main() {
  group('UpdateService Tests', () {
    tearDown(() {
      UpdateService.debugResetForTesting();
    });

    test('resolveDownloadUrl: абсолютный URL не меняется', () {
      const url = 'https://update.orpheus.click/orpheus.apk';
      expect(UpdateService.resolveDownloadUrl(url), equals(url));
    });

    test('resolveDownloadUrl: относительный путь резолвится через AppConfig', () {
      const path = '/download';
      expect(UpdateService.resolveDownloadUrl(path), equals(AppConfig.httpUrl(path)));
    });

    test('getWithFallback: при ошибке первого хоста пробует следующий и возвращает ответ', () async {
      final called = <Uri>[];
      UpdateService.debugHttpGet = (uri) async {
        called.add(uri);
        // Первый хост (api.orpheus.click) "падает"
        if (uri.host == AppConfig.primaryApiHost) {
          throw http.ClientException('boom');
        }
        return http.Response('ok', 200);
      };

      final resp = await UpdateService.debugGetWithFallbackForTesting('/api/check-update');
      expect(resp, isNotNull);
      expect(resp!.statusCode, equals(200));
      expect(resp.body, equals('ok'));

      // Проверяем порядок fallback: новый домен -> legacy
      expect(called.map((u) => u.host).toList(), equals([AppConfig.primaryApiHost, AppConfig.legacyHost]));
    });

    testWidgets('checkForUpdate: показывает диалог, когда serverBuild > currentBuild, и закрывается по "ПОЗЖЕ"', (tester) async {
      UpdateService.debugResetForTesting();
      UpdateService.debugCurrentBuildNumberOverride = 1;
      UpdateService.debugHttpGet = (uri) async {
        return http.Response(
          '{"version_code":2,"download_url":"/download","version_name":"1.1.0","required":false}',
          200,
        );
      };

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );

      await UpdateService.checkForUpdate(ctx);
      await tester.pumpAndSettle();

      expect(find.text('ДОСТУПНО ОБНОВЛЕНИЕ'), findsOneWidget);
      expect(find.text('ПОЗЖЕ'), findsOneWidget);
      expect(find.text('СКАЧАТЬ'), findsOneWidget);

      await tester.tap(find.text('ПОЗЖЕ'));
      await tester.pumpAndSettle();

      expect(find.text('ДОСТУПНО ОБНОВЛЕНИЕ'), findsNothing);
    });

    testWidgets('checkForUpdate: required=true скрывает кнопку "ПОЗЖЕ"', (tester) async {
      UpdateService.debugResetForTesting();
      UpdateService.debugCurrentBuildNumberOverride = 1;
      UpdateService.debugHttpGet = (uri) async {
        return http.Response(
          '{"version_code":2,"download_url":"/download","version_name":"1.1.0","required":true}',
          200,
        );
      };

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );

      await UpdateService.checkForUpdate(ctx);
      await tester.pumpAndSettle();

      expect(find.text('ДОСТУПНО ОБНОВЛЕНИЕ'), findsOneWidget);
      expect(find.text('ПОЗЖЕ'), findsNothing);
      expect(find.text('СКАЧАТЬ'), findsOneWidget);
    });

    testWidgets('checkForUpdate: не показывает диалог, когда serverBuild <= currentBuild', (tester) async {
      UpdateService.debugResetForTesting();
      UpdateService.debugCurrentBuildNumberOverride = 2;
      UpdateService.debugHttpGet = (uri) async {
        return http.Response(
          '{"version_code":2,"download_url":"/download","version_name":"1.1.0","required":false}',
          200,
        );
      };

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );

      await UpdateService.checkForUpdate(ctx);
      await tester.pumpAndSettle();

      expect(find.text('ДОСТУПНО ОБНОВЛЕНИЕ'), findsNothing);
    });
  });
}

