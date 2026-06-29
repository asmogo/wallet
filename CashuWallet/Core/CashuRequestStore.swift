import Foundation
import SwiftUI

@MainActor
class CashuRequestStore: ObservableObject {
    static let shared = CashuRequestStore()

    @Published private(set) var requests: [CashuRequest] = []
    @Published var currentRequestId: String?

    private let storageKey = "cashuRequests.v1"
    private let currentIdKey = "cashuRequests.currentId.v1"

    var currentRequest: CashuRequest? {
        guard let id = currentRequestId else { return nil }
        return requests.first(where: { $0.id == id })
    }

    private init() {
        load()
    }

    /// Rail-generic intent creation. `createNew` below is the ecash-specific
    /// wrapper kept for existing call sites; the quote-backed rails go through
    /// `upsertQuoteIntent` so re-opening a reusable offer never duplicates a row.
    @discardableResult
    func create(
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
        amount: UInt64? = nil,
        unit: String = "sat",
        mints: [String] = [],
        memo: String? = nil,
        encoded: String
    ) -> CashuRequest {
        create(
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


    private func persist() {
        do {
            let data = try JSONEncoder().encode(requests)
            UserDefaults.standard.set(data, forKey: storageKey)
            UserDefaults.standard.set(currentRequestId, forKey: currentIdKey)
        } catch {
            AppLogger.wallet.error("CashuRequestStore persist failed: \(String(describing: error))")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CashuRequest].self, from: data) {
            requests = decoded
        }
        currentRequestId = UserDefaults.standard.string(forKey: currentIdKey)
    }
}
