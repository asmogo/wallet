package org.cashu.wallet.Core

import android.view.HapticFeedbackConstants
import org.junit.Assert.assertEquals
import org.junit.Test

class HapticFeedbackTest {
    @Test
    fun selectionUsesLightTickFeedback() {
        assertEquals(
            HapticFeedbackConstants.CLOCK_TICK,
            WalletHaptic.Selection.androidFeedbackConstant(),
        )
    }

    @Test
    fun successUsesContextClickFeedback() {
        assertEquals(
            HapticFeedbackConstants.CONTEXT_CLICK,
            WalletHaptic.Success.androidFeedbackConstant(),
        )
    }

    @Test
    fun warningAndErrorUseAttentionFeedback() {
        assertEquals(HapticFeedbackConstants.LONG_PRESS, WalletHaptic.Warning.androidFeedbackConstant())
        assertEquals(HapticFeedbackConstants.LONG_PRESS, WalletHaptic.Error.androidFeedbackConstant())
    }
}
