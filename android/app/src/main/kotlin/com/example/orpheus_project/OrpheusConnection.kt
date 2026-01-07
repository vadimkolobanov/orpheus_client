package com.example.orpheus_project

import android.content.Context
import android.content.Intent
import android.telecom.Connection
import android.telecom.DisconnectCause
import android.util.Log

class OrpheusConnection(
    private val appContext: Context,
    private val model: OrpheusIncomingCallModel,
) : Connection() {
    private val tag = "OrpheusConnection"
    private val connectionKey: String = (model.callId ?: model.callerKey)

    init {
        // Self-managed VoIP call.
        setConnectionProperties(PROPERTY_SELF_MANAGED)
        setConnectionCapabilities(CAPABILITY_SUPPORT_HOLD or CAPABILITY_HOLD)

        // Best-effort caller display name.
        val display = model.callerName ?: model.callerKey.take(8)
        setCallerDisplayName(display, android.telecom.TelecomManager.PRESENTATION_ALLOWED)
    }

    override fun onAnswer() {
        Log.i(tag, "onAnswer (callId=${model.callId}, callerKey=${model.callerKey})")
        setActive()

        // Передаём действие в Flutter через pending_call.
        Log.i(tag, "Saving pending accepted call...")
        OrpheusCallStore.savePendingAcceptedCall(appContext, model)
        
        // Логируем что было сохранено
        val savedJson = appContext.getSharedPreferences("orpheus_calls", android.content.Context.MODE_PRIVATE)
            .getString("pending_accept_json", null)
        Log.i(tag, "Saved pending_accept_json (len=${savedJson?.length ?: 0})")
        
        // offer больше не нужен после accept — освобождаем.
        OrpheusCallStore.clearCachedOffer(appContext)
        OrpheusConnectionRegistry.remove(connectionKey)
        sendCloseIncomingUi()
        
        // КРИТИЧНО: очищаем active_call после Accept — звонок переходит под управление Flutter,
        // Telecom incoming flow завершён. Иначе следующие звонки будут блокироваться как "active_call_exists".
        OrpheusCallStore.clearActiveCall(appContext)
        Log.i(tag, "Active call cleared after accept")
        
        Log.i(tag, "Launching MainActivity for Telecom action...")
        OrpheusCallManager.launchMainActivityForTelecomAction(appContext)
        
        // ВАЖНО: завершаем Telecom connection — звонок теперь под управлением Flutter WebRTC.
        // Без этого Telecom будет держать connection активным и пытаться управлять им (hold/resume).
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
        Log.i(tag, "Telecom connection destroyed after accept")
    }

    override fun onReject() {
        Log.i(tag, "onReject (callId=${model.callId})")
        OrpheusCallStore.savePendingRejectedCall(appContext, model)
        OrpheusCallStore.clearCachedOffer(appContext)
        OrpheusConnectionRegistry.remove(connectionKey)
        sendCloseIncomingUi()
        // MVP: поднимем приложение, чтобы Flutter смог отправить call-rejected по WS/HTTP fallback.
        OrpheusCallManager.launchMainActivityForTelecomAction(appContext)

        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        OrpheusCallStore.clearActiveCall(appContext)
        destroy()
    }

    override fun onDisconnect() {
        Log.i(tag, "onDisconnect (callId=${model.callId})")
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        OrpheusCallStore.clearActiveCall(appContext)
        OrpheusConnectionRegistry.remove(connectionKey)
        sendCloseIncomingUi()
        destroy()
    }

    override fun onAbort() {
        Log.i(tag, "onAbort (callId=${model.callId})")
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        OrpheusCallStore.clearActiveCall(appContext)
        OrpheusConnectionRegistry.remove(connectionKey)
        sendCloseIncomingUi()
        destroy()
    }

    override fun onShowIncomingCallUi() {
        // Android для self-managed calls ожидает, что мы сами покажем UI входящего.
        val display = model.callerName ?: model.callerKey.take(8)
        val intent = Intent(appContext, OrpheusIncomingCallActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(OrpheusIncomingCallActivity.EXTRA_CONNECTION_KEY, connectionKey)
            putExtra(OrpheusIncomingCallActivity.EXTRA_CALLER_NAME, display)
        }
        try {
            appContext.startActivity(intent)
        } catch (e: Exception) {
            Log.e(tag, "Failed to start OrpheusIncomingCallActivity", e)
        }
    }

    private fun sendCloseIncomingUi() {
        try {
            val i = Intent(OrpheusIncomingCallActivity.ACTION_CLOSE).apply {
                setPackage(appContext.packageName)
                putExtra(OrpheusIncomingCallActivity.EXTRA_CLOSE_KEY, connectionKey)
            }
            appContext.sendBroadcast(i)
        } catch (_: Exception) {
        }
    }
}


