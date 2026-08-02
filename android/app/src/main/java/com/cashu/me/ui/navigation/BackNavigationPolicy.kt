package com.cashu.me.ui.navigation

// Back policies live here only where system back has more than one candidate
// outcome. Flow-sheet screens need no policy: dismissal is the sheet's own job
// — back = swipe = abandon to the wallet — and each screen just swallows back
// while money is moving.
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
