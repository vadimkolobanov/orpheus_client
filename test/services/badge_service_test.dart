import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/badge_service.dart';

void main() {
  group('BadgeType enum', () {
    test('содержит все 5 типов бейджей', () {
      expect(BadgeType.values.length, equals(5));
      expect(BadgeType.values, contains(BadgeType.core));
      expect(BadgeType.values, contains(BadgeType.owner));
      expect(BadgeType.values, contains(BadgeType.patron));
      expect(BadgeType.values, contains(BadgeType.benefactor));
      expect(BadgeType.values, contains(BadgeType.early));
    });
  });

  group('BadgeInfo', () {
    test('badges map содержит все типы', () {
      expect(BadgeInfo.badges.length, equals(5));
      expect(BadgeInfo.badges.containsKey(BadgeType.core), isTrue);
      expect(BadgeInfo.badges.containsKey(BadgeType.owner), isTrue);
      expect(BadgeInfo.badges.containsKey(BadgeType.patron), isTrue);
      expect(BadgeInfo.badges.containsKey(BadgeType.benefactor), isTrue);
      expect(BadgeInfo.badges.containsKey(BadgeType.early), isTrue);
    });

    test('каждый бейдж имеет правильный label', () {
      expect(BadgeInfo.badges[BadgeType.core]!.label, equals('CORE'));
      expect(BadgeInfo.badges[BadgeType.owner]!.label, equals('OWNER'));
      expect(BadgeInfo.badges[BadgeType.patron]!.label, equals('PATRON'));
      expect(BadgeInfo.badges[BadgeType.benefactor]!.label, equals('BENEFACTOR'));
      expect(BadgeInfo.badges[BadgeType.early]!.label, equals('EARLY'));
    });

    test('typeString возвращает имя типа', () {
      expect(BadgeInfo.badges[BadgeType.core]!.typeString, equals('core'));
      expect(BadgeInfo.badges[BadgeType.owner]!.typeString, equals('owner'));
      expect(BadgeInfo.badges[BadgeType.patron]!.typeString, equals('patron'));
      expect(BadgeInfo.badges[BadgeType.benefactor]!.typeString, equals('benefactor'));
      expect(BadgeInfo.badges[BadgeType.early]!.typeString, equals('early'));
    });

    test('каждый бейдж имеет уникальные цвета', () {
      final colors = <Color>{};
      for (final badge in BadgeInfo.badges.values) {
        // backgroundColor должен быть уникальным для каждого бейджа
        expect(colors.contains(badge.backgroundColor), isFalse,
            reason: 'Дублирующийся цвет для ${badge.label}');
        colors.add(badge.backgroundColor);
      }
    });

    test('BENEFACTOR имеет золотой цвет', () {
      final benefactor = BadgeInfo.badges[BadgeType.benefactor]!;
      // Проверяем что цвет в золотом диапазоне (0xFFFFB300)
      expect(benefactor.backgroundColor.value, equals(0xFFFFB300));
    });

    group('fromString', () {
      test('возвращает правильный бейдж для валидных строк', () {
        expect(BadgeInfo.fromString('core')?.type, equals(BadgeType.core));
        expect(BadgeInfo.fromString('owner')?.type, equals(BadgeType.owner));
        expect(BadgeInfo.fromString('patron')?.type, equals(BadgeType.patron));
        expect(BadgeInfo.fromString('benefactor')?.type, equals(BadgeType.benefactor));
        expect(BadgeInfo.fromString('early')?.type, equals(BadgeType.early));
      });

      test('регистронезависимый поиск', () {
        expect(BadgeInfo.fromString('CORE')?.type, equals(BadgeType.core));
        expect(BadgeInfo.fromString('Core')?.type, equals(BadgeType.core));
        expect(BadgeInfo.fromString('PATRON')?.type, equals(BadgeType.patron));
      });

      test('возвращает null для невалидных строк', () {
        expect(BadgeInfo.fromString(null), isNull);
        expect(BadgeInfo.fromString(''), isNull);
        expect(BadgeInfo.fromString('invalid'), isNull);
        expect(BadgeInfo.fromString('admin'), isNull);
        expect(BadgeInfo.fromString('vip'), isNull);
      });
    });
  });

  group('BadgeService', () {
    test('instance возвращает singleton', () {
      final instance1 = BadgeService.instance;
      final instance2 = BadgeService.instance;
      expect(identical(instance1, instance2), isTrue);
    });

    test('getBadgeCached возвращает null для неизвестного pubkey', () {
      final service = BadgeService.instance;
      final result = service.getBadgeCached('unknown_pubkey_12345');
      expect(result, isNull);
    });

    test('clearCache очищает кеш', () {
      final service = BadgeService.instance;
      // Сначала очищаем
      service.clearCache();
      // Проверяем что кеш пустой
      expect(service.getBadgeCached('any_key'), isNull);
    });

    test('invalidate удаляет конкретный ключ из кеша', () {
      final service = BadgeService.instance;
      service.clearCache();
      // invalidate не должен выбрасывать ошибку даже если ключа нет
      expect(() => service.invalidate('nonexistent_key'), returnsNormally);
    });
  });

  group('Приоритет бейджей (бизнес-логика)', () {
    // Приоритет: core > owner > patron > benefactor > early
    test('CORE имеет высший приоритет', () {
      // core должен быть первым в enum (индекс 0 = высший приоритет)
      expect(BadgeType.core.index, equals(0));
    });

    test('EARLY имеет низший приоритет', () {
      // early должен быть последним
      expect(BadgeType.early.index, equals(4));
    });

    test('порядок приоритетов: core > owner > patron > benefactor > early', () {
      expect(BadgeType.core.index, lessThan(BadgeType.owner.index));
      expect(BadgeType.owner.index, lessThan(BadgeType.patron.index));
      expect(BadgeType.patron.index, lessThan(BadgeType.benefactor.index));
      expect(BadgeType.benefactor.index, lessThan(BadgeType.early.index));
    });
  });
}

