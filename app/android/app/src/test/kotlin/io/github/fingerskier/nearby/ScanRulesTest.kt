package io.github.fingerskier.nearby

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ScanRulesTest {
    @Test
    fun startsFreelyUnderTheLimit() {
        val limiter = StartLimiter()
        for (at in listOf(0L, 1_000, 2_000, 3_000)) {
            assertEquals(0, limiter.delayAt(at))
            limiter.record(at)
        }
    }

    @Test
    fun aFifthStartWaitsUntilTheOldestLeavesTheWindow() {
        val limiter = StartLimiter()
        listOf(0L, 1_000, 2_000, 3_000).forEach(limiter::record)
        // The oldest start leaves the 30 s window at 30 s; one more second of margin.
        assertEquals(27_000, limiter.delayAt(4_000))
        assertEquals(0, limiter.delayAt(31_000))
    }

    @Test
    fun neverAllowsFiveStartsWithinThirtySeconds() {
        val limiter = StartLimiter()
        val starts = mutableListOf<Long>()
        var now = 0L
        repeat(40) {
            now += limiter.delayAt(now)
            limiter.record(now)
            starts += now
            now += 100
        }
        for (i in 4 until starts.size) {
            assert(starts[i] - starts[i - 4] >= 30_000) { "starts ${starts.subList(i - 4, i + 1)} are too close" }
        }
    }

    @Test
    fun namesAddressTypesLikeBlueZ() {
        assertEquals("public", addressTypeName(0))
        assertEquals("random", addressTypeName(1))
        assertNull(addressTypeName(0xFF)) // anonymous
        assertNull(addressTypeName(0xFFFF)) // unknown
    }

    @Test
    fun expandsSixteenBitUuids() {
        assertEquals("0000fe2c-0000-1000-8000-00805f9b34fb", uuid16(0xFE2C))
    }
}
