package com.leqra.android.accounts

import org.junit.Assert.*
import org.junit.Test

class CallsignDraftsTest {
    private fun fresh() = CallsignDrafts(listOf(null, null), listOf(null, null), listOf(null, null))

    @Test
    fun freshSeatsGetIndependentSecureNamesAndOnePersistableRequest() {
        val state = fresh()
        assertNotEquals(state.name(0), state.name(1))
        for (seat in 0..1) {
            assertTrue(
                Regex("pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}").matches(state.name(seat))
            )
            assertTrue(state.pending(seat))
        }
        assertEquals(state.requestID(0), state.requestID(1))
        val restored =
            CallsignDrafts(
                (0..1).map(state::name),
                (0..1).map(state::pending),
                (0..1).map(state::requestID),
            )
        for (seat in 0..1) {
            assertEquals(state.name(seat), restored.name(seat))
            assertEquals(state.requestID(seat), restored.requestID(seat))
        }
    }

    @Test
    fun savedNamesStayChosenAndManualGenerationUsesFreshId() {
        val state =
            CallsignDrafts(listOf("RUST", "Godlike Bot 7"), listOf(null, null), listOf(null, null))
        assertFalse(state.pending(0))
        assertFalse(state.pending(1))
        val id = state.requestID(0)
        state.generate(0)
        assertNotEquals(id, state.requestID(0))
        assertTrue(Regex("pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}").matches(state.name(0)))
        assertTrue(state.pending(0))
        assertEquals("Godlike Bot 7", state.name(1))
    }

    @Test
    fun lateRepliesCannotOverwriteEditsImportsServersKeysOrNewAttempts() {
        for (change in 0..4) {
            val state = fresh()
            val request = state.request(0, "https://one.test", "key1")
            when (change) {
                0 -> state.edit(0, "MY DRAFT")
                1 -> state.cancel(0)
                2 -> state.generate(0)
            }
            assertFalse(
                state.complete(
                    request,
                    if (change == 3) "https://two.test" else request.origin,
                    if (change == 4) "key2" else request.key,
                    "pilot-abcdefghij",
                )
            )
        }
        val state = fresh()
        assertTrue(
            state.complete(state.request(0, "origin", "key"), "origin", "key", "pilot-abcdefghij")
        )
        assertEquals("pilot-abcdefghij", state.name(0))
        assertFalse(state.pending(0))
        assertTrue(state.pending(1))
    }

    @Test
    fun existingLegacyGeneratedNamesRemainUnchanged() {
        val state =
            CallsignDrafts(
                listOf("pilot-abcdefghij", "pilot-klmnopqrst"),
                listOf(null, null),
                listOf(null, null),
            )
        assertEquals("pilot-abcdefghij", state.name(0))
        assertEquals("pilot-klmnopqrst", state.name(1))
        assertFalse(state.pending(0))
        assertFalse(state.pending(1))
    }
}
