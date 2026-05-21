package org.cashu.wallet.Core

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView

enum class WalletHaptic {
    Selection,
    LightImpact,
    MediumImpact,
    Success,
    Warning,
    Error,
}

class WalletHapticPerformer internal constructor(
    private val view: View,
) {
    fun perform(type: WalletHaptic) {
        view.performHapticFeedback(type.androidFeedbackConstant())
    }
}

@Composable
fun rememberWalletHaptics(): WalletHapticPerformer {
    val view = LocalView.current
    return remember(view) { WalletHapticPerformer(view) }
}

internal fun WalletHaptic.androidFeedbackConstant(): Int = when (this) {
    WalletHaptic.Selection -> HapticFeedbackConstants.CLOCK_TICK
    WalletHaptic.LightImpact -> HapticFeedbackConstants.KEYBOARD_TAP
    WalletHaptic.MediumImpact -> HapticFeedbackConstants.CONTEXT_CLICK
    WalletHaptic.Success -> HapticFeedbackConstants.CONTEXT_CLICK
    WalletHaptic.Warning -> HapticFeedbackConstants.LONG_PRESS
    WalletHaptic.Error -> HapticFeedbackConstants.LONG_PRESS
}
