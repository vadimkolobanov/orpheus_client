import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orpheus_project/services/device_settings_service.dart';

void main() {
  group('DeviceSettingsService (контракты)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      DeviceSettingsService.debugResetForTesting();
    });

    tearDown(() {
      DeviceSettingsService.debugResetForTesting();
    });

    test('setup dialog dismissed: roundtrip через SharedPreferences', () async {
      expect(await DeviceSettingsService.isSetupDialogDismissed(), isFalse);

      await DeviceSettingsService.setSetupDialogDismissed(true);
      expect(await DeviceSettingsService.isSetupDialogDismissed(), isTrue);

      await DeviceSettingsService.setSetupDialogDismissed(false);
      expect(await DeviceSettingsService.isSetupDialogDismissed(), isFalse);
    });

    test('getManufacturerDisplayName: корректный display для известных OEM', () {
      expect(DeviceSettingsService.getManufacturerDisplayName('xiaomi'), equals('Xiaomi/MIUI'));
      expect(DeviceSettingsService.getManufacturerDisplayName('redmi'), equals('Xiaomi/MIUI'));
      expect(DeviceSettingsService.getManufacturerDisplayName('poco'), equals('Xiaomi/MIUI'));
      expect(DeviceSettingsService.getManufacturerDisplayName('vivo'), equals('Vivo'));
      expect(DeviceSettingsService.getManufacturerDisplayName('oppo'), equals('OPPO/Realme'));
      expect(DeviceSettingsService.getManufacturerDisplayName('realme'), equals('OPPO/Realme'));
      expect(DeviceSettingsService.getManufacturerDisplayName('huawei'), equals('Huawei/Honor'));
      expect(DeviceSettingsService.getManufacturerDisplayName('honor'), equals('Huawei/Honor'));
      expect(DeviceSettingsService.getManufacturerDisplayName('samsung'), equals('Samsung'));
      expect(DeviceSettingsService.getManufacturerDisplayName('oneplus'), equals('OnePlus'));
      expect(DeviceSettingsService.getManufacturerDisplayName('other'), equals('other'));
    });

    test('needsManualSetup: true для китайского OEM, даже если batteryOptimizationDisabled=true', () async {
      DeviceSettingsService.debugForceAndroid = true;
      DeviceSettingsService.debugManufacturerOverride = 'xiaomi';
      DeviceSettingsService.debugBatteryOptimizationDisabledOverride = true;

      expect(await DeviceSettingsService.needsManualSetup(), isTrue);
    });

    test('needsManualSetup: true если batteryOptimizationDisabled=false (то есть оптимизация включена)', () async {
      DeviceSettingsService.debugForceAndroid = true;
      DeviceSettingsService.debugManufacturerOverride = 'other';
      DeviceSettingsService.debugBatteryOptimizationDisabledOverride = false;

      expect(await DeviceSettingsService.needsManualSetup(), isTrue);
    });

    test('needsManualSetup: false для non-android окружения по умолчанию', () async {
      // В тестовой среде на Windows Platform.isAndroid=false, метод должен быть safe-default.
      expect(await DeviceSettingsService.needsManualSetup(), isFalse);
    });
  });
}






