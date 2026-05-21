package org.cashu.wallet.Core

import org.junit.Assert.assertEquals
import org.junit.Test

class TransactionUpdateEventsTest {
    @Test
    fun incrementsTransactionUpdateVersion() {
        assertEquals(1, nextTransactionUpdateVersion(0))
        assertEquals(42, nextTransactionUpdateVersion(41))
    }

    @Test
    fun wrapsMaxValueToNonZeroVersion() {
        assertEquals(1, nextTransactionUpdateVersion(Long.MAX_VALUE))
    }
}

