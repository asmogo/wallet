import Foundation

struct MintQuoteInfo: Identifiable {
    let id: String
    let request: String  // Payment request (BOLT11 invoice, BOLT12 offer, or on-chain address)
    let amount: UInt64?
    /// Whether the quote was created without an amount. This cannot be derived
    /// from `amount`: NUT-25 reports the cumulative paid amount after the first
    /// payment, but the underlying BOLT12 offer remains amountless and reusable.
    let isAmountless: Bool
    let paymentMethod: PaymentMethodKind
    var state: MintQuoteState
    let expiry: UInt64?
    /// First-seen timestamp for the offer. Set only for reusable (amountless
    /// BOLT12) offers, which carry no creation field in the CDK quote — see
    /// `MintQuoteCreatedAtStore`. nil for every other rail.
    let createdAt: Date?

    /// The unit the quote mints into ("sat", "eur", …). `amount` is denominated
    /// in this unit's base units. Defaults to "sat" for older/sat quotes.
    var unit: String = "sat"

    /// Mint wallet that owns the quote. Quote follow-up work must use this
    /// instead of mutable active-mint state.
    var mintURL: String? = nil

    /// NUT-25's durable settlement ledger. A reusable offer is fully caught up
    /// when these values are equal; their difference is the only amount the
    /// wallet is allowed to mint.
    var amountPaid: UInt64 = 0
    var amountIssued: UInt64 = 0

    var mintableAmount: UInt64 {
        amountPaid > amountIssued ? amountPaid - amountIssued : 0
    }

    var hasSettledPayment: Bool {
        amountPaid > 0 && amountIssued >= amountPaid
    }
    /// Payer-facing description embedded in a BOLT12 offer. CDK never returns
    /// it (write-only on `mintQuote`), so this is populated from the locally
    /// stored quote-intent memo (`CashuRequest.memo`) — nil everywhere else.
    var description: String? = nil

