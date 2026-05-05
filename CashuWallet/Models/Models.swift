import Foundation
import CashuDevKit

enum PaymentMethodKind: String, CaseIterable, Codable, Hashable {
    case bolt11
    case bolt12
    case onchain

    static func from(_ cdkMethod: CashuDevKit.PaymentMethod) -> PaymentMethodKind? {
        switch cdkMethod {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        case .custom(let method):
            return method.lowercased() == PaymentMethodKind.onchain.rawValue ? .onchain : nil
        }
    }

    var cdkMethod: CashuDevKit.PaymentMethod {
        switch self {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        case .onchain:
            return .custom(method: rawValue)
        }
    }

    var displayName: String {
        switch self {
        case .bolt11:
            return "BOLT11"
        case .bolt12:
            return "BOLT12"
        case .onchain:
            return "On-chain"
        }
    }

    var symbol: String {
        switch self {
        case .bolt11:
            return "\u{26A1}"
        case .bolt12:
            return "\u{1F517}"
        case .onchain:
            return "\u{20BF}"
        }
    }

    var requestDisplayName: String {
        switch self {
        case .bolt11:
            return "Invoice"
        case .bolt12:
            return "Offer"
        case .onchain:
            return "Address"
        }
    }

    var sortOrder: Int {
        switch self {
        case .bolt11:
            return 0
        case .bolt12:
            return 1
        case .onchain:
            return 2
        }
    }

    var requiresMintAmount: Bool {
        self != .bolt12
    }

    var supportsOptionalMintAmount: Bool {
        self == .bolt12
    }

    var requiresMeltAmount: Bool {
        switch self {
        case .onchain:
            return true
        case .bolt11, .bolt12:
            return false
        }
    }
}

enum PaymentRequestParser {
    static func normalizeLightningRequest(_ request: String) -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let lightningPrefix = "lightning:"

        if trimmedRequest.lowercased().hasPrefix(lightningPrefix) {
            return String(trimmedRequest.dropFirst(lightningPrefix.count))
        }

        return trimmedRequest
    }

    static func normalizeBitcoinRequest(_ request: String) -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "bitcoin:"

        let withoutScheme: String
        if trimmedRequest.lowercased().hasPrefix(prefix) {
            withoutScheme = String(trimmedRequest.dropFirst(prefix.count))
        } else {
            withoutScheme = trimmedRequest
        }

        return withoutScheme.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? withoutScheme
    }

    static func isBitcoinAddress(_ request: String) -> Bool {
        let normalizedRequest = normalizeBitcoinRequest(request).lowercased()
        return normalizedRequest.hasPrefix("bc1")
            || normalizedRequest.hasPrefix("tb1")
            || normalizedRequest.hasPrefix("bcrt1")
            || normalizedRequest.hasPrefix("1")
            || normalizedRequest.hasPrefix("3")
            || normalizedRequest.hasPrefix("2")
            || normalizedRequest.hasPrefix("m")
            || normalizedRequest.hasPrefix("n")
    }

    static func isHumanReadableLightningAddress(_ request: String) -> Bool {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmedRequest.firstIndex(of: "@") else { return false }
        let user = trimmedRequest[trimmedRequest.startIndex..<atIndex]
        let domain = trimmedRequest[trimmedRequest.index(after: atIndex)...]
        return !user.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    static func paymentMethod(for request: String) -> PaymentMethodKind? {
        if isBitcoinAddress(request) {
            return .onchain
        }

        let normalizedRequest = normalizeLightningRequest(request)
        guard !normalizedRequest.isEmpty else { return nil }
        guard let decodedRequest = try? decodeInvoice(invoiceStr: normalizedRequest) else {
            return nil
        }

        switch decodedRequest.paymentType {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        }
    }
}

struct OnchainPaymentObservation: Equatable {
    let txid: String
    let amount: UInt64
    let confirmed: Bool
    let confirmations: Int?

    var statusText: String {
        if let confirmations, confirmations > 0 {
            let suffix = confirmations == 1 ? "" : "s"
            return "Payment confirmed on-chain (\(confirmations) confirmation\(suffix))"
        }

        return confirmed ? "Payment detected on-chain" : "Payment seen in mempool"
    }

    func hasRequiredConfirmations(_ requiredConfirmations: Int?) -> Bool {
        guard confirmed else { return false }
        guard let requiredConfirmations, requiredConfirmations > 0 else {
            return true
        }
        return (confirmations ?? 1) >= requiredConfirmations
    }
}

enum OnchainExplorer {
    private struct ExplorerDescriptor {
        let webBaseURL: String
        let apiBaseURL: String
    }

