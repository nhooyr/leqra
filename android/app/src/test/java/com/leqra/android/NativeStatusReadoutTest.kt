package com.leqra.android

import org.junit.Assert.assertEquals
import org.junit.Test

class NativeStatusReadoutTest {
    @Test
    fun fpsAndPingFollowTheIOSReadoutInReadyRoomAndDuringPlay() {
        assertEquals("fps: —, ping: —", performanceReadout(true, false, 120, null))
        assertEquals("fps: —, ping: 9 ms", performanceReadout(true, false, 120, 8.7))
        assertEquals("fps: 120, ping: 9 ms", performanceReadout(false, true, 120, 8.7))
        assertEquals("fps: 120, ping: —", performanceReadout(false, true, 120, null))
        assertEquals("fps: 120", performanceReadout(false, false, 120, 8.7))
    }
}
