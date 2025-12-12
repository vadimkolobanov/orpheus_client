package com.example.orpheus_project

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Ресивер для автозапуска приложения после перезагрузки устройства.
 * Это критично для Xiaomi/Vivo/Huawei, которые агрессивно убивают приложения.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON" ||
            intent.action == "com.htc.intent.action.QUICKBOOT_POWERON") {
            
            Log.d("BootReceiver", "Device booted, starting Orpheus...")
            
            // Запускаем MainActivity в фоне (она инициализирует Firebase и WebSocket)
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                // Специальный флаг чтобы Activity знала, что запущена при загрузке
                putExtra("from_boot", true)
            }
            
            try {
                context.startActivity(launchIntent)
                Log.d("BootReceiver", "Orpheus started successfully after boot")
            } catch (e: Exception) {
                Log.e("BootReceiver", "Failed to start Orpheus: ${e.message}")
            }
        }
    }
}

