package com.cashu.me.ui.navigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BackNavigationPolicyTest {
    @Test
    fun shellBackPrioritizesTopmostOverlay() {
        assertEquals(
            ShellBackAction.CloseReceiveDetail,
            shellBackAction(receiveDetailVisible = true, scannerVisible = true),
        )
        assertEquals(
            ShellBackAction.CloseScanner,
            shellBackAction(receiveDetailVisible = false, scannerVisible = true),
        )
        assertNull(shellBackAction(receiveDetailVisible = false, scannerVisible = false))
    }

    @Test
    fun onboardingBackMovesOneLogicalStepOrStaysDuringRestore() {
        assertEquals(OnboardingBackAction.Stay, onboardingBackAction(OnboardingBackState.Welcome, canExitOnboarding = false))
        assertEquals(OnboardingBackAction.CloseRestoreFlow, onboardingBackAction(OnboardingBackState.Welcome, canExitOnboarding = true))
        assertEquals(OnboardingBackAction.Welcome, onboardingBackAction(OnboardingBackState.ShowMnemonic, canExitOnboarding = false))
        assertEquals(OnboardingBackAction.ShowMnemonic, onboardingBackAction(OnboardingBackState.FirstMint, canExitOnboarding = false))
        assertEquals(OnboardingBackAction.Welcome, onboardingBackAction(OnboardingBackState.RestoreMethod, canExitOnboarding = false))
        assertEquals(OnboardingBackAction.Welcome, onboardingBackAction(OnboardingBackState.RestoreInput, canExitOnboarding = false))
        assertEquals(OnboardingBackAction.RestoreInput, onboardingBackAction(OnboardingBackState.RestoreMints, canExitOnboarding = false))
        assertEquals(
            OnboardingBackAction.Stay,
            onboardingBackAction(OnboardingBackState.RestoreProgress, canExitOnboarding = false, restoreInProgress = true),
        )
        assertEquals(
            OnboardingBackAction.Stay,
            onboardingBackAction(OnboardingBackState.RestoreProgress, canExitOnboarding = false, restoreInProgress = false),
        )
    }

    @Test
    fun moneyFlowBackPoliciesHandleBusyAndNestedStates() {
        assertEquals(
            UnifiedSendBackAction.Ignore,
            unifiedSendBackAction(sending = true, statusVisible = false, onConfirmStep = true, cameFromAmount = true, onInputStep = false),
        )
        assertEquals(
            UnifiedSendBackAction.Close,
            unifiedSendBackAction(sending = false, statusVisible = true, onConfirmStep = false, cameFromAmount = false, onInputStep = false),
        )
        assertEquals(
            UnifiedSendBackAction.ReturnToAmount,
            unifiedSendBackAction(sending = false, statusVisible = false, onConfirmStep = true, cameFromAmount = true, onInputStep = false),
        )
        assertEquals(
            UnifiedSendBackAction.ResetToInput,
            unifiedSendBackAction(sending = false, statusVisible = false, onConfirmStep = false, cameFromAmount = false, onInputStep = false),
        )
        assertEquals(
            UnifiedSendBackAction.Close,
            unifiedSendBackAction(sending = false, statusVisible = false, onConfirmStep = false, cameFromAmount = false, onInputStep = true),
        )

        assertEquals(SendEcashBackAction.Ignore, sendEcashBackAction(sending = true, generated = true))
        assertEquals(SendEcashBackAction.ReturnToInput, sendEcashBackAction(sending = false, generated = true))
        assertEquals(SendEcashBackAction.Close, sendEcashBackAction(sending = false, generated = false))

        assertEquals(ReceiveEcashBackAction.Ignore, receiveEcashBackAction(claiming = true, reviewing = true))
        assertEquals(ReceiveEcashBackAction.ReturnToPaste, receiveEcashBackAction(claiming = false, reviewing = true))
        assertEquals(ReceiveEcashBackAction.Close, receiveEcashBackAction(claiming = false, reviewing = false))

        assertEquals(ReceiveLightningBackAction.ReturnToInput, receiveLightningBackAction(displayingQuote = true))
        assertEquals(ReceiveLightningBackAction.Close, receiveLightningBackAction(displayingQuote = false))

        assertEquals(ConnectMintBackAction.ReturnToPicker, connectMintBackAction(onPickerStep = false))
        assertEquals(ConnectMintBackAction.Close, connectMintBackAction(onPickerStep = true))
    }

    @Test
    fun simpleBackPoliciesCoverSearchDetailAndDirectSurfaces() {
        assertEquals(SimpleBackAction.CloseSearch, historyBackAction(searching = true))
        assertNull(historyBackAction(searching = false))
        assertEquals(SimpleBackAction.CloseDetail, p2pkBackAction(showingDetail = true))
        assertNull(p2pkBackAction(showingDetail = false))
        assertEquals(SimpleBackAction.Close, directSurfaceBackAction())
    }
}
