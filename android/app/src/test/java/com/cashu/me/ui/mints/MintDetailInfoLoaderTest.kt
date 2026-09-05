package com.cashu.me.ui.mints

import java.io.IOException
import kotlin.coroutines.Continuation
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MintDetailInfoLoaderTest {
    @Test
    fun cancellationPropagatesWithoutShowingFailureOrLeavingLoading() = runBlocking {
        val loader = MintDetailInfoLoader<String>()
        var propagated = false
        try {
            loader.load { throw CancellationException("View left") }
        } catch (_: CancellationException) {
            propagated = true
        }
        assertTrue(propagated)
        assertNull(loader.info)
        assertNull(loader.errorMessage)
        assertEquals(MintConnectionState.NotChecked, loader.connection)
    }

    @Test
    fun cancelledNativeRequestCannotPublishSuccessOrFailure() = runBlocking {
        for (result in listOf(Result.success("late"), Result.failure(IOException("Timed out")))) {
            val loader = MintDetailInfoLoader<String>()
            val fetch = SuspendedFetch()
            val task = launch(start = CoroutineStart.UNDISPATCHED) { loader.load { fetch.value() } }
            task.cancel()
            fetch.finish(result)
            task.join()

            assertNull(loader.info)
            assertNull(loader.errorMessage)
            assertEquals(MintConnectionState.NotChecked, loader.connection)
        }
    }

    @Test
    fun cancelledRefreshPreservesLoadedInformation() = runBlocking {
        val loader = MintDetailInfoLoader<String>()
        loader.load { "saved" }
        try {
            loader.load { throw CancellationException("View left") }
        } catch (_: CancellationException) {
            // The screen's LaunchedEffect owns this cancellation.
        }
        assertEquals("saved", loader.info)
        assertNull(loader.errorMessage)
        assertEquals(MintConnectionState.NotChecked, loader.connection)
    }

    @Test
    fun failureAfterSuccessKeepsInformationButReportsOffline() = runBlocking {
        val loader = MintDetailInfoLoader<String>()
        loader.load { "saved" }
        loader.load { throw IOException("Timed out") }

        assertEquals("saved", loader.info)
        assertEquals(
            "The mint took too long to respond. Check your connection and try again.",
            loader.errorMessage,
        )
        assertEquals(MintConnectionState.Offline, loader.connection)
    }

    @Test
    fun emptyResponseFailsAndRetryClearsError() = runBlocking {
        val loader = MintDetailInfoLoader<String>()
        loader.load { null }
        assertEquals("The mint did not respond.", loader.errorMessage)
        assertEquals(MintConnectionState.Offline, loader.connection)

        loader.load { "fresh" }
        assertEquals("fresh", loader.info)
        assertNull(loader.errorMessage)
        assertEquals(MintConnectionState.Online, loader.connection)
    }

    @Test
    fun supersededCompletionCannotOverwriteNewerSuccess() = runBlocking {
        val results = listOf(
            Result.success("stale"),
            Result.failure(CancellationException("View left")),
            Result.failure(IOException("Timed out")),
        )
        for (result in results) {
            val loader = MintDetailInfoLoader<String>()
            val fetch = SuspendedFetch()
            val old = launch(start = CoroutineStart.UNDISPATCHED) { loader.load { fetch.value() } }
            loader.load { "fresh" }
            fetch.finish(result)
            old.join()

            assertEquals("fresh", loader.info)
            assertNull(loader.errorMessage)
            assertEquals(MintConnectionState.Online, loader.connection)
        }
    }

    @Test
    fun olderCancellationCannotStopNewerLoadingIndicator() = runBlocking {
        val loader = MintDetailInfoLoader<String>()
        val firstFetch = SuspendedFetch()
        val first = launch(start = CoroutineStart.UNDISPATCHED) { loader.load { firstFetch.value() } }
        val secondFetch = SuspendedFetch()
        val second = launch(start = CoroutineStart.UNDISPATCHED) { loader.load { secondFetch.value() } }

        first.cancel()
        firstFetch.finish(Result.failure(CancellationException("View left")))
        first.join()
        assertEquals(MintConnectionState.Checking, loader.connection)
        assertNull(loader.errorMessage)

        secondFetch.finish(Result.success("fresh"))
        second.join()
        assertEquals(MintConnectionState.Online, loader.connection)
    }

    @Test
    fun alreadyCancelledTaskDoesNotStartFetch() = runBlocking {
        val loader = MintDetailInfoLoader<String>()
        var didFetch = false
        val task = launch {
            cancel()
            loader.load {
                didFetch = true
                "unexpected"
            }
        }
        task.join()
        assertFalse(didFetch)
        assertEquals(MintConnectionState.NotChecked, loader.connection)
    }

    /** Ignores cancellation so tests can finish native work after its caller leaves. */
    private class SuspendedFetch {
        private var continuation: Continuation<String?>? = null

        suspend fun value(): String? = suspendCoroutine { continuation = it }

        fun finish(result: Result<String?>) {
            checkNotNull(continuation).resumeWith(result)
            continuation = null
        }
    }
}
