import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/call_native_ui_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.orpheus_project/call');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        // просто подтверждаем, что вызов ушёл в канал
        return true;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('enableCallMode/disableCallMode: вызывают MethodChannel best-effort', () async {
    await CallNativeUiService.enableCallMode();
    await CallNativeUiService.disableCallMode();
  });
}




