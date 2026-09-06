package com.cashu.me.ui.receive

/** Tracks cumulative BOLT12 issuance across receipts without replaying saved payments. */
internal class ReusableMintPaymentObservation(private var amountIssued: Long) {
    fun newlyIssuedAmount(currentAmountIssued: Long): Long? {
        if (currentAmountIssued <= amountIssued) return null
        val received = currentAmountIssued - amountIssued
        amountIssued = currentAmountIssued
        return received
    }
}
