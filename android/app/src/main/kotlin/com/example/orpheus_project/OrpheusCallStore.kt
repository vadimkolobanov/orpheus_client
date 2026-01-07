package com.example.orpheus_project

import android.content.Context
import android.content.SharedPreferences

/**
 * SharedPreferences хранилище для мостов Kotlin ↔ Flutter по действиям Telecom.
 *
 * Важно: отдельный pref-файл, чтобы не зависеть от реализации FlutterSharedPreferences.
 */
object OrpheusCallStore {
    private const val PREFS = "orpheus_calls"

    // Extras keys (Telecom/Intent)
    const val EXTRA_CALL_ID = "call_id"
    const val EXTRA_CALLER_KEY = "caller_key"
    const val EXTRA_CALLER_NAME = "caller_name"
    const val EXTRA_SERVER_TS_MS = "server_ts_ms"

    // Pref keys
    private const val KEY_PENDING_ACCEPT = "pending_accept_json"
    private const val KEY_PENDING_REJECT = "pending_reject_json"
    private const val KEY_LAST_CALL_ID = "last_call_id"
    private const val KEY_LAST_CALL_TS_MS = "last_call_ts_ms"
    private const val KEY_ACTIVE_CALL_ID = "active_call_id"
    private const val KEY_ACTIVE_CALL_SET_AT_MS = "active_call_set_at_ms"
    private const val KEY_CACHED_CALLER_KEY = "cached_caller_key"
    private const val KEY_CACHED_CALL_ID = "cached_call_id"
    private const val KEY_CACHED_SERVER_TS_MS = "cached_server_ts_ms"
    private const val KEY_CACHED_OFFER_JSON = "cached_offer_json"
    private const val KEY_PHONE_ACCOUNT_REGISTERED = "phone_account_registered"

    // Если приложение было убито/крашнулось, активный вызов может “залипнуть”.
    // Считаем его протухшим через 2 минуты.
    private const val ACTIVE_CALL_STALE_MS: Long = 2 * 60_000L

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun markActiveCall(context: Context, callId: String?) {
        prefs(context).edit()
            .putString(KEY_ACTIVE_CALL_ID, callId)
            .putLong(KEY_ACTIVE_CALL_SET_AT_MS, System.currentTimeMillis())
            .apply()
    }

    fun clearActiveCall(context: Context) {
        prefs(context).edit()
            .remove(KEY_ACTIVE_CALL_ID)
            .remove(KEY_ACTIVE_CALL_SET_AT_MS)
            .apply()
    }

    fun getActiveCallId(context: Context): String? {
        val p = prefs(context)
        val id = p.getString(KEY_ACTIVE_CALL_ID, null) ?: return null
        val setAt = p.getLong(KEY_ACTIVE_CALL_SET_AT_MS, 0L)
        if (setAt == 0L) return id
        val age = System.currentTimeMillis() - setAt
        if (age > ACTIVE_CALL_STALE_MS) {
            clearActiveCall(context)
            return null
        }
        return id
    }

    fun savePendingAcceptedCall(context: Context, model: OrpheusIncomingCallModel) {
        val offerJson = getCachedOfferJson(context, model.callId, model.callerKey)
        val json = buildJson(
            callId = model.callId,
            callerKey = model.callerKey,
            callerName = model.callerName,
            serverTsMs = model.serverTsMs,
            offerJson = offerJson,
            action = "accept",
        )
        prefs(context).edit().putString(KEY_PENDING_ACCEPT, json).apply()
    }

    fun savePendingRejectedCall(context: Context, model: OrpheusIncomingCallModel) {
        val json = buildJson(
            callId = model.callId,
            callerKey = model.callerKey,
            callerName = model.callerName,
            serverTsMs = model.serverTsMs,
            offerJson = null,
            action = "reject",
        )
        prefs(context).edit().putString(KEY_PENDING_REJECT, json).apply()
    }

