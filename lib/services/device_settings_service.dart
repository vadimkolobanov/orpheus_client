import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для работы с настройками устройства.
/// Особенно важен для китайских производителей (Xiaomi, Vivo, Oppo, Huawei),
/// которые агрессивно управляют батареей и убивают фоновые приложения.
class DeviceSettingsService {
  static const _batteryChannel = MethodChannel('com.example.orpheus_project/battery');
  static const _settingsChannel = MethodChannel('com.example.orpheus_project/settings');
  
  // Ключ для хранения настройки "не показывать диалог"
  static const String _setupDialogDismissedKey = 'setup_dialog_dismissed';

  // ===== Test hooks =====
  @visibleForTesting
  static bool? debugForceAndroid;

  @visibleForTesting
  static String? debugManufacturerOverride;

  @visibleForTesting
  static bool? debugBatteryOptimizationDisabledOverride;

  @visibleForTesting
  static void debugResetForTesting() {
    debugForceAndroid = null;
    debugManufacturerOverride = null;
    debugBatteryOptimizationDisabledOverride = null;
  }
  
  /// Проверить, был ли диалог скрыт пользователем
  static Future<bool> isSetupDialogDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_setupDialogDismissedKey) ?? false;
  }
  
  /// Сохранить настройку "не показывать диалог"
  static Future<void> setSetupDialogDismissed(bool dismissed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupDialogDismissedKey, dismissed);
  }

  /// Получить производителя устройства
  static Future<String> getDeviceManufacturer() async {
    final forced = debugForceAndroid;
    if (forced != true && !Platform.isAndroid) return 'other';

    final override = debugManufacturerOverride;
    if (override != null) return override.toLowerCase();
    
    try {
      final manufacturer = await _settingsChannel.invokeMethod<String>('getDeviceManufacturer');
      return manufacturer?.toLowerCase() ?? 'other';
    } catch (e) {
      return 'other';
    }
  }

  /// Проверить, отключена ли оптимизация батареи для приложения
  static Future<bool> isBatteryOptimizationDisabled() async {
    final forced = debugForceAndroid;
    if (forced != true && !Platform.isAndroid) return true;

    final override = debugBatteryOptimizationDisabledOverride;
    if (override != null) return override;
    
    try {
      return await _batteryChannel.invokeMethod<bool>('isBatteryOptimizationDisabled') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Запросить отключение оптимизации батареи
  static Future<void> requestBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _batteryChannel.invokeMethod('requestBatteryOptimization');
    } catch (e) {
      print("DeviceSettings: Battery optimization request error: $e");
    }
  }

  /// Открыть настройки батареи
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _batteryChannel.invokeMethod('openBatterySettings');
    } catch (e) {
      print("DeviceSettings: Open battery settings error: $e");
    }
  }

  /// Открыть настройки приложения
  static Future<void> openAppSettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _settingsChannel.invokeMethod('openAppSettings');
    } catch (e) {
      print("DeviceSettings: Open app settings error: $e");
    }
  }

  /// Открыть настройки уведомлений
  static Future<void> openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _settingsChannel.invokeMethod('openNotificationSettings');
    } catch (e) {
      print("DeviceSettings: Open notification settings error: $e");
    }
  }

  /// Открыть настройки автозапуска (для китайских OEM)
  static Future<void> openAutoStartSettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _settingsChannel.invokeMethod('openAutoStartSettings');
    } catch (e) {
      print("DeviceSettings: Open autostart settings error: $e");
    }
  }

  /// Проверить, разрешено ли рисовать поверх других приложений
  static Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return true;
    
    try {
      return await _settingsChannel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Запросить разрешение на overlay
  static Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    
    try {
      await _settingsChannel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      print("DeviceSettings: Overlay permission request error: $e");
    }
  }

  /// Проверить, нужно ли показывать инструкции по настройке
  /// (для китайских устройств это критично)
  static Future<bool> needsManualSetup() async {
    final manufacturer = await getDeviceManufacturer();
    final batteryOptimized = !(await isBatteryOptimizationDisabled());
    
    // Для китайских OEM всегда нужна ручная настройка
    final isChineseOem = ['xiaomi', 'redmi', 'poco', 'vivo', 'oppo', 'realme', 'huawei', 'honor', 'oneplus']
        .any((brand) => manufacturer.contains(brand));
    
    return isChineseOem || batteryOptimized;
  }

  /// Получить человекочитаемое название производителя
  static String getManufacturerDisplayName(String manufacturer) {
    if (manufacturer.contains('xiaomi') || manufacturer.contains('redmi') || manufacturer.contains('poco')) {
      return 'Xiaomi/MIUI';
    } else if (manufacturer.contains('vivo')) {
      return 'Vivo';
    } else if (manufacturer.contains('oppo') || manufacturer.contains('realme')) {
      return 'OPPO/Realme';
    } else if (manufacturer.contains('huawei') || manufacturer.contains('honor')) {
      return 'Huawei/Honor';
    } else if (manufacturer.contains('samsung')) {
      return 'Samsung';
    } else if (manufacturer.contains('oneplus')) {
      return 'OnePlus';
    }
    return manufacturer;
  }

  /// Показать диалог с инструкциями по настройке
  static Future<void> showSetupDialog(BuildContext context) async {
    final manufacturer = await getDeviceManufacturer();
    final displayName = getManufacturerDisplayName(manufacturer);
    final batteryDisabled = await isBatteryOptimizationDisabled();

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              batteryDisabled ? Icons.check_circle : Icons.warning_amber_rounded,
              color: batteryDisabled ? const Color(0xFF6AD394) : Colors.orange,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Настройка уведомлений',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Устройство: $displayName',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                'Для стабильной работы уведомлений о звонках и сообщениях, выполните следующие шаги:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              
              // Шаг 1: Батарея
              _buildSetupStep(
                number: 1,
                title: 'Отключить оптимизацию батареи',
                description: batteryDisabled 
                    ? 'Уже отключено ✓'
                    : 'Разрешите Orpheus работать в фоне без ограничений',
                isComplete: batteryDisabled,
                onTap: batteryDisabled ? null : () async {
                  Navigator.pop(context);
                  await requestBatteryOptimization();
                },
              ),
              
              // Шаг 2: Автозапуск (для китайских OEM)
              if (_isChineseOem(manufacturer)) ...[
                const SizedBox(height: 12),
                _buildSetupStep(
                  number: 2,
                  title: 'Включить автозапуск',
                  description: 'Разрешите приложению запускаться автоматически',
                  onTap: () async {
                    Navigator.pop(context);
                    await openAutoStartSettings();
                  },
                ),
              ],
              
              // Шаг 3: Уведомления
              const SizedBox(height: 12),
              _buildSetupStep(
                number: _isChineseOem(manufacturer) ? 3 : 2,
                title: 'Проверить настройки уведомлений',
                description: 'Убедитесь, что уведомления о звонках включены',
                onTap: () async {
                  Navigator.pop(context);
                  await openNotificationSettings();
                },
              ),
              
              // Дополнительные инструкции для Xiaomi
              if (manufacturer.contains('xiaomi') || manufacturer.contains('redmi') || manufacturer.contains('poco')) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠️ Для Xiaomi/MIUI также:',
                        style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Настройки → Приложения → Orpheus → Экономия батареи → "Без ограничений"\n'
                        '• Безопасность → Autostart → включить Orpheus\n'
                        '• Настройки → Приложения → Orpheus → Уведомления → включить все',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
              
              // Для Vivo
              if (manufacturer.contains('vivo')) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠️ Для Vivo также:',
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• i Manager → Диспетчер приложений → Orpheus → Высокое энергопотребление\n'
                        '• Настройки → Приложения → Orpheus → Autostart → включить',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await setSetupDialogDismissed(true);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Не показывать', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Позже', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6AD394),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  static bool _isChineseOem(String manufacturer) {
    return ['xiaomi', 'redmi', 'poco', 'vivo', 'oppo', 'realme', 'huawei', 'honor', 'oneplus']
        .any((brand) => manufacturer.contains(brand));
  }

  static Widget _buildSetupStep({
    required int number,
    required String title,
    required String description,
    bool isComplete = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isComplete 
              ? const Color(0xFF6AD394).withOpacity(0.1)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isComplete 
                ? const Color(0xFF6AD394).withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isComplete 
                    ? const Color(0xFF6AD394)
                    : Colors.white.withOpacity(0.2),
              ),
              child: Center(
                child: isComplete
                    ? const Icon(Icons.check, size: 16, color: Colors.black)
                    : Text(
                        '$number',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isComplete ? const Color(0xFF6AD394) : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      color: isComplete ? const Color(0xFF6AD394).withOpacity(0.7) : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey.withOpacity(0.5),
              ),
          ],
        ),
      ),
    );
  }
}