    var isExpired: Bool {
        guard let expiry = expiry, expiry > 0 else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Counter-verified result of reconciling one persisted mint quote. A
/// successful mint response is combined with a follow-up quote check so an
/// ambiguous network failure cannot lose a payment or mint it twice.
struct MintQuoteReconciliationResult {
    let quote: MintQuoteInfo
    let newlyIssued: UInt64
    let hadOutstandingPayment: Bool
    let retryStatus: MintQuoteRetryStatus

    var remainingAmount: UInt64 { quote.mintableAmount }
    var hasSettledPayment: Bool { quote.hasSettledPayment }

    init(
        observed: MintQuoteInfo,
        mintedAmount: UInt64 = 0,
        verified: MintQuoteInfo? = nil,
        issuedBeforeCheck: UInt64? = nil,
        retryStatus: MintQuoteRetryStatus = MintQuoteRetryStatus()
    ) {
        var reconciled = verified ?? observed
        reconciled.amountPaid = max(reconciled.amountPaid, observed.amountPaid)

        let inferredIssued: UInt64
        let (sum, overflow) = observed.amountIssued.addingReportingOverflow(mintedAmount)
        inferredIssued = overflow ? UInt64.max : sum
        reconciled.amountIssued = max(reconciled.amountIssued, inferredIssued)

        if reconciled.amountPaid > 0,
           reconciled.amountIssued >= reconciled.amountPaid {
            reconciled.state = .issued
        } else if reconciled.amountPaid > reconciled.amountIssued {
            reconciled.state = .paid
        }

        // A quote status check may itself finish CDK's interrupted issue saga.
        let baseline = issuedBeforeCheck ?? observed.amountIssued
        let verifiedAdvance = reconciled.amountIssued > baseline
            ? reconciled.amountIssued - baseline
            : 0
        quote = reconciled
        newlyIssued = max(mintedAmount, verifiedAdvance)
        hadOutstandingPayment = observed.amountPaid > observed.amountIssued
        self.retryStatus = retryStatus
    }
}

/// What the wallet can honestly promise after a paid quote fails to issue.
enum MintQuoteRetryState: String, Codable, Equatable {
    case none
    case retryScheduled
    case needsAttention
}

struct MintQuoteRetryStatus: Equatable {
    var state: MintQuoteRetryState = .none
    var nextRetryAt: Date?
    var failureCount = 0
}

/// Durable maintenance metadata. CDK's paid/issued counters remain the money
/// ledger; this record only bounds when the app checks again and preserves the
/// truthful retry state across process restarts.
struct MintQuoteScheduleRecord: Codable, Equatable {
    var firstObservedAt: TimeInterval
    var lastAttemptAt: TimeInterval?
    var nextAttemptAt: TimeInterval = 0
    var consecutiveFailures = 0
    var hadOutstandingPayment = false
    var isReusable = false
    var isComplete = false
}

enum MintQuoteSchedulePolicy {
    static let passiveBatchLimit = 2
    static let forcedBatchLimit = 20
    private static let recentQuoteWindow: TimeInterval = 2 * 60
    private static let recentQuoteInterval: TimeInterval = 10
    private static let idleQuoteInterval: TimeInterval = 60
    private static let needsAttentionFailureCount = 4
    private static let failureDelays: [TimeInterval] = [5, 15, 30, 60, 5 * 60]

    struct Selection {
        let quoteIDs: [String]
        let records: [String: MintQuoteScheduleRecord]
    }

    static func select(
        quoteIDs: Set<String>,
        existing: [String: MintQuoteScheduleRecord],
        now: Date,
        force: Bool,
        unsettledOnchainQuoteIDs: Set<String> = []
    ) -> Selection {
        let nowValue = now.timeIntervalSince1970
        var records = existing.filter { quoteIDs.contains($0.key) }
        for quoteID in quoteIDs where !quoteID.isEmpty && records[quoteID] == nil {
            records[quoteID] = MintQuoteScheduleRecord(firstObservedAt: nowValue)
        }
        // Older schedules treated expiry as terminal even while an on-chain
        // deposit was waiting for confirmations. The durable quote reopens it.
        for quoteID in unsettledOnchainQuoteIDs where records[quoteID]?.isComplete == true {
            records[quoteID]?.isComplete = false
            records[quoteID]?.nextAttemptAt = 0
        }

        let limit = force ? forcedBatchLimit : passiveBatchLimit
        let selected = quoteIDs
            .filter { quoteID in
                guard let record = records[quoteID] else { return false }
                return !record.isComplete && (force || record.nextAttemptAt <= nowValue)
            }
            .sorted { lhs, rhs in
                guard let left = records[lhs], let right = records[rhs] else {
                    return lhs < rhs
                }
                let leftAttempt = left.lastAttemptAt ?? -TimeInterval.greatestFiniteMagnitude
                let rightAttempt = right.lastAttemptAt ?? -TimeInterval.greatestFiniteMagnitude
                if leftAttempt != rightAttempt { return leftAttempt < rightAttempt }
                if left.nextAttemptAt != right.nextAttemptAt {
                    return left.nextAttemptAt < right.nextAttemptAt
                }
                return lhs < rhs
            }
            .prefix(limit)

        for quoteID in selected {
            guard var record = records[quoteID] else { continue }
            record.lastAttemptAt = nowValue
            if record.consecutiveFailures == 0 {
                record.nextAttemptAt = nowValue + (failureDelays.first ?? 5)
            }
            records[quoteID] = record
        }
        return Selection(quoteIDs: Array(selected), records: records)
    }

    static func observed(
        previous: MintQuoteScheduleRecord?,
        quote: MintQuoteInfo,
        now: Date
    ) -> MintQuoteScheduleRecord {
        let nowValue = now.timeIntervalSince1970
        var record = previous ?? MintQuoteScheduleRecord(firstObservedAt: nowValue)
        let reusable = quote.paymentMethod == .bolt12
        let expired = quote.expiry.map { $0 > 0 && UInt64(nowValue) >= $0 } ?? false
        // On-chain expiry stops new deposits, not confirmation of deposits
        // already seen by the mint. Zero paid counters cannot prove completion.
        let expiredInvoice = quote.paymentMethod == .bolt11 && expired
        let complete = !reusable && (expiredInvoice || quote.state == .issued || quote.hasSettledPayment)
        let age = max(0, nowValue - record.firstObservedAt)
        let interval = age < recentQuoteWindow ? recentQuoteInterval : idleQuoteInterval

        record.lastAttemptAt = nowValue
        record.nextAttemptAt = complete ? .greatestFiniteMagnitude : nowValue + interval
        record.consecutiveFailures = 0
        record.hadOutstandingPayment = false
        record.isReusable = reusable
        record.isComplete = complete
        return record
    }

    static func failed(
        previous: MintQuoteScheduleRecord?,
        now: Date,
        hadOutstandingPayment: Bool,
        isReusable: Bool
    ) -> MintQuoteScheduleRecord {
        let nowValue = now.timeIntervalSince1970
        var record = previous ?? MintQuoteScheduleRecord(firstObservedAt: nowValue)
        let failures = record.consecutiveFailures == Int.max
            ? Int.max
            : record.consecutiveFailures + 1
        let delayIndex = min(max(0, failures - 1), failureDelays.count - 1)

        record.lastAttemptAt = nowValue
        record.nextAttemptAt = nowValue + failureDelays[delayIndex]
        record.consecutiveFailures = failures
        record.hadOutstandingPayment = hadOutstandingPayment || record.hadOutstandingPayment
        record.isReusable = isReusable || record.isReusable
        record.isComplete = false
        return record
    }

    /// Receive polling can run more often than maintenance, but shares its
    /// failure backoff. Explicit retry and refresh actions bypass the deadline.
    static func shouldAttempt(
        record: MintQuoteScheduleRecord?,
        now: Date,
        force: Bool
    ) -> Bool {
        guard !force, let record, record.consecutiveFailures > 0 else { return true }
        return record.nextAttemptAt <= now.timeIntervalSince1970
    }

    static func retryStatus(for record: MintQuoteScheduleRecord) -> MintQuoteRetryStatus {
        guard record.hadOutstandingPayment, record.consecutiveFailures > 0 else {
            return MintQuoteRetryStatus()
        }
        return MintQuoteRetryStatus(
            state: record.consecutiveFailures >= needsAttentionFailureCount
                ? .needsAttention
                : .retryScheduled,
            nextRetryAt: Date(timeIntervalSince1970: record.nextAttemptAt),
            failureCount: record.consecutiveFailures
        )
    }
}

/// Remembers when each reusable (amountless BOLT12) offer was first materialized.
/// The CDK `MintQuote` has no creation timestamp, and the same offer is reused
/// across opens via `LightningService.existingAmountlessOffer(mintURL:unit:)`.
/// Without a stable record, the "Created" row would drift to "now" on every
/// visit. Keyed by quote id; stamped once, read back forever after.
enum MintQuoteCreatedAtStore {
    private static let storageKey = "mintQuoteCreatedAt.v1"

    /// Returns the stored date for `quoteId`, stamping `date` first if absent.
    @discardableResult
    static func recordIfAbsent(quoteId: String, date: Date) -> Date {
        var map = load()
        if let existing = map[quoteId] { return existing }
        map[quoteId] = date
        save(map)
        return date
    }

    static func date(for quoteId: String) -> Date? { load()[quoteId] }

    private static func load() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return map
    }

    private static func save(_ map: [String: Date]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

/// Melt quote information
struct MeltQuoteInfo: Identifiable {

    let id: String
    let mintUrl: String
    let amount: UInt64
    let feeReserve: UInt64
    let paymentMethod: PaymentMethodKind
    var state: MeltQuoteState
    let expiry: UInt64?
    
    var totalAmount: UInt64 {
        let total = amount.addingReportingOverflow(feeReserve)
        return total.overflow ? UInt64.max : total.partialValue
    }
    
    var isExpired: Bool {
        guard let expiry = expiry, expiry > 0 else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Final result for a completed melt payment.
struct MeltPaymentResult {
    /// How the mint answered the melt confirmation. `.settled` is final (fee and
    /// preimage are real). `.pending` means the mint accepted the payment for
    /// asynchronous NUT-05 processing — common for on-chain melts — so `preimage`
    /// is nil and `feePaid` is still the quote's fee reserve, not the actual fee.
    enum Settlement {
        case settled
        case pending
    }

    let preimage: String?
    let amount: UInt64
    let feePaid: UInt64
    let mintUrl: String
    var settlement: Settlement = .settled
}

/// Wallet transaction
