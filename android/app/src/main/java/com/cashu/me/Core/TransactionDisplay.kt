package com.cashu.me.Core

import java.net.URI
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry

data class TransactionDetailField(
    val label: String,
    val value: String,
    // Full untruncated payload for tap-to-copy rows (the display `value` may be
    // middle-truncated); null = row is not copyable.
    val copyValue: String? = null,
)

object TransactionDisplay {
    // Kind-first, capitalized kind, lowercase verb — single source of truth for
    // rows AND the detail title, so a row and the sheet it opens read identically.
    fun title(transaction: WalletTransaction): String = when (transaction.kind) {
        TransactionKind.Lightning -> when {
            transaction.type != TransactionType.Incoming -> "Lightning paid"
            // Nothing has been received while the invoice awaits payment.
            transaction.isUnpaidInvoice -> "Lightning invoice"
            else -> "Lightning received"
        }
        TransactionKind.Onchain -> if (transaction.type == TransactionType.Incoming) {
            "Bitcoin received"
        } else {
            "Bitcoin sent"
        }
        TransactionKind.Ecash -> if (transaction.type == TransactionType.Incoming) {
            "Ecash received"
        } else {
            "Ecash sent"
        }
    }

    // The Status detail row: monochrome value, the hero glyph carries colour.
    fun statusText(transaction: WalletTransaction): String = when (transaction.status) {
        TransactionStatus.Completed -> when (transaction.kind) {
            TransactionKind.Ecash -> "Claimed"
            TransactionKind.Lightning -> "Paid"
            TransactionKind.Onchain -> "Confirmed"
        }
        TransactionStatus.Pending -> "Pending"
        TransactionStatus.Failed -> "Failed"
        TransactionStatus.Expired -> "Expired"
    }

    fun qrContent(transaction: WalletTransaction): String? =
        transaction.token ?: transaction.invoice

    /**
     * The QR hero appears only while the artifact remains useful. Ecash is
     * shareable only for an unclaimed outgoing send; an incoming pending token
     * is money to claim, not a payment code. One-shot Lightning invoices retire
     * after settlement, reusable BOLT12 offers stay live, and on-chain addresses
     * retire once the deposit is minted — a confirmed receive is a historical
     * receipt (checkmark hero), not a payment code to re-present.
     */
    fun showsQr(transaction: WalletTransaction): Boolean = when (transaction.kind) {
        TransactionKind.Ecash ->
            transaction.token != null &&
                transaction.type == TransactionType.Outgoing &&
                transaction.status == TransactionStatus.Pending
        TransactionKind.Lightning ->
            transaction.invoice != null &&
                (transaction.status == TransactionStatus.Pending ||
                    transaction.invoice.startsWith("lno", ignoreCase = true))
        TransactionKind.Onchain ->
            transaction.invoice != null && transaction.status == TransactionStatus.Pending
    }

    /**
     * Settled-ecash receipt carve-out: a completed ecash transaction keeps a
     * passive Copy of the raw token as a record — never the QR or Share.
     */
    fun copyableContent(transaction: WalletTransaction): String? = when {
        showsQr(transaction) -> qrContent(transaction)
        transaction.kind == TransactionKind.Ecash &&
            transaction.status == TransactionStatus.Completed -> transaction.token
        else -> null
    }

    fun qrLabel(transaction: WalletTransaction): String = when (transaction.kind) {
        TransactionKind.Ecash -> "Ecash token"
        TransactionKind.Lightning -> "Payment request"
        TransactionKind.Onchain -> "Bitcoin address"
    }

    // Detail rows follow the iOS canon: Status first (monochrome), Date, then
    // conditional essentials — Fee when > 0, Mint, Lightning payment proof,
    // or on-chain Address/Transaction ID. Type/Direction/Unit rows stay dropped;
    // amounts and fees already carry their native unit.
    fun detailFields(transaction: WalletTransaction): List<TransactionDetailField> =
        buildList {
            add(TransactionDetailField("Status", statusText(transaction)))
            add(TransactionDetailField("Date", formatDetailDate(transaction.dateEpochMillis)))
            if (transaction.fee > 0) add(TransactionDetailField("Fee", formatNativeAmount(transaction.fee, transaction.unit)))
            transaction.mintUrl?.let { add(TransactionDetailField("Mint", mintHost(it))) }
            transaction.memo
                ?.takeIf { it.isNotBlank() }
                ?.let { add(TransactionDetailField("Memo", it)) }
            if (transaction.kind == TransactionKind.Onchain) {
                // Address/txid are reference blobs — show the decoder's standard
                // 8…6 short form; tap-to-copy carries the full value.
                transaction.invoice?.let {
                    add(TransactionDetailField("Address", middleTruncated(it), copyValue = it))
                }
                transaction.preimage?.let {
                    add(TransactionDetailField("Transaction ID", middleTruncated(it), copyValue = it))
                }
            } else {
                transaction.preimage?.let {
                    add(TransactionDetailField("Payment Proof", middleTruncated(it), copyValue = it))
                }
            }
        }

    /** `prefix(8)…suffix(6)` middle-truncation, the decoder's convention for
     *  opaque destination blobs; short strings pass through untouched. */
    private fun middleTruncated(value: String): String =
        if (value.length > 16) "${value.take(8)}…${value.takeLast(6)}" else value

    private fun formatNativeAmount(amount: Long, unit: String): String =
        if (unit.equals("sat", ignoreCase = true)) {
            "$amount sat"
        } else {
            CurrencyAmount(amount, CurrencyRegistry.currencyForMintUnit(unit)).formatted()
        }

    private fun formatDetailDate(epochMillis: Long): String =
        java.text.DateFormat.getDateTimeInstance(
            java.text.DateFormat.MEDIUM,
            java.text.DateFormat.SHORT,
        ).format(java.util.Date(epochMillis))

    private fun mintHost(url: String): String =
        runCatching { URI.create(url).host }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: url
}
