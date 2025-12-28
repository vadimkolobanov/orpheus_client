import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AndroidManifest задаёт default_notification_icon (не ic_launcher), чтобы не было "белого квадрата"', () async {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    expect(await manifest.exists(), isTrue, reason: 'AndroidManifest.xml должен существовать');

    final xml = await manifest.readAsString();
    expect(xml, contains('com.google.firebase.messaging.default_notification_icon'));
    expect(xml, contains('@drawable/ic_stat_orpheus'));
  });

  test('Иконка уведомления (drawable) существует', () async {
    final icon = File('android/app/src/main/res/drawable/ic_stat_orpheus.xml');
    expect(await icon.exists(), isTrue);
  });
}




