package com.cashu.me.ui.navigation

enum class ShellBackAction {
    CloseReceiveDetail,
    CloseScanner,
}

fun shellBackAction(
    receiveDetailVisible: Boolean,
    scannerVisible: Boolean,
): ShellBackAction? =
    when {
        receiveDetailVisible -> ShellBackAction.CloseReceiveDetail
        scannerVisible -> ShellBackAction.CloseScanner
        else -> null
    }

enum class OnboardingBackState {
    Welcome,
    ShowMnemonic,
    FirstMint,
    RestoreMethod,
    RestoreInput,
    RestoreMints,
    RestoreProgress,
}

enum class OnboardingBackAction {
    CloseRestoreFlow,
    Welcome,
    ShowMnemonic,
    RestoreMethod,
    RestoreInput,
    RestoreMints,
    Stay,
}

fun onboardingBackAction(
    state: OnboardingBackState,
    canExitOnboarding: Boolean,
    restoreInProgress: Boolean = false,
): OnboardingBackAction =
    when (state) {
        OnboardingBackState.Welcome ->
            if (canExitOnboarding) OnboardingBackAction.CloseRestoreFlow else OnboardingBackAction.Stay
        OnboardingBackState.ShowMnemonic -> OnboardingBackAction.Welcome
        OnboardingBackState.FirstMint -> OnboardingBackAction.ShowMnemonic
        OnboardingBackState.RestoreMethod -> OnboardingBackAction.Welcome
        // iOS retreats from seed input straight to welcome.
        OnboardingBackState.RestoreInput -> OnboardingBackAction.Welcome
        OnboardingBackState.RestoreMints -> OnboardingBackAction.RestoreInput
        // Forward-only on results (iOS hides back once restore starts).
        OnboardingBackState.RestoreProgress -> OnboardingBackAction.Stay
    }

enum class UnifiedSendBackAction {
    Ignore,
    Close,
    ReturnToAmount,
    ResetToInput,
}

fun unifiedSendBackAction(
    sending: Boolean,
    statusVisible: Boolean,
    onConfirmStep: Boolean,
    cameFromAmount: Boolean,
    onInputStep: Boolean,
): UnifiedSendBackAction =
    when {
        sending -> UnifiedSendBackAction.Ignore
        statusVisible -> UnifiedSendBackAction.Close
        onConfirmStep && cameFromAmount -> UnifiedSendBackAction.ReturnToAmount
        !onInputStep -> UnifiedSendBackAction.ResetToInput
        else -> UnifiedSendBackAction.Close
    }

enum class SendEcashBackAction {
    Ignore,
    ReturnToInput,
    Close,
}

fun sendEcashBackAction(sending: Boolean, generated: Boolean): SendEcashBackAction =
    when {
        sending -> SendEcashBackAction.Ignore
        generated -> SendEcashBackAction.ReturnToInput
        else -> SendEcashBackAction.Close
    }

enum class ReceiveEcashBackAction {
    Ignore,
    ReturnToPaste,
    Close,
}

fun receiveEcashBackAction(claiming: Boolean, reviewing: Boolean): ReceiveEcashBackAction =
    when {
        claiming -> ReceiveEcashBackAction.Ignore
        reviewing -> ReceiveEcashBackAction.ReturnToPaste
        else -> ReceiveEcashBackAction.Close
    }

enum class ReceiveLightningBackAction {
    ReturnToInput,
    Close,
}

fun receiveLightningBackAction(displayingQuote: Boolean): ReceiveLightningBackAction =
    if (displayingQuote) ReceiveLightningBackAction.ReturnToInput else ReceiveLightningBackAction.Close

enum class ConnectMintBackAction {
    ReturnToPicker,
    Close,
}

/**
 * The connect-a-mint sheet pushes "Add custom mint URL" and "Discover mints" as
 * in-sheet steps, so back unwinds to the picker before the host sheet sees it.
 */
fun connectMintBackAction(onPickerStep: Boolean): ConnectMintBackAction =
    if (onPickerStep) ConnectMintBackAction.Close else ConnectMintBackAction.ReturnToPicker

enum class SimpleBackAction {
    Close,
    CloseSearch,
    CloseDetail,
}

fun historyBackAction(searching: Boolean): SimpleBackAction? =
    if (searching) SimpleBackAction.CloseSearch else null

fun p2pkBackAction(showingDetail: Boolean): SimpleBackAction? =
    if (showingDetail) SimpleBackAction.CloseDetail else null

fun directSurfaceBackAction(): SimpleBackAction = SimpleBackAction.Close
