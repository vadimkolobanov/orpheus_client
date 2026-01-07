import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/notification_service.dart';

void main() {
  test('native_telecom incoming_call does not show local notification on Android', () {
    final shouldShow = NotificationService.shouldShowLocalNotification(
      hasNotificationPayload: false,
      data: {
        'type': 'incoming_call',
        'native_telecom': '1',
        'caller_key': 'abc',
      },
      isAndroid: true,
    );
    expect(shouldShow, isFalse);
  });

  test('non-telecom incoming_call still shows local notification (data-only)', () {
    final shouldShow = NotificationService.shouldShowLocalNotification(
      hasNotificationPayload: false,
      data: {
        'type': 'incoming_call',
        'caller_key': 'abc',
      },
      isAndroid: true,
    );
    expect(shouldShow, isTrue);
  });
}



