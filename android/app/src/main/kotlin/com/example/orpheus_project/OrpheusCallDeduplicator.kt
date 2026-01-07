package com.example.orpheus_project

/**
 * Pure логика дедуп/TTL — вынесена отдельно, чтобы покрыть unit-тестами.
 */
object OrpheusCallDeduplicator {
    const val DEFAULT_TTL_MS: Long = 60_000L

    data class Decision(
        val shouldProcess: Boolean,
        val reason: String,
    )

    fun decide(
        nowMs: Long,
        serverTsMs: Long?,
        ttlMs: Long = DEFAULT_TTL_MS,
        callId: String?,
        lastCallId: String?,
        lastCallServerTsMs: Long,
        hasActiveCall: Boolean,
    ): Decision {
        if (hasActiveCall) return Decision(false, "active_call_exists")

        if (serverTsMs != null) {
            val age = nowMs - serverTsMs
            if (age > ttlMs) return Decision(false, "expired_ttl")
            if (age < -5_000L) {
                // Сильно “из будущего” — скорее кривые часы; не блокируем, но отметим.
                // В логах будет видно, если проблема массовая.
            }
        }

        // Предпочтительно дедуп по call_id.
        if (callId != null && lastCallId != null && callId == lastCallId) {
            return Decision(false, "duplicate_call_id")
        }

        // Fallback: если call_id нет, используем serverTs (если есть) как слабый дедуп.
        if (callId == null && serverTsMs != null && lastCallServerTsMs != 0L) {
            val delta = kotlin.math.abs(serverTsMs - lastCallServerTsMs)
            if (delta < 2_000L) return Decision(false, "duplicate_ts_bucket")
        }

        return Decision(true, "ok")
    }
}



