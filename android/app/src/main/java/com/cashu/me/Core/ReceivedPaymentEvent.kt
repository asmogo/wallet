package com.cashu.me.Core

/**
 * Identifies which surface owns confirmation feedback for a successful
 * incoming payment.
 *
 * Receive flows render their own success terminal (and therefore its haptic).
 * Passive receipts have no such terminal, so Home owns the success haptic.
 */
enum class ReceiveConfirmationOwner {
    InFlow,
    Home,
}

data class ReceivedPaymentEvent(
    val amount: Long,
    val unit: String,
    val confirmationOwner: ReceiveConfirmationOwner,
) {
    val homeOwnsSuccessHaptic: Boolean
        get() = confirmationOwner == ReceiveConfirmationOwner.Home
}

/**
 * Build a presentation event only from a confirmed, positive credit.
 *
 * Balance refreshes deliberately have no path through this function: callers
 * invoke it at the successful mint/redeem boundary instead.
 */
internal fun confirmedReceivedPaymentEvent(
    amount: Long,
    unit: String,
    confirmationOwner: ReceiveConfirmationOwner,
): ReceivedPaymentEvent? = amount
    .takeIf { it > 0L }
    ?.let {
        ReceivedPaymentEvent(
            amount = it,
            unit = unit.ifBlank { "sat" }.lowercase(),
            confirmationOwner = confirmationOwner,
        )
    }
