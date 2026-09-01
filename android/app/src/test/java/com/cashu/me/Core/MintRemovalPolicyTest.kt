package com.cashu.me.Core

import com.cashu.me.Core.CDK.MultiUnitWalletRemovalException
import com.cashu.me.Core.CDK.mintRemovalUrlsMatch
import com.cashu.me.Core.CDK.normalizedRegisteredWalletUnits
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class MintRemovalPolicyTest {
    @Test
    fun registeredUnitsAreNormalizedAndDeduplicated() {
        assertEquals(
            listOf("eur"),
            normalizedRegisteredWalletUnits(listOf(" EUR ", "eur", "EuR", " ")),
        )
        assertTrue(normalizedRegisteredWalletUnits(emptyList()).isEmpty())
    }

    @Test
    fun mintIdentityFoldsAuthorityButPreservesEncodedAndCaseSensitivePaths() {
        assertTrue(mintRemovalUrlsMatch(
            "https://MINT.example.com/Mint/",
            "HTTPS://mint.example.com/Mint",
        ))
        assertFalse(mintRemovalUrlsMatch(
            "https://mint.example.com/Mint",
            "https://mint.example.com/mint",
        ))
        assertFalse(mintRemovalUrlsMatch(
            "https://mint.example.com/foo%2F",
            "https://mint.example.com/foo/",
        ))
    }

    @Test
    fun multiUnitGatewayRefusalPreservesMetadata() = runBlocking {
        var metadataCommitted = false

        try {
            removeMintWalletBeforeCommit(
                mintUrl = MintUrl,
                removeWalletIfSingleUnit = {
                    throw MultiUnitWalletRemovalException(listOf("sat", "eur"))
                },
                commitMetadata = { metadataCommitted = true },
            )
            fail("Expected multi-unit removal to be refused")
        } catch (_: MultiUnitWalletRemovalException) {
            // Expected: the atomic gateway operation refused before removal.
        }

        assertFalse(metadataCommitted)
    }

    @Test
    fun existingNativeWalletIsRemovedBeforeMetadataCommit() = runBlocking {
        val events = mutableListOf<String>()

        val existed = removeMintWalletBeforeCommit(
            mintUrl = MintUrl,
            removeWalletIfSingleUnit = { mintUrl ->
                events += "remove:$mintUrl"
                true
            },
            commitMetadata = { events += "commit" },
        )

        assertTrue(existed)
        assertEquals(listOf("remove:$MintUrl", "commit"), events)
    }

    @Test
    fun missingNativeWalletCommitsMetadataWithoutInventingSatWallet() = runBlocking {
        val events = mutableListOf<String>()

        val existed = removeMintWalletBeforeCommit(
            mintUrl = MintUrl,
            removeWalletIfSingleUnit = {
                events += "atomic-check-and-remove"
                false
            },
            commitMetadata = { events += "commit" },
        )

        assertFalse(existed)
        assertEquals(listOf("atomic-check-and-remove", "commit"), events)
    }

    @Test
    fun nativeFailurePreservesMetadata() = runBlocking {
        var metadataCommitted = false

        try {
            removeMintWalletBeforeCommit(
                mintUrl = MintUrl,
                removeWalletIfSingleUnit = { throw RepositoryFailure() },
                commitMetadata = { metadataCommitted = true },
            )
            fail("Expected native removal failure")
        } catch (_: RepositoryFailure) {
            // Expected.
        }

        assertFalse(metadataCommitted)
    }

    @Test(expected = CancellationException::class)
    fun cancellationIsPreservedWithoutMetadataCommit() {
        runBlocking {
            var metadataCommitted = false
            try {
                removeMintWalletBeforeCommit(
                    mintUrl = MintUrl,
                    removeWalletIfSingleUnit = { throw CancellationException("cancelled") },
                    commitMetadata = { metadataCommitted = true },
                )
            } finally {
                assertFalse(metadataCommitted)
            }
        }
    }

    @Test
    fun cancellationDuringNativeSuccessStillCommitsMetadata() = runBlocking {
        val nativeStarted = CompletableDeferred<Unit>()
        val allowNativeReturn = CompletableDeferred<Unit>()
        var metadataCommitted = false
        val request = async {
            removeMintWalletBeforeCommit(
                mintUrl = MintUrl,
                removeWalletIfSingleUnit = {
                    nativeStarted.complete(Unit)
                    allowNativeReturn.await()
                    true
                },
                commitMetadata = { metadataCommitted = true },
            )
        }

        nativeStarted.await()
        request.cancel()
        allowNativeReturn.complete(Unit)
        request.join()

        assertTrue(request.isCancelled)
        assertTrue(metadataCommitted)
    }

    private class RepositoryFailure : IllegalStateException("repository unavailable")

    private companion object {
        const val MintUrl = "https://mint.example.com"
    }
}
