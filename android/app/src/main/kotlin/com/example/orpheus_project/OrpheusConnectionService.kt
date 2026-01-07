package com.example.orpheus_project

import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.util.Log

class OrpheusConnectionService : ConnectionService() {
    private val tag = "OrpheusConnService"

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest
    ): Connection {
        val extras = request.extras
        val callId = extras?.getString(OrpheusCallStore.EXTRA_CALL_ID)
        val callerKey = extras?.getString(OrpheusCallStore.EXTRA_CALLER_KEY) ?: "unknown"
        val callerName = extras?.getString(OrpheusCallStore.EXTRA_CALLER_NAME)
        val serverTsMs = extras?.getLong(OrpheusCallStore.EXTRA_SERVER_TS_MS, 0L)?.takeIf { it > 0L }

        val model = OrpheusIncomingCallModel(
            callId = callId,
            callerKey = callerKey,
            callerName = callerName,
            serverTsMs = serverTsMs,
            nativeTelecom = true,
        )

        Log.i(tag, "Incoming connection created (callId=$callId caller=$callerKey)")

        val conn = OrpheusConnection(applicationContext, model)
        // Best-effort address for system UI.
        try {
            conn.setAddress(request.address, android.telecom.TelecomManager.PRESENTATION_ALLOWED)
        } catch (_: Exception) {
        }
        conn.setInitializing()
        conn.setRinging()

        // Регистрируем connection для IncomingCallActivity.
        val key = (model.callId ?: model.callerKey)
        OrpheusConnectionRegistry.register(key, conn)

        return conn
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        Log.e(tag, "Incoming connection failed")
        // На всякий случай очищаем active-call (иначе могут быть ложные active_call_exists).
        try {
            OrpheusCallStore.clearActiveCall(applicationContext)
        } catch (_: Exception) {}
        super.onCreateIncomingConnectionFailed(connectionManagerPhoneAccount, request)
    }

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: android.telecom.PhoneAccountHandle?,
        request: ConnectionRequest
    ): Connection {
        // Outgoing через Telecom пока не делаем (Flutter уже умеет).
        return Connection.createFailedConnection(DisconnectCause(DisconnectCause.ERROR))
    }
}


