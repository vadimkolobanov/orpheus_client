package com.example.orpheus_project

import android.util.Log
import com.google.firebase.messaging.RemoteMessage

/**
 * ВАЖНО:
 * Мы наследуемся от flutterfire `FlutterFirebaseMessagingService`, чтобы не ломать existing FCM flow.
 *
 * Для звонков с `native_telecom=1`:
 * - поднимаем Telecom incoming UI (best-effort)
 * - НЕ вызываем super, чтобы Dart background handler не показал локальную call-нотификацию (анти-дубли).
 *
 * Для остальных сообщений: делегируем в super.
 */
class OrpheusFirebaseMessagingService :
    io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService() {

    private val tag = "OrpheusFCM"

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data

        val model = OrpheusIncomingCallModel.fromFcmData(data)
        if (model != null && model.nativeTelecom) {
            Log.i(tag, "Telecom-call push received (callId=${model.callId})")
            try {
                val ok = OrpheusCallManager.tryShowIncomingCall(applicationContext, model)
                if (ok) {
                    // Считаем сообщение обработанным, в Dart не пропускаем.
                    return
                }
            } catch (e: Exception) {
                Log.e(tag, "Telecom handling error", e)
            }
            // Если Telecom не смог — даём Dart обработчику показать fallback (локальную нотификацию).
        }

        super.onMessageReceived(message)
    }
}


