package com.example.orpheus_project

import android.os.Bundle

/**
 * Модель data-only push для входящего звонка.
 *
 * Backward-compatible: часть полей опциональна, чтобы не ломать прод.
 */
data class OrpheusIncomingCallModel(
    val callId: String?,
    val callerKey: String,
    val callerName: String?,
    val serverTsMs: Long?,
    val nativeTelecom: Boolean,
) {
    companion object {
        const val TYPE_INCOMING_CALL = "incoming_call"
        const val TYPE_CALL_LEGACY = "call"

        fun fromFcmData(data: Map<String, String>): OrpheusIncomingCallModel? {
            val type = data["type"] ?: return null
            if (type != TYPE_INCOMING_CALL && type != TYPE_CALL_LEGACY) return null

            val callerKey = data["caller_key"] ?: return null
            val callId = data["call_id"]?.trim()?.takeIf { it.isNotEmpty() }
            val callerName = data["caller_name"]
            val serverTsMs = data["server_ts_ms"]?.toLongOrNull()
            val nativeTelecom = (data["native_telecom"] == "1" || data["native_telecom"] == "true")

            return OrpheusIncomingCallModel(
                callId = callId,
                callerKey = callerKey,
                callerName = callerName,
                serverTsMs = serverTsMs,
                nativeTelecom = nativeTelecom,
            )
        }
    }

    fun toTelecomExtras(): Bundle {
        val b = Bundle()
        b.putString(OrpheusCallStore.EXTRA_CALL_ID, callId)
        b.putString(OrpheusCallStore.EXTRA_CALLER_KEY, callerKey)
        b.putString(OrpheusCallStore.EXTRA_CALLER_NAME, callerName)
        if (serverTsMs != null) b.putLong(OrpheusCallStore.EXTRA_SERVER_TS_MS, serverTsMs)
        return b
    }
}


