import Foundation
import SwiftUI

@MainActor
class CashuRequestStore: ObservableObject {
    static let shared = CashuRequestStore()

    @Published private(set) var requests: [CashuRequest] = []
    @Published var currentRequestId: String?

    private let storageKey = StorageKeys.cashuRequests
    private let currentIdKey = StorageKeys.cashuRequestsCurrentId
    private let userDefaults: UserDefaults

    var currentRequest: CashuRequest? {
        guard let id = currentRequestId else { return nil }
        return requests.first(where: { $0.id == id })
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    /// Rail-generic intent creation. `createNew` below is the ecash-specific
    /// wrapper kept for existing call sites; the quote-backed rails go through
    /// `upsertQuoteIntent` so re-opening a reusable offer never duplicates a row.
    @discardableResult
    func create(
        id: String = CashuRequest.newId(),
        rail: CashuRequest.Rail,
        encoded: String,
        amount: UInt64? = nil,
        unit: String = "sat",
        mints: [String] = [],
        memo: String? = nil,
        quoteId: String? = nil,
        reusable: Bool,
        expiry: Date? = nil,
        makeCurrent: Bool = false
    ) -> CashuRequest {
        let intent = CashuRequest(
            id: id,
            encoded: encoded,
            amount: amount,
            unit: unit,
            mints: mints,
            memo: memo,
            rail: rail,
            reusable: reusable,
            quoteId: quoteId,
            expiry: expiry
        )
        requests.insert(intent, at: 0)
        // `currentRequestId` is the ecash receive-screen's "current request"
        // pointer; only the ecash rail should move it.
        if makeCurrent { currentRequestId = intent.id }
        persist()
        return intent
    }

    func createNew(
        id: String = CashuRequest.newId(),
        amount: UInt64? = nil,
        unit: String = "sat",
        mints: [String] = [],
        memo: String? = nil,
        encoded: String
    ) -> CashuRequest {
        create(
            id: id,
            rail: .ecash,
            encoded: encoded,
            amount: amount,
            unit: unit,
            mints: mints,
            memo: memo,
            reusable: true,
            makeCurrent: true
        )
    }

    /// The intent backing a given mint quote, if one exists. The `quoteId` is
    /// the join key for the Lightning / on-chain rails.
    func intent(forQuoteId quoteId: String) -> CashuRequest? {
        requests.first { $0.quoteId == quoteId }
    }

    /// Create the intent for a quote-backed rail, or return the existing one if
    /// this quote already has a row. Reusable BOLT12 offers are re-opened often
    /// and must map to a single persistent intent, never a fresh one per open.
    @discardableResult
    func upsertQuoteIntent(
        rail: CashuRequest.Rail,
        quoteId: String,
        encoded: String,
        amount: UInt64? = nil,
        unit: String = "sat",
        mints: [String] = [],
        memo: String? = nil,
        reusable: Bool,
        expiry: Date? = nil
    ) -> CashuRequest {
        if let existing = intent(forQuoteId: quoteId) { return existing }
        return create(
            rail: rail,
            encoded: encoded,
            amount: amount,
            unit: unit,
            mints: mints,
            memo: memo,
            quoteId: quoteId,
            reusable: reusable,
            expiry: expiry
        )
    }

    /// Track reuse separately from creation so clearing a description survives reopening.
    func markQuotePresented(_ quoteId: String) {
        guard let index = requests.firstIndex(where: { $0.quoteId == quoteId }) else { return }
        requests[index].lastPresentedAt = Date()
        persist()
    }

    func lastPresentedAmountlessOffer(mintURL: String, unit: String) -> CashuRequest? {
        requests.filter {
            $0.rail == .bolt12 && $0.amount == nil && $0.mints.contains(mintURL) &&
                $0.unit.lowercased() == unit.lowercased()
        }.max { ($0.lastPresentedAt ?? $0.createdAt) < ($1.lastPresentedAt ?? $1.createdAt) }
    }

    /// Amount and mint edits keep the NUT-18 identity within one currency.
    /// Changing currency creates a separate intent so old copies and their
    /// payments keep their original denomination. Encode before mutating state.
    @discardableResult
    func update(
        id: String,
        amount: UInt64?,
        unit: String,
        mints: [String],
        encoded encode: (String) throws -> String
    ) rethrows -> CashuRequest? {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { return nil }
        let old = requests[index]
        if old.unit.caseInsensitiveCompare(unit) != .orderedSame {
            let newId = CashuRequest.newId()
            let encoded = try encode(newId)
            return createNew(id: newId, amount: amount, unit: unit, mints: mints, memo: old.memo, encoded: encoded)
        }
        let encoded = try encode(old.id)
        requests[index] = CashuRequest(
            id: old.id,
            encoded: encoded,
            amount: amount,
            unit: unit,
            mints: mints,
            memo: old.memo,
            createdAt: old.createdAt,
            receivedPayments: old.receivedPayments,
            rail: old.rail,
            reusable: old.reusable,
            quoteId: old.quoteId,
            expiry: old.expiry,
            lastPresentedAt: old.lastPresentedAt
        )
        persist()
        return requests[index]
    }

    func attachPayment(requestId: String, transactionId: String, amount: UInt64) {
        guard let index = requests.firstIndex(where: { $0.id == requestId }) else { return }
        attachPayment(at: index, transactionId: transactionId, amount: amount)
    }

    /// Attach an incoming CDK transaction to the intent backing its mint quote
    /// (Lightning / on-chain rails). No-op when no intent owns the quote, so an
    /// out-of-band receive still renders as its own plain timeline row.
    func attachPayment(quoteId: String, transactionId: String, amount: UInt64) {
        guard let index = requests.firstIndex(where: { $0.quoteId == quoteId }) else { return }
        attachPayment(at: index, transactionId: transactionId, amount: amount)
    }

    private func attachPayment(at index: Int, transactionId: String, amount: UInt64) {
        guard !requests[index].receivedPayments.contains(where: { $0.transactionId == transactionId }) else { return }
        requests[index].receivedPayments.append(
            CashuRequestPayment(transactionId: transactionId, amount: amount, receivedAt: Date())
        )
        persist()
    }

    func delete(id: String) {
        requests.removeAll { $0.id == id }
        if currentRequestId == id { currentRequestId = nil }
        persist()
    }

    func request(withId id: String) -> CashuRequest? {
        requests.first(where: { $0.id == id })
    }

    /// Wipe all request intents at a wallet boundary (delete / create / restore).
    /// Requests belong to the wallet that created them; without this they
    /// survive `deleteWallet()` and resurface in the next wallet's History.
    func resetForWalletBoundary() {
        requests = []
        currentRequestId = nil
        userDefaults.removeObject(forKey: storageKey)
        userDefaults.removeObject(forKey: currentIdKey)
    }

    /// Re-read persisted state after wallet-boundary defaults were rolled back
    /// (failed `installCleanWallet`), so memory matches the restored defaults.
    func reloadFromDefaults() {
        requests = []
        currentRequestId = nil
        load()
    }


    private func persist() {
        do {
            let data = try JSONEncoder().encode(requests)
            userDefaults.set(data, forKey: storageKey)
            userDefaults.set(currentRequestId, forKey: currentIdKey)
        } catch {
            AppLogger.wallet.error("CashuRequestStore persist failed: \(String(describing: error))")
        }
    }

    private func load() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CashuRequest].self, from: data) {
            requests = decoded
        }
        currentRequestId = userDefaults.string(forKey: currentIdKey)
    }
}
