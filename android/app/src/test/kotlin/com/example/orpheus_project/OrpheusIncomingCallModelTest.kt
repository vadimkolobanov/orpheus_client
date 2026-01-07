package com.example.orpheus_project

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class OrpheusIncomingCallModelTest {
    @Test
    fun `parses incoming_call with native_telecom`() {
        val data = mapOf(
            "type" to "incoming_call",
            "caller_key" to "abc123",
            "caller_name" to "Alice",
            "call_id" to "call-1",
            "server_ts_ms" to "1700000000000",
            "native_telecom" to "1",
        )
        val model = OrpheusIncomingCallModel.fromFcmData(data)
        assertNotNull(model)
        assertEquals("call-1", model!!.callId)
        assertEquals("abc123", model.callerKey)
        assertEquals("Alice", model.callerName)
        assertEquals(1700000000000L, model.serverTsMs)
        assertEquals(true, model.nativeTelecom)
    }

    @Test
    fun `returns null for non-call type`() {
        val data = mapOf(
            "type" to "new_message",
            "caller_key" to "abc123",
        )
        assertNull(OrpheusIncomingCallModel.fromFcmData(data))
    }

    @Test
    fun `nativeTelecom false when flag missing`() {
        val data = mapOf(
            "type" to "incoming_call",
            "caller_key" to "abc123",
        )
        val model = OrpheusIncomingCallModel.fromFcmData(data)
        assertNotNull(model)
        assertFalse(model!!.nativeTelecom)
    }
}