    fun getAndClearPendingAcceptedCall(context: Context): String? {
        val p = prefs(context)
        val v = p.getString(KEY_PENDING_ACCEPT, null)
        if (v != null) p.edit().remove(KEY_PENDING_ACCEPT).apply()
        return v
    }

    fun getAndClearPendingRejectedCall(context: Context): String? {
        val p = prefs(context)
        val v = p.getString(KEY_PENDING_REJECT, null)
        if (v != null) p.edit().remove(KEY_PENDING_REJECT).apply()
        return v
    }

    fun getLastCallId(context: Context): String? = prefs(context).getString(KEY_LAST_CALL_ID, null)
    fun getLastCallTsMs(context: Context): Long = prefs(context).getLong(KEY_LAST_CALL_TS_MS, 0L)

    fun setLastCall(context: Context, callId: String?, serverTsMs: Long?) {
        val editor = prefs(context).edit()
        if (callId != null) editor.putString(KEY_LAST_CALL_ID, callId) else editor.remove(KEY_LAST_CALL_ID)
        if (serverTsMs != null) editor.putLong(KEY_LAST_CALL_TS_MS, serverTsMs) else editor.remove(KEY_LAST_CALL_TS_MS)
        editor.apply()
    }

    private fun escapeJson(s: String): String =
        s.replace("\\", "\\\\").replace("\"", "\\\"")

    private fun buildJson(
        callId: String?,
        callerKey: String,
        callerName: String?,
        serverTsMs: Long?,
        offerJson: String?,
        action: String,
    ): String {
        // Минимальный JSON без дополнительных зависимостей (Gson/Moshi не добавляем).
        val parts = mutableListOf<String>()
        parts += "\"action\":\"${escapeJson(action)}\""
        parts += "\"caller_key\":\"${escapeJson(callerKey)}\""
        if (callId != null) parts += "\"call_id\":\"${escapeJson(callId)}\""
        if (callerName != null) parts += "\"caller_name\":\"${escapeJson(callerName)}\""
        if (serverTsMs != null) parts += "\"server_ts_ms\":$serverTsMs"
        if (offerJson != null) parts += "\"offer_data\":\"${escapeJson(offerJson)}\""
        parts += "\"stored_ts_ms\":${System.currentTimeMillis()}"
        return "{${parts.joinToString(",")}}"
    }

    fun cacheIncomingOffer(
        context: Context,
        callerKey: String,
        callId: String?,
        serverTsMs: Long?,
        offerJson: String,
    ) {
        prefs(context).edit()
            .putString(KEY_CACHED_CALLER_KEY, callerKey)
            .putString(KEY_CACHED_CALL_ID, callId)
            .putLong(KEY_CACHED_SERVER_TS_MS, serverTsMs ?: 0L)
            .putString(KEY_CACHED_OFFER_JSON, offerJson)
            .apply()
    }

    private fun getCachedOfferJson(context: Context, callId: String?, callerKey: String): String? {
        val p = prefs(context)
        val cachedCaller = p.getString(KEY_CACHED_CALLER_KEY, null) ?: return null
        if (cachedCaller != callerKey) return null
        val cachedCallId = p.getString(KEY_CACHED_CALL_ID, null)
        if (callId != null && cachedCallId != null && cachedCallId != callId) return null
        return p.getString(KEY_CACHED_OFFER_JSON, null)
    }

    fun clearCachedOffer(context: Context) {
        prefs(context).edit()
            .remove(KEY_CACHED_CALLER_KEY)
            .remove(KEY_CACHED_CALL_ID)
            .remove(KEY_CACHED_SERVER_TS_MS)
            .remove(KEY_CACHED_OFFER_JSON)
            .apply()
    }

    fun isPhoneAccountRegistered(context: Context): Boolean =
        prefs(context).getBoolean(KEY_PHONE_ACCOUNT_REGISTERED, false)

    fun setPhoneAccountRegistered(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(KEY_PHONE_ACCOUNT_REGISTERED, value).apply()
    }
}


