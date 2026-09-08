package com.cashu.me.Core

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class WalletDeletionActionTest {
    @Test fun rejectsDuplicateSubmissionsAndAllowsExplicitRetryAfterFailure() = runBlocking {
        val jobs = mutableListOf<suspend CoroutineScope.() -> Unit>()
        var calls = 0
        val action = WalletDeletionAction({ jobs.add(it); Unit }) {
            calls++
            if (calls == 1) error("code=11001, errorMessage=private storage detail")
        }
        action.submit()
        action.submit()
        assertTrue(action.running.value)
        assertEquals(1, jobs.size)
        jobs.removeAt(0)(this)
        assertFalse(action.running.value)
        assertNotNull(action.error.value)
        assertEquals("private storage detail", action.error.value)
        action.submit()
        assertNull(action.error.value)
        jobs.removeAt(0)(this)
        assertEquals(2, calls)
        assertFalse(action.running.value)
        assertNull(action.error.value)
    }

    @Test fun cancellationIsNotReportedAsDeletionFailure() = runBlocking {
        val jobs = mutableListOf<suspend CoroutineScope.() -> Unit>()
        val action = WalletDeletionAction({ jobs.add(it); Unit }) { throw CancellationException() }
        action.submit()
        try { jobs.removeAt(0)(this); fail("Expected cancellation") }
        catch (_: CancellationException) { }
        assertFalse(action.running.value)
        assertNull(action.error.value)
    }
}
