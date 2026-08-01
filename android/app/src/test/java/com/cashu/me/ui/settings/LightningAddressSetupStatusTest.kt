package com.cashu.me.ui.settings

import com.cashu.me.Core.NPCState
import com.cashu.me.Core.WalletStartupFailure
import com.cashu.me.Core.WalletState
import org.junit.Assert.assertEquals
import org.junit.Test

class LightningAddressSetupStatusTest {
    @Test
    fun enabledAddressShowsProgressWhileWalletRuntimeIsStarting() {
        assertEquals(
            LightningAddressSetupStatus.SettingUp,
            lightningAddressSetupStatus(
                walletState = WalletState(isInitialized = true, isRuntimeReady = false),
                npcState = NPCState(isEnabled = true),
            ),
        )
    }

    @Test
    fun startupFailureOffersRecoveryInsteadOfIndefiniteProgress() {
        assertEquals(
            LightningAddressSetupStatus.NeedsRecovery,
            lightningAddressSetupStatus(
                walletState = WalletState(
                    isInitialized = true,
                    isRuntimeReady = false,
                    startupFailure = WalletStartupFailure("The saved wallet couldn't be opened."),
                ),
                npcState = NPCState(isEnabled = true),
            ),
        )
    }

    @Test
    fun missingAddressAfterRuntimeReadyOffersSetupRecovery() {
        assertEquals(
            LightningAddressSetupStatus.NeedsRecovery,
            lightningAddressSetupStatus(
                walletState = WalletState(isInitialized = true, isRuntimeReady = true),
                npcState = NPCState(isEnabled = true),
            ),
        )
    }

    @Test
    fun disabledFeatureKeepsNeutralEmptyState() {
        assertEquals(
            LightningAddressSetupStatus.Empty,
            lightningAddressSetupStatus(
                walletState = WalletState(isInitialized = true, isRuntimeReady = true),
                npcState = NPCState(isEnabled = false),
            ),
        )
    }
}
