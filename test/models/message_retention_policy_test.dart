// test/models/message_retention_policy_test.dart
// Тесты для MessageRetentionPolicy

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/models/message_retention_policy.dart';

void main() {
  group('MessageRetentionPolicy', () {
    group('retentionDuration', () {
      test('all returns null (no limit)', () {
        expect(MessageRetentionPolicy.all.retentionDuration, isNull);
      });

      test('day returns 24 hours', () {
        expect(MessageRetentionPolicy.day.retentionDuration, 
            equals(const Duration(hours: 24)));
      });

      test('week returns 7 days', () {
        expect(MessageRetentionPolicy.week.retentionDuration, 
            equals(const Duration(days: 7)));
      });

      test('month returns 30 days', () {
        expect(MessageRetentionPolicy.month.retentionDuration, 
            equals(const Duration(days: 30)));
      });
    });

    group('getCutoffTime', () {
      test('all returns null', () {
        expect(MessageRetentionPolicy.all.getCutoffTime(), isNull);
      });

      test('day returns time 24 hours ago', () {
        final now = DateTime(2024, 1, 15, 12, 0, 0);
        final cutoff = MessageRetentionPolicy.day.getCutoffTime(now);
        
        expect(cutoff, equals(DateTime(2024, 1, 14, 12, 0, 0)));
      });

      test('week returns time 7 days ago', () {
        final now = DateTime(2024, 1, 15, 12, 0, 0);
        final cutoff = MessageRetentionPolicy.week.getCutoffTime(now);
        
        expect(cutoff, equals(DateTime(2024, 1, 8, 12, 0, 0)));
      });

      test('month returns time 30 days ago', () {
        final now = DateTime(2024, 1, 31, 12, 0, 0);
        final cutoff = MessageRetentionPolicy.month.getCutoffTime(now);
        
        expect(cutoff, equals(DateTime(2024, 1, 1, 12, 0, 0)));
      });
    });

    group('displayName', () {
      test('all has correct display name', () {
        expect(MessageRetentionPolicy.all.displayName, equals('Хранить всегда'));
      });

      test('day has correct display name', () {
        expect(MessageRetentionPolicy.day.displayName, equals('Хранить 24 часа'));
      });

      test('week has correct display name', () {
        expect(MessageRetentionPolicy.week.displayName, equals('Хранить 7 дней'));
      });

      test('month has correct display name', () {
        expect(MessageRetentionPolicy.month.displayName, equals('Хранить 30 дней'));
      });
    });

    group('subtitle', () {
      test('all has correct subtitle', () {
        expect(MessageRetentionPolicy.all.subtitle, 
            equals('Сообщения не удаляются автоматически'));
      });

      test('day has correct subtitle', () {
        expect(MessageRetentionPolicy.day.subtitle, 
            equals('Сообщения старше суток удаляются'));
      });

      test('week has correct subtitle', () {
        expect(MessageRetentionPolicy.week.subtitle, 
            equals('Сообщения старше недели удаляются'));
      });

      test('month has correct subtitle', () {
        expect(MessageRetentionPolicy.month.subtitle, 
            equals('Сообщения старше месяца удаляются'));
      });
    });

    group('configValue serialization', () {
      test('configValue returns correct index', () {
        expect(MessageRetentionPolicy.all.configValue, equals(0));
        expect(MessageRetentionPolicy.day.configValue, equals(1));
        expect(MessageRetentionPolicy.week.configValue, equals(2));
        expect(MessageRetentionPolicy.month.configValue, equals(3));
      });

      test('fromConfigValue restores correct policy', () {
        expect(MessageRetentionPolicyExtension.fromConfigValue(0), 
            equals(MessageRetentionPolicy.all));
        expect(MessageRetentionPolicyExtension.fromConfigValue(1), 
            equals(MessageRetentionPolicy.day));
        expect(MessageRetentionPolicyExtension.fromConfigValue(2), 
            equals(MessageRetentionPolicy.week));
        expect(MessageRetentionPolicyExtension.fromConfigValue(3), 
            equals(MessageRetentionPolicy.month));
      });

      test('fromConfigValue returns all for null', () {
        expect(MessageRetentionPolicyExtension.fromConfigValue(null), 
            equals(MessageRetentionPolicy.all));
      });

      test('fromConfigValue returns all for invalid values', () {
        expect(MessageRetentionPolicyExtension.fromConfigValue(-1), 
            equals(MessageRetentionPolicy.all));
        expect(MessageRetentionPolicyExtension.fromConfigValue(100), 
            equals(MessageRetentionPolicy.all));
      });
    });

    group('roundtrip serialization', () {
      test('all policies survive roundtrip', () {
        for (final policy in MessageRetentionPolicy.values) {
          final serialized = policy.configValue;
          final deserialized = MessageRetentionPolicyExtension.fromConfigValue(serialized);
          expect(deserialized, equals(policy));
        }
      });
    });
  });
}
