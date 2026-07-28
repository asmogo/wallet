package com.cashu.me.Core

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.cashu.me.Models.CashuRequest
import com.cashu.me.Models.CashuRequestPayment
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction

data class CashuRequestStoreState(
    val requests: List<CashuRequest> = emptyList(),
    val currentRequestId: String? = null,
) {
    val currentRequest: CashuRequest?
        get() = currentRequestId?.let { id -> requests.firstOrNull { it.id == id } }
}

interface CashuRequestPersistence {
    fun loadCashuRequests(): List<CashuRequest>
    fun saveCashuRequests(requests: List<CashuRequest>)
    var currentCashuRequestId: String?
}

class CashuRequestStore(
    private val walletStore: CashuRequestPersistence,
) {
    private val mutableState = MutableStateFlow(loadState())
    val state: StateFlow<CashuRequestStoreState> = mutableState.asStateFlow()

    fun createNew(
        id: String = CashuRequest.newId(),
        amount: Long? = null,
        unit: String = "sat",
        mints: List<String> = emptyList(),
        memo: String? = null,
        encoded: String,
    ): CashuRequest {
        val request = CashuRequest(
            id = id,
            encoded = encoded,
            amount = amount,
            unit = unit,
            mints = mints,
            memo = memo?.takeIf { it.isNotBlank() },
        )
        val updated = listOf(request) + mutableState.value.requests.filterNot { it.id == request.id }
        persist(updated, request.id)
        return request
    }

    fun upsert(request: CashuRequest, makeCurrent: Boolean = true): CashuRequest {
        val updated = listOf(request) + mutableState.value.requests.filterNot { it.id == request.id }
        persist(updated, if (makeCurrent) request.id else mutableState.value.currentRequestId)
        return request
    }

    fun update(
        id: String,
        amount: Long?,
        unit: String,
        mints: List<String>,
        memo: String?,
        encoded: String,
    ): CashuRequest? {
        val existing = request(id) ?: return null
        val updatedRequest = existing.copy(
            amount = amount,
            unit = unit,
            mints = mints,
            memo = memo?.takeIf { it.isNotBlank() },
            encoded = encoded,
        )
        upsert(updatedRequest, makeCurrent = mutableState.value.currentRequestId == id)
        return updatedRequest
    }

    fun upsertQuoteIntent(
        id: String = CashuRequest.newId(),
        quoteId: String,
        quoteKind: String,
        amount: Long?,
        unit: String = "sat",
        mints: List<String> = emptyList(),
        memo: String? = null,
        encoded: String,
    ): CashuRequest {
        // Re-opening an amountless BOLT12 offer must keep its request identity
        // and its accumulated payments. Otherwise every visit creates another
        // history row for the same reusable invoice.
        val existing = mutableState.value.requests.firstOrNull { it.quoteId == quoteId }
        return upsert(
            CashuRequest(
                id = existing?.id ?: id,
                encoded = encoded,
                amount = amount,
                unit = unit,
                mints = mints,
                memo = memo?.takeIf { it.isNotBlank() },
                createdAtEpochMillis = existing?.createdAtEpochMillis ?: System.currentTimeMillis(),
                quoteId = quoteId,
                quoteKind = quoteKind,
                receivedPayments = existing?.receivedPayments.orEmpty(),
                receivedPaymentIds = existing?.receivedPaymentIds.orEmpty(),
            ),
        )
    }

    fun attachPayment(requestId: String, transactionId: String, amount: Long) {
        val current = mutableState.value
        val updated = current.requests.map { request ->
            if (request.id != requestId || request.receivedPayments.any { it.transactionId == transactionId }) {
                request
            } else {
                request.copy(
                    receivedPayments = request.receivedPayments + CashuRequestPayment(
                        transactionId = transactionId,
                        amount = amount,
                        receivedAtEpochMillis = System.currentTimeMillis(),
                    ),
                )
            }
        }
        persist(updated, current.currentRequestId)
    }

    fun attachPaymentByQuoteId(quoteId: String, transactionId: String, amount: Long) {
        val request = mutableState.value.requests.firstOrNull { it.quoteId == quoteId } ?: return
        attachPayment(request.id, transactionId, amount)
    }

    /**
     * Reconcile received wallet transactions with persistent quote-backed
     * requests. A reusable BOLT12 offer stays as one history item while each
     * incoming payment is attached to it by its stable transaction id.
     */
    fun reconcileIncomingQuotePayments(transactions: List<WalletTransaction>) {
        val current = mutableState.value
        val incomingByQuoteId = transactions
            .asSequence()
            .filter { it.type == TransactionType.Incoming }
            .mapNotNull { transaction ->
                transaction.quoteId?.let { quoteId -> quoteId to transaction }
            }
            .groupBy({ it.first }, { it.second })
        if (incomingByQuoteId.isEmpty()) return

        var changed = false
        val updated = current.requests.map { request ->
            val quoteId = request.quoteId ?: return@map request
            val payments = request.receivedPayments.toMutableList()
            incomingByQuoteId[quoteId].orEmpty().forEach { transaction ->
                val existingIndex = payments.indexOfFirst { it.transactionId == transaction.id }
                if (existingIndex == -1) {
                    payments += CashuRequestPayment(
                        transactionId = transaction.id,
                        amount = transaction.amount,
                        receivedAtEpochMillis = transaction.dateEpochMillis,
                    )
                    changed = true
                } else if (
                    // When offline, the pending-quote fallback is keyed by the
                    // quote itself and reports its latest aggregate amount.
                    // Refresh that synthetic entry instead of double-counting.
                    transaction.id == quoteId &&
                    transaction.amount > payments[existingIndex].amount
                ) {
                    payments[existingIndex] = payments[existingIndex].copy(
                        amount = transaction.amount,
                        receivedAtEpochMillis = transaction.dateEpochMillis,
                    )
                    changed = true
                }
            }
            request.takeIf { payments == request.receivedPayments }
                ?: request.copy(receivedPayments = payments)
        }
        if (changed) persist(updated, current.currentRequestId)
    }

    fun delete(id: String) {
        val current = mutableState.value
        val updated = current.requests.filterNot { it.id == id }
        val nextCurrent = current.currentRequestId.takeUnless { it == id }
        persist(updated, nextCurrent)
    }

    fun request(id: String): CashuRequest? =
        mutableState.value.requests.firstOrNull { it.id == id }

    fun reload() {
        mutableState.value = loadState()
    }

    /** Clear both observable and persisted request state before changing wallets. */
    fun resetForWalletBoundary() {
        reset()
    }

    fun reset() {
        persist(emptyList(), null)
    }

    private fun loadState(): CashuRequestStoreState {
        val requests = walletStore.loadCashuRequests()
        val currentId = walletStore.currentCashuRequestId
            ?.takeIf { id -> requests.any { it.id == id } }
        if (currentId != walletStore.currentCashuRequestId) {
            walletStore.currentCashuRequestId = currentId
        }
        return CashuRequestStoreState(
            requests = requests.sortedByDescending { it.createdAtEpochMillis },
            currentRequestId = currentId,
        )
    }

    private fun persist(requests: List<CashuRequest>, currentRequestId: String?) {
        val normalized = requests.map { it.withLegacyPaymentFallback() }
            .sortedByDescending { it.createdAtEpochMillis }
        walletStore.saveCashuRequests(normalized)
        walletStore.currentCashuRequestId = currentRequestId
        mutableState.value = CashuRequestStoreState(
            requests = normalized,
            currentRequestId = currentRequestId,
        )
    }
}
