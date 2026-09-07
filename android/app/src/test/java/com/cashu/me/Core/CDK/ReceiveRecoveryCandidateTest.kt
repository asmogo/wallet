package com.cashu.me.Core.CDK

import org.junit.Assert.*
import org.junit.Test

class ReceiveRecoveryCandidateTest {
    @Test fun readsOnlyReceiveSagaAccountIdentity() {
        assertEquals(ReceiveRecoveryCandidate("https://mint.example", "usd"), receiveRecoveryCandidate(
            """{"kind":"receive","mint_url":"https://mint.example","unit":"usd","data":{"token":"never copied"}}""",
        ))
        assertNull(receiveRecoveryCandidate("""{"kind":"send","mint_url":"https://mint.example","unit":"sat"}"""))
        assertNull(receiveRecoveryCandidate("not JSON"))
    }
}