    private struct ExplorerTransaction: Decodable {
        let txid: String
        let status: ExplorerTransactionStatus
        let vout: [ExplorerTransactionOutput]
    }

    private struct ExplorerBlock: Decodable {
        let height: Int
    }

    private struct ExplorerTransactionStatus: Decodable {
        let confirmed: Bool
        let blockHeight: Int?
        let blockTime: Int?

        private enum CodingKeys: String, CodingKey {
            case confirmed
            case blockHeight = "block_height"
            case blockTime = "block_time"
        }
    }

    private struct ExplorerTransactionOutput: Decodable {
        let scriptpubkeyAddress: String?
        let value: UInt64

        private enum CodingKeys: String, CodingKey {
            case scriptpubkeyAddress = "scriptpubkey_address"
            case value
        }
    }

    static func addressWebURL(for address: String, mintURL: String?) -> URL? {
        guard let descriptor = descriptor(for: address, mintURL: mintURL) else {
            return nil
        }

        let normalizedAddress = PaymentRequestParser.normalizeBitcoinRequest(address)
        return URL(string: "\(descriptor.webBaseURL)/address/\(normalizedAddress)")
    }

    static func transactionWebURL(for txid: String, address: String? = nil, mintURL: String?) -> URL? {
        guard let descriptor = descriptor(for: address, mintURL: mintURL) else {
            return nil
        }

        return URL(string: "\(descriptor.webBaseURL)/tx/\(txid)")
    }

    static func observePayment(
        for address: String,
        mintURL: String?,
        expectedAmount: UInt64,
        createdAfter: Date
    ) async -> OnchainPaymentObservation? {
        guard let descriptor = descriptor(for: address, mintURL: mintURL) else {
            return nil
        }

        let normalizedAddress = PaymentRequestParser.normalizeBitcoinRequest(address)
        guard let url = URL(string: "\(descriptor.apiBaseURL)/address/\(normalizedAddress)/txs") else {
            return nil
        }

        do {
            let request = explorerAPIRequest(url: url)

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                AppLogger.wallet.error("Failed to inspect on-chain address activity: HTTP \(httpResponse.statusCode)")
                return nil
            }

            let transactions = try JSONDecoder().decode([ExplorerTransaction].self, from: data)
            let earliestBlockTime = Int(createdAfter.timeIntervalSince1970)
            let normalizedAddressLowercased = normalizedAddress.lowercased()
            let tipHeight = await currentTipHeight(using: descriptor)

            for transaction in transactions {
                let matchingAmount = transaction.vout
                    .filter { $0.scriptpubkeyAddress?.lowercased() == normalizedAddressLowercased }
                    .map(\.value)
                    .max() ?? 0

                guard matchingAmount >= expectedAmount else {
                    continue
                }

                let status = await freshStatusIfNeeded(for: transaction, using: descriptor)

                if let blockTime = status.blockTime, blockTime < earliestBlockTime {
                    continue
                }

                return OnchainPaymentObservation(
                    txid: transaction.txid,
                    amount: matchingAmount,
                    confirmed: status.confirmed,
                    confirmations: confirmations(
                        for: status,
                        tipHeight: tipHeight
                    )
                )
            }
        } catch {
            AppLogger.wallet.error("Failed to inspect on-chain address activity: \(error)")
        }

