package com.example.orpheus_project

import java.util.concurrent.ConcurrentHashMap

/**
 * Простая registry для связи IncomingCallActivity ↔ OrpheusConnection.
 *
 * Важно: best-effort, живёт только в памяти процесса.
 */
object OrpheusConnectionRegistry {
    private val byKey = ConcurrentHashMap<String, OrpheusConnection>()

    fun register(key: String, connection: OrpheusConnection) {
        byKey[key] = connection
    }

    fun get(key: String): OrpheusConnection? = byKey[key]

    fun remove(key: String) {
        byKey.remove(key)
    }
}


