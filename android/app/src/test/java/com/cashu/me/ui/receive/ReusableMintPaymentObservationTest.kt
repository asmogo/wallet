package com.cashu.me.ui.receive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReusableMintPaymentObservationTest {
    @Test
    fun `each receipt uses the payment delta and ignores already acknowledged issuance`() {
        val observation = ReusableMintPaymentObservation(0)
        assertNull(observation.newlyIssuedAmount(0))
        assertEquals(21L, observation.newlyIssuedAmount(21))
        assertNull(observation.newlyIssuedAmount(21))
        assertEquals(21L, observation.newlyIssuedAmount(42))
        assertNull(observation.newlyIssuedAmount(42))
        assertEquals(34L, observation.newlyIssuedAmount(76))
    }

    @Test
    fun `saved offer and stale snapshots do not replay success`() {
        val observation = ReusableMintPaymentObservation(100)
        assertNull(observation.newlyIssuedAmount(100))
        assertNull(observation.newlyIssuedAmount(0))
        assertEquals(21L, observation.newlyIssuedAmount(121))
        assertNull(observation.newlyIssuedAmount(100))
        assertNull(observation.newlyIssuedAmount(121))
    }
}
