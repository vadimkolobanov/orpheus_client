package com.example.orpheus_project

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.util.Log
import android.provider.Settings
import android.content.Context
import android.os.Bundle
import android.app.NotificationManager
import android.app.KeyguardManager
import android.os.Build.VERSION_CODES
class MainActivity: FlutterFragmentActivity() {
    private val TAG = "MainActivity"
    private val BATTERY_CHANNEL = "com.example.orpheus_project/battery"
    private val SETTINGS_CHANNEL = "com.example.orpheus_project/settings"
    private val CALL_CHANNEL = "com.example.orpheus_project/call"

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.i(TAG, "onCreate: intent=${intent?.action}, from_telecom=${intent?.getBooleanExtra("from_telecom", false)}")
        super.onCreate(savedInstanceState)
        // Флаги showWhenLocked и turnScreenOn теперь применяются только во время звонков
        // через MethodChannel, чтобы не мешать нормальной работе приложения

        // Telecom: регистрируем PhoneAccount best-effort (без падений).
        try {
            OrpheusCallManager.ensurePhoneAccountRegistered(applicationContext)
        } catch (_: Exception) {
            // best-effort
        }
        
        // Если запущены из Telecom — включаем режим звонка (show on lockscreen)
        if (intent?.getBooleanExtra("from_telecom", false) == true) {
            Log.i(TAG, "Enabling call mode from Telecom launch")
            enableCallMode()
        }
    }
    
    override fun onNewIntent(intent: Intent) {
        Log.i(TAG, "onNewIntent: action=${intent.action}, from_telecom=${intent.getBooleanExtra("from_telecom", false)}")
        super.onNewIntent(intent)
        setIntent(intent)
        
        // Если запущены из Telecom — включаем режим звонка
        if (intent.getBooleanExtra("from_telecom", false)) {
            Log.i(TAG, "Enabling call mode from Telecom (onNewIntent)")
            enableCallMode()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Защита от скриншотов
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )

        // Канал для управления батареей
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestBatteryOptimization" -> {
                    requestIgnoreBatteryOptimization()
                    result.success(true)
                }
                "isBatteryOptimizationDisabled" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "openBatterySettings" -> {
                    openBatterySettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Канал для настроек устройства
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(true)
                }
                "canDrawOverlays" -> {
                    result.success(canDrawOverlays())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(true)
                }
                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER.lowercase())
                }
                "openAutoStartSettings" -> {
                    openAutoStartSettings()
                    result.success(true)
                }
                "openFullScreenIntentSettings" -> {
                    openFullScreenIntentSettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Канал для управления поведением во время звонков
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableCallMode" -> {
                    enableCallMode()
                    result.success(true)
                }
                "disableCallMode" -> {
                    disableCallMode()
                    result.success(true)
                }
                // Telecom bridge: Flutter забирает pending call/reject после действий в системном UI.
                "getAndClearPendingCall" -> {
                    val pending = OrpheusCallStore.getAndClearPendingAcceptedCall(applicationContext)
                    Log.i("MainActivity", "getAndClearPendingCall: ${if (pending != null) "found (len=${pending.length})" else "null"}")
                    result.success(pending)
                }
                "getAndClearPendingReject" -> {
                    result.success(OrpheusCallStore.getAndClearPendingRejectedCall(applicationContext))
                }
                // WS background -> Telecom incoming (как Telegram)
                "showTelecomIncomingCall" -> {
                    val args = call.arguments as? Map<*, *>
                    val callerKey = args?.get("caller_key")?.toString()?.trim().orEmpty()
                    if (callerKey.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val callerName = args?.get("caller_name")?.toString()
                    val callId = args?.get("call_id")?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                    val serverTsMs = (args?.get("server_ts_ms") as? Number)?.toLong()
                        ?: args?.get("server_ts_ms")?.toString()?.toLongOrNull()
                    val offerJson = args?.get("offer_json")?.toString()

                    if (!offerJson.isNullOrBlank()) {
                        OrpheusCallStore.cacheIncomingOffer(
                            applicationContext,
                            callerKey = callerKey,
                            callId = callId,
                            serverTsMs = serverTsMs,
                            offerJson = offerJson,
                        )
                    }

                    val model = OrpheusIncomingCallModel(
                        callId = callId,
                        callerKey = callerKey,
                        callerName = callerName,
                        serverTsMs = serverTsMs,
                        nativeTelecom = true,
                    )
                    val ok = OrpheusCallManager.tryShowIncomingCall(applicationContext, model)
                    result.success(ok)
                }
                "clearActiveTelecomCall" -> {
                    OrpheusCallStore.clearActiveCall(applicationContext)
                    OrpheusCallStore.clearCachedOffer(applicationContext)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun enableCallMode() {
        // Включаем показ поверх блокировки и включение экрана только во время звонка
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }

    private fun disableCallMode() {
        // Отключаем показ поверх блокировки после завершения звонка
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }

    private fun requestIgnoreBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val packageName = packageName
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent().apply {
                        action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    // Fallback: открыть общие настройки батареи
                    openBatterySettings()
                }
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isIgnoringBatteryOptimizations(packageName)
        }
        return true
    }

    private fun openBatterySettings() {
        try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback
            val intent = Intent(Settings.ACTION_SETTINGS)
            startActivity(intent)
        }
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    private fun openNotificationSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
            startActivity(intent)
        } else {
            openAppSettings()
        }
    }

    private fun openFullScreenIntentSettings() {
        // Android 14+ (API 34): Special app access → Full screen intents.
        // Без этого "большой экран" по full-screen intent может не показываться.
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } else {
                // Fallback: хотя бы открыть настройки уведомлений приложения
                openNotificationSettings()
            }
        } catch (e: Exception) {
            openNotificationSettings()
        }
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }

    private fun openAutoStartSettings() {
        // Попытка открыть настройки автозапуска для разных производителей
        val manufacturer = Build.MANUFACTURER.lowercase()
        
        try {
            val intent = when {
                manufacturer.contains("xiaomi") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.miui.securitycenter",
                            "com.miui.permcenter.autostart.AutoStartManagementActivity"
                        )
                    }
                }
                manufacturer.contains("oppo") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.coloros.safecenter",
                            "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                        )
                    }
                }
                manufacturer.contains("vivo") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.vivo.permissionmanager",
                            "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                        )
                    }
                }
                manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.huawei.systemmanager",
                            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                        )
                    }
                }
                manufacturer.contains("samsung") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.samsung.android.lool",
                            "com.samsung.android.sm.ui.battery.BatteryActivity"
                        )
                    }
                }
                else -> {
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                }
            }
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback: открыть настройки приложения
            openAppSettings()
        }
    }
}
