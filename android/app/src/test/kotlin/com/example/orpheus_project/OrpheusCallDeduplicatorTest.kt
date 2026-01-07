package com.example.orpheus_project

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OrpheusCallDeduplicatorTest {
    @Test
    fun `blocks when active call exists`() {
        val d = OrpheusCallDeduplicator.decide(
            nowMs = 1000,
            serverTsMs = 900,
            callId = "c1",
            lastCallId = null,
            lastCallServerTsMs = 0,
            hasActiveCall = true,
        )
        assertFalse(d.shouldProcess)
    }

    @Test
    fun `blocks expired by ttl`() {
        val d = OrpheusCallDeduplicator.decide(
            nowMs = 100_000,
            serverTsMs = 0,
            ttlMs = 60_000,
            callId = "c1",
            lastCallId = null,
            lastCallServerTsMs = 0,
            hasActiveCall = false,
        )
        assertFalse(d.shouldProcess)
    }

    @Test
    fun `blocks duplicate call_id`() {
        val d = OrpheusCallDeduplicator.decide(
            nowMs = 1000,
            serverTsMs = 900,
            callId = "c1",
            lastCallId = "c1",
            lastCallServerTsMs = 900,
            hasActiveCall = false,
        )
        assertFalse(d.shouldProcess)
    }

    @Test
    fun `allows fresh new call`() {
        val d = OrpheusCallDeduplicator.decide(
            nowMs = 1000,
            serverTsMs = 990,
            callId = "c2",
            lastCallId = "c1",
            lastCallServerTsMs = 800,
            hasActiveCall = false,
        )
        assertTrue(d.shouldProcess)
    }
}