        return nil
    }

    private static func descriptor(for address: String?, mintURL: String?) -> ExplorerDescriptor? {
        let mintHost = mintURL.flatMap { URL(string: $0)?.host?.lowercased() }
        if mintHost == "onchain.cashudevkit.org" {
            return ExplorerDescriptor(
                webBaseURL: "https://mutinynet.com",
                apiBaseURL: "https://mutinynet.com/api"
            )
        }

        let normalizedAddress = address.map(PaymentRequestParser.normalizeBitcoinRequest)?.lowercased() ?? ""

        if normalizedAddress.hasPrefix("bc1")
            || normalizedAddress.hasPrefix("1")
            || normalizedAddress.hasPrefix("3") {
            return ExplorerDescriptor(
                webBaseURL: "https://mempool.space",
                apiBaseURL: "https://mempool.space/api"
            )
        }

        if normalizedAddress.hasPrefix("tb1")
            || normalizedAddress.hasPrefix("m")
            || normalizedAddress.hasPrefix("n")
            || normalizedAddress.hasPrefix("2") {
            return ExplorerDescriptor(
                webBaseURL: "https://mempool.space/signet",
                apiBaseURL: "https://mempool.space/signet/api"
            )
        }

        guard mintHost != nil else {
            return nil
        }

        return ExplorerDescriptor(
            webBaseURL: "https://mempool.space/signet",
            apiBaseURL: "https://mempool.space/signet/api"
        )
    }

    private static func currentTipHeight(using descriptor: ExplorerDescriptor) async -> Int? {
        if let url = URL(string: "\(descriptor.apiBaseURL)/blocks/tip/height"),
           let tipHeight = await tipHeight(from: url) {
            return tipHeight
        }

        guard let url = URL(string: "\(descriptor.apiBaseURL)/blocks") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: explorerAPIRequest(url: url))
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return nil
            }

            let blocks = try JSONDecoder().decode([ExplorerBlock].self, from: data)
            return blocks.map(\.height).max()
        } catch {
            AppLogger.wallet.error("Failed to inspect on-chain tip height: \(error)")
            return nil
        }
    }

    private static func tipHeight(from url: URL) async -> Int? {
        do {
            let (data, response) = try await URLSession.shared.data(for: explorerAPIRequest(url: url))
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return nil
            }

            return String(data: data, encoding: .utf8)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap(Int.init)
        } catch {
            return nil
        }
    }

    private static func freshStatusIfNeeded(
        for transaction: ExplorerTransaction,
        using descriptor: ExplorerDescriptor
    ) async -> ExplorerTransactionStatus {
        guard transaction.status.confirmed,
              transaction.status.blockHeight == nil,
              let url = URL(string: "\(descriptor.apiBaseURL)/tx/\(transaction.txid)/status") else {
            return transaction.status
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: explorerAPIRequest(url: url))
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return transaction.status
            }

            return try JSONDecoder().decode(ExplorerTransactionStatus.self, from: data)
        } catch {
            return transaction.status
        }
    }

    private static func explorerAPIRequest(url: URL) -> URLRequest {
        var request = URLRequest(
            url: cacheBustedURL(url),
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 10
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private static func cacheBustedURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(
            URLQueryItem(
                name: "_",
                value: String(Int(Date().timeIntervalSince1970 * 1_000))
            )
        )
        components.queryItems = queryItems

        return components.url ?? url
    }

    private static func confirmations(
        for status: ExplorerTransactionStatus,
        tipHeight: Int?
    ) -> Int? {
        guard status.confirmed else {
            return nil
        }

        guard let blockHeight = status.blockHeight,
              let tipHeight,
              tipHeight >= blockHeight else {
            return 1
        }

        return tipHeight - blockHeight + 1
    }
}

/// Mint information
struct MintInfo: Identifiable, Equatable, Codable {
    var id: String { url }
    let url: String
    var name: String
    var description: String?
    var isActive: Bool
    var balance: UInt64
    
    /// Icon URL (if available from mint info)
    var iconUrl: String?
    
    /// Supported units
    var units: [String] = ["sat"]

    /// Supported NUT-04 payment methods for receiving
    var supportedMintMethods: [PaymentMethodKind] = [.bolt11]

    /// Supported NUT-05 payment methods for sending
    var supportedMeltMethods: [PaymentMethodKind] = [.bolt11]

    /// Required on-chain confirmations for minting, if advertised by the mint
    var onchainMintConfirmations: Int? = nil
    
    /// Last updated timestamp
    var lastUpdated: Date = Date()
}

extension MintInfo {
    private enum CodingKeys: String, CodingKey {
        case url
        case name
        case description
        case isActive
        case balance
        case iconUrl
        case units
        case supportedMintMethods
        case supportedMeltMethods
        case onchainMintConfirmations
        case lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Mint"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        balance = try container.decodeIfPresent(UInt64.self, forKey: .balance) ?? 0
        iconUrl = try container.decodeIfPresent(String.self, forKey: .iconUrl)
        units = try container.decodeIfPresent([String].self, forKey: .units) ?? ["sat"]
        supportedMintMethods = try container.decodeIfPresent([PaymentMethodKind].self, forKey: .supportedMintMethods) ?? [.bolt11]
        supportedMeltMethods = try container.decodeIfPresent([PaymentMethodKind].self, forKey: .supportedMeltMethods) ?? [.bolt11]
        onchainMintConfirmations = try container.decodeIfPresent(Int.self, forKey: .onchainMintConfirmations)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(balance, forKey: .balance)
        try container.encodeIfPresent(iconUrl, forKey: .iconUrl)
        try container.encode(units, forKey: .units)
        try container.encode(supportedMintMethods, forKey: .supportedMintMethods)
        try container.encode(supportedMeltMethods, forKey: .supportedMeltMethods)
        try container.encodeIfPresent(onchainMintConfirmations, forKey: .onchainMintConfirmations)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}

// Extension for notifications
extension Notification.Name {
    static let cashuTokenReceived = Notification.Name("cashuTokenReceived")
    static let cashuTokenClaimed = Notification.Name("cashuTokenClaimed")
    static let cashuTransactionsUpdated = Notification.Name("cashuTransactionsUpdated")
}

/// Mint quote information
struct MintQuoteInfo: Identifiable {
    let id: String
    let request: String  // Payment request (BOLT11 invoice, BOLT12 offer, or on-chain address)
    let amount: UInt64?
    let paymentMethod: PaymentMethodKind
    var state: MintQuoteState
    let expiry: UInt64?
    
