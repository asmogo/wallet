package com.cashu.me.Core.CDK

import kotlinx.coroutines.CancellationException
import org.cashudevkit.QuoteState

class MeltPaymentRecoveryException(
    val quoteId: String,
    val operationId: String?,
    val unresolved: Boolean,
) : IllegalStateException(if (unresolved) {
    "Payment status is unknown. Do not send it again yet. Refresh History to check settlement."
} else {
    "The mint returned your funds. Create a new quote before trying again."
})

/** Only successful status AND reservation reads can establish that retrying is safe. */
internal suspend fun <T> resolveAmbiguousMelt(
    quoteId: String,
    operationId: String?,
    checkStatus: suspend () -> T,
    recoverSagas: suspend () -> Unit,
    state: (T) -> QuoteState,
    compensationComplete: suspend () -> Boolean,
): T {
    fun unresolved() = MeltPaymentRecoveryException(quoteId, operationId, unresolved = true)
    val checked = try {
        checkStatus()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        try { recoverSagas() } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { }
        try { checkStatus() } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { throw unresolved() }
    }
    if (state(checked) == QuoteState.PAID || state(checked) == QuoteState.ISSUED || state(checked) == QuoteState.PENDING) return checked
    val compensated = try {
        operationId != null && compensationComplete()
    } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { false }
    throw MeltPaymentRecoveryException(quoteId, operationId, unresolved = !compensated)
}
