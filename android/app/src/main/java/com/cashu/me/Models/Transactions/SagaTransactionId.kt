package com.cashu.me.Models

/**
 * CDK derives the transaction id of a saga-managed operation from the
 * operation (UUID) id: the id's dash-free ASCII form becomes the 32 id bytes,
 * which the FFI then hex-encodes. Reproduced locally because the FFI helper
 * (`TransactionId.from_saga_id`) is not exported to the bindings.
 * iOS `SagaTransactionId` parity.
 */
object SagaTransactionId {
    /** Operation (saga) UUID string → CDK transaction id hex. */
    fun transactionIdHex(operationId: String): String? {
        val simple = operationId.lowercase().replace("-", "")
        if (simple.length != 32 || !simple.all(::isHexDigitChar)) return null
        return simple.toByteArray(Charsets.UTF_8).joinToString("") { "%02x".format(it) }
    }

    /** CDK transaction id hex → operation (saga) UUID string, as accepted by
     * `checkSendStatus` / `revokeSend` (UUID parsing tolerates the simple form). */
    fun operationId(fromTransactionIdHex: String): String? {
        if (fromTransactionIdHex.length != 64) return null
        val bytes = try {
            fromTransactionIdHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        } catch (_: NumberFormatException) {
            return null
        }
        val simple = String(bytes, Charsets.UTF_8)
        if (simple.length != 32 || !simple.all(::isHexDigitChar)) return null
        return simple
    }

    private fun isHexDigitChar(c: Char): Boolean = c.isDigit() || c in 'a'..'f'
}