    var isExpired: Bool {
        guard let expiry = expiry, expiry > 0 else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Melt quote information
struct MeltQuoteInfo: Identifiable {

    let id: String
    let amount: UInt64
    let feeReserve: UInt64
    let paymentMethod: PaymentMethodKind
    var state: MeltQuoteState
    let expiry: UInt64?
    
    var totalAmount: UInt64 {
        amount + feeReserve
    }
    
    var isExpired: Bool {
        guard let expiry = expiry, expiry > 0 else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Wallet transaction
struct WalletTransaction: Identifiable {
    let id: String
    let amount: UInt64
    let type: TransactionType
    let kind: TransactionKind
    let date: Date
    let memo: String?
    var status: TransactionStatus
    var statusNote: String? = nil
    
    /// Associated mint URL
    var mintUrl: String?
    
    /// Payment proof (preimage for Lightning, txid for on-chain when exposed)
    var preimage: String?
    
    /// Ecash token string (for outgoing pending transactions)
    var token: String?
    
    /// Payment request string (BOLT11 invoice, BOLT12 offer, or on-chain address)
    var invoice: String?
    
    /// Fee paid for the transaction (in sats)
    var fee: UInt64 = 0
    
    /// Whether this is from pending storage vs. completed transactions
    var isPendingToken: Bool = false

    var displayStatusText: String {
        if status == .pending {
            return statusNote ?? status.displayText
        }

        return status.displayText
    }
    
    enum TransactionType {
        case incoming   // Mint or receive
        case outgoing   // Send or melt
        
        var icon: String {
            switch self {
            case .incoming: return "arrow.down.circle.fill"
            case .outgoing: return "arrow.up.circle.fill"
            }
        }
    }
    
    /// Kind of transaction - distinguishes between Ecash and Lightning
    enum TransactionKind {
        case ecash      // Ecash token send/receive
        case lightning  // Lightning invoice mint/melt
        case onchain    // On-chain address mint/melt
        
        var displayName: String {
            switch self {
            case .ecash: return "Ecash"
            case .lightning: return "Lightning"
            case .onchain: return "On-chain"
            }
        }
    }
    
    enum TransactionStatus {
        case pending
        case completed
        case failed
        
        var displayText: String {
            switch self {
            case .pending: return "Pending"
            case .completed: return "Completed"
            case .failed: return "Failed"
            }
        }
    }
}

/// Result of a send tokens operation - includes token string and fee paid
struct SendTokenResult {
    let token: String
    let fee: UInt64
}

/// Pending token entry - stored when user sends ecash
struct PendingToken: Codable, Identifiable {
    var id: String { tokenId }
    let tokenId: String
    let token: String
    let amount: UInt64
    let fee: UInt64
    let date: Date
    let mintUrl: String
    let memo: String?
}

/// Pending receive token entry - stored when user chooses "Receive Later"
struct PendingReceiveToken: Codable, Identifiable {
    var id: String { tokenId }
    let tokenId: String
    let token: String
    let amount: UInt64
    let date: Date
    let mintUrl: String
}

/// Claimed token entry - stored when a sent token is claimed by recipient
struct ClaimedToken: Codable, Identifiable {
    var id: String { tokenId }
    let tokenId: String
    let token: String
    let amount: UInt64
    let fee: UInt64
    let date: Date
    let mintUrl: String
    let memo: String?
    let claimedDate: Date
}

/// Result of restoring proofs from a single mint via NUT-09
struct RestoreMintResult: Identifiable {
    var id: String { mintUrl }
    let mintUrl: String
    let mintName: String
    let spent: UInt64
    let unspent: UInt64
    let pending: UInt64

    var totalRecovered: UInt64 { unspent + pending }
}

/// Token parsed information
struct TokenInfo {
    let amount: UInt64
    let mint: String
    let unit: String
    let memo: String?
    let proofCount: Int
    
    /// Parse a cashu token string
    static func parse(_ tokenString: String) -> TokenInfo? {
        TokenParser.tokenInfo(from: tokenString)
    }
}

// MARK: - Data Extensions

import CryptoKit

extension Data {
    /// SHA256 hash of the data
    func sha256() -> Data {
        let hash = SHA256.hash(data: self)
        return Data(hash)
    }
}
