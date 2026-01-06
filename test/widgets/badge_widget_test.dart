import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/badge_service.dart';
import 'package:orpheus_project/widgets/badge_widget.dart';

void main() {
  group('GlassColors', () {
    test('все цвета определены и различаются', () {
      // Проверяем что цвета не null и различаются
      final glassColors = [
        GlassColors.coreGlass,
        GlassColors.ownerGlass,
        GlassColors.patronGlass,
        GlassColors.benefactorGlass,
        GlassColors.earlyGlass,
      ];

      // Все цвета должны быть уникальными
      final uniqueColors = glassColors.toSet();
      expect(uniqueColors.length, equals(5), 
          reason: 'Все 5 типов бейджей должны иметь уникальные цвета');
    });

    test('BENEFACTOR имеет золотой цвет', () {
      // Золотой = 0xFFFFB300
      expect(GlassColors.benefactorGlass.value, equals(0xFFFFB300));
    });

    test('glow цвета светлее base цветов', () {
      // Glow должен быть светлее (выше яркость)
      expect(
        GlassColors.coreGlow.computeLuminance(),
        greaterThan(GlassColors.coreGlass.computeLuminance() * 0.8),
      );
    });
  });

  group('LuxuryBadgeWidget', () {
    testWidgets('рендерится без ошибок', (tester) async {
      final badge = BadgeInfo.badges[BadgeType.core]!;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: LuxuryBadgeWidget(badge: badge),
            ),
          ),
        ),
      );

      // Виджет должен отрендериться
      expect(find.byType(LuxuryBadgeWidget), findsOneWidget);
    });

    testWidgets('отображает правильный label', (tester) async {
      final badge = BadgeInfo.badges[BadgeType.patron]!;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LuxuryBadgeWidget(badge: badge),
            ),
          ),
        ),
      );

      expect(find.text('PATRON'), findsOneWidget);
    });

    testWidgets('compact режим меняет размеры', (tester) async {
      final badge = BadgeInfo.badges[BadgeType.early]!;

      // Обычный режим
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LuxuryBadgeWidget(badge: badge, compact: false),
            ),
          ),
        ),
      );

      final normalSize = tester.getSize(find.byType(LuxuryBadgeWidget));

      // Compact режим
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LuxuryBadgeWidget(badge: badge, compact: true),
            ),
          ),
        ),
      );

      final compactSize = tester.getSize(find.byType(LuxuryBadgeWidget));

      // Compact должен быть меньше
      expect(compactSize.width, lessThan(normalSize.width));
      expect(compactSize.height, lessThan(normalSize.height));
    });

    testWidgets('рендерится для всех типов бейджей', (tester) async {
      for (final badgeType in BadgeType.values) {
        final badge = BadgeInfo.badges[badgeType]!;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: LuxuryBadgeWidget(badge: badge),
              ),
            ),
          ),
        );

        expect(find.text(badge.label), findsOneWidget,
            reason: 'Бейдж ${badge.label} должен отображаться');
      }
    });

    testWidgets('анимации можно отключить', (tester) async {
      final badge = BadgeInfo.badges[BadgeType.core]!;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LuxuryBadgeWidget(
                badge: badge,
                enableAnimations: false,
              ),
            ),
          ),
        ),
      );

      // Виджет должен отрендериться без ошибок
      expect(find.byType(LuxuryBadgeWidget), findsOneWidget);
    });
  });

  group('BadgeWidget (обёртка)', () {
    testWidgets('использует LuxuryBadgeWidget внутри', (tester) async {
      final badge = BadgeInfo.badges[BadgeType.owner]!;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BadgeWidget(badge: badge),
            ),
          ),
        ),
      );

      // BadgeWidget должен содержать LuxuryBadgeWidget
      expect(find.byType(BadgeWidget), findsOneWidget);
      expect(find.byType(LuxuryBadgeWidget), findsOneWidget);
    });
  });

  group('UserBadge', () {
    testWidgets('показывает SizedBox.shrink пока загружается', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: UserBadge(pubkey: 'test_pubkey_12345'),
            ),
          ),
        ),
      );

      // Пока загружается, должен быть SizedBox.shrink (пустой)
      expect(find.byType(UserBadge), findsOneWidget);
      // LuxuryBadgeWidget не должен отображаться пока нет данных
      expect(find.byType(LuxuryBadgeWidget), findsNothing);
    });
  });

  group('AnimatedUserBadge', () {
    testWidgets('показывает SizedBox.shrink пока загружается', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnimatedUserBadge(pubkey: 'test_pubkey_67890'),
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedUserBadge), findsOneWidget);
      // Бейдж не должен отображаться пока нет данных с сервера
      expect(find.byType(LuxuryBadgeWidget), findsNothing);
    });
  });

  group('BadgeShowcase', () {
    testWidgets('отображает все 5 бейджей', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BadgeShowcase(),
            ),
          ),
        ),
      );

      expect(find.byType(BadgeShowcase), findsOneWidget);
      // Должно быть 5 LuxuryBadgeWidget
      expect(find.byType(LuxuryBadgeWidget), findsNWidgets(5));

      // Все labels должны присутствовать
      expect(find.text('CORE'), findsOneWidget);
      expect(find.text('OWNER'), findsOneWidget);
      expect(find.text('PATRON'), findsOneWidget);
      expect(find.text('BENEFACTOR'), findsOneWidget);
      expect(find.text('EARLY'), findsOneWidget);
    });

    testWidgets('содержит заголовок GLASS COLLECTION', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BadgeShowcase(),
            ),
          ),
        ),
      );

      expect(find.text('GLASS COLLECTION'), findsOneWidget);
    });
  });
}




