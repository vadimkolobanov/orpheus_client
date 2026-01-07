package com.example.orpheus_project

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log

/**
 * Управление Telecom/PhoneAccount и входящими вызовами.
 *
 * Важно: best-effort. Если Telecom недоступен/заблокирован — вызывающий код должен сделать fallback (нотификация).
 */
object OrpheusCallManager {
    private const val TAG = "OrpheusCallManager"
    private const val PHONE_ACCOUNT_ID = "orpheus_voip"

    private fun telecomManager(context: Context): TelecomManager? =
        context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager

    private fun phoneAccountHandle(context: Context): PhoneAccountHandle =
        PhoneAccountHandle(
            ComponentName(context, OrpheusConnectionService::class.java),
            PHONE_ACCOUNT_ID,
        )

    fun ensurePhoneAccountRegistered(context: Context) {
        val tm = telecomManager(context) ?: return
        val handle = phoneAccountHandle(context)

        // ВАЖНО:
        // TelecomManager.getPhoneAccount() на некоторых устройствах/версиях Android может требовать
        // READ_PHONE_NUMBERS, что нам не нужно и добавлять не хотим.
        // Поэтому не дергаем getPhoneAccount вообще — регистрируем "once" через SharedPreferences-флаг.
        if (OrpheusCallStore.isPhoneAccountRegistered(context)) return

        try {
            val account = PhoneAccount.builder(handle, "Orpheus")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .setSupportedUriSchemes(listOf(PhoneAccount.SCHEME_SIP))
                .build()

            tm.registerPhoneAccount(account)
            OrpheusCallStore.setPhoneAccountRegistered(context, true)
            Log.i(TAG, "PhoneAccount registered")
        } catch (e: SecurityException) {
            Log.e(TAG, "registerPhoneAccount security error", e)
        } catch (e: Exception) {
            Log.e(TAG, "registerPhoneAccount failed", e)
        }
    }

    /**
     * Пытаемся показать системный входящий UI (Telecom).
     * @return true, если мы реально инициировали Telecom incoming flow.
     */
    fun tryShowIncomingCall(context: Context, model: OrpheusIncomingCallModel): Boolean {
        val tm = telecomManager(context) ?: return false

        // Дедуп/TTL + защита от второго активного вызова.
        val hasActive = OrpheusCallStore.getActiveCallId(context) != null
        val decision = OrpheusCallDeduplicator.decide(
            nowMs = System.currentTimeMillis(),
            serverTsMs = model.serverTsMs,
            callId = model.callId,
            lastCallId = OrpheusCallStore.getLastCallId(context),
            lastCallServerTsMs = OrpheusCallStore.getLastCallTsMs(context),
            hasActiveCall = hasActive,
        )
        if (!decision.shouldProcess) {
            Log.i(TAG, "Incoming call ignored: ${decision.reason}")
            // ВАЖНО: если Telecom-вызов уже активен или это явный дубль, считаем событие "обработанным",
            // чтобы Flutter не показывал fallback-нотификацию поверх системного UI.
            return decision.reason == "active_call_exists" ||
                decision.reason == "duplicate_call_id" ||
                decision.reason == "duplicate_ts_bucket"
        }

        // Регистрируем account best-effort.
        ensurePhoneAccountRegistered(context)

        val handle = phoneAccountHandle(context)
        val extras = model.toTelecomExtras()

        // Адрес нужен системе для отображения как “звонка”; схема SIP — условная, у нас ключ.
        extras.putParcelable(
            TelecomManager.EXTRA_INCOMING_CALL_ADDRESS,
            Uri.fromParts(PhoneAccount.SCHEME_SIP, model.callerKey, null),
        )

        return try {
            tm.addNewIncomingCall(handle, extras)
            OrpheusCallStore.setLastCall(context, model.callId, model.serverTsMs)
            OrpheusCallStore.markActiveCall(context, model.callId ?: model.callerKey)
            Log.i(TAG, "Telecom incoming call requested (callId=${model.callId})")
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "Telecom addNewIncomingCall security error: ${e.message}")
            false
        } catch (e: Exception) {
            Log.e(TAG, "Telecom addNewIncomingCall failed: ${e.message}")
            false
        }
    }

    fun launchMainActivityForTelecomAction(context: Context) {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("from_telecom", true)
        }
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start MainActivity: ${e.message}")
        }
    }
}


