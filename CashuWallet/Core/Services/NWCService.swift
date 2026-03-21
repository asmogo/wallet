import Foundation
import CashuDevKit

struct NWCOperationRecord: Codable, Identifiable, Hashable {
    enum Direction: String, Codable {
        case incoming
        case outgoing
    }

    enum State: String, Codable {
        case pending
        case settled
        case failed
    }

    let id: UUID
    let direction: Direction
    var state: State
    let invoice: String
    let description: String?
    var amountMsat: UInt64
    var feesPaidMsat: UInt64?
    let createdAt: Date
    var settledAt: Date?
    var expiresAt: Date?
    var quoteId: String?
    var mintUrl: String?
    var preimage: String?

    init(
        id: UUID = UUID(),
        direction: Direction,
        state: State,
        invoice: String,
        description: String?,
        amountMsat: UInt64,
        feesPaidMsat: UInt64?,
        createdAt: Date,
        settledAt: Date?,
        expiresAt: Date?,
        quoteId: String?,
        mintUrl: String?,
        preimage: String?
    ) {
        self.id = id
        self.direction = direction
        self.state = state
        self.invoice = invoice
        self.description = description
        self.amountMsat = amountMsat
        self.feesPaidMsat = feesPaidMsat
        self.createdAt = createdAt
        self.settledAt = settledAt
        self.expiresAt = expiresAt
        self.quoteId = quoteId
        self.mintUrl = mintUrl
        self.preimage = preimage
    }
}

@MainActor
final class NWCService: ObservableObject {
    static let shared = NWCService()

    @Published private(set) var isListening = false
    @Published var lastError: String?
    @Published private(set) var operationRecords: [NWCOperationRecord] = []

    let supportedMethods = [
        "pay_invoice",
        "make_invoice",
        "get_balance",
        "get_info",
        "list_transactions",
        "lookup_invoice",
    ]

    private let recordsKey = "nwc.operationRecords"
    private let seenCommandIdsKey = "nwc.seenCommandIds"
    private let seenCommandsUntilKey = "nwc.seenCommandsUntil"

    private var subscription: NostrRelaySubscription?
    private var pendingInvoiceMonitorTask: Task<Void, Never>?
    private var blocking = false
    private var seenCommandIds: [String] = []

    private var walletRepositoryProvider: (() -> WalletRepository?)?
    private var currentMintUrlProvider: (() -> String?)?
    private var refreshWalletState: (() async -> Void)?
    private var balanceProvider: (() -> UInt64)?
    private var transactionsProvider: (() -> [WalletTransaction])?

    private init() {
        loadPersistedState()
    }

    func configure(
        walletRepositoryProvider: @escaping () -> WalletRepository?,
        currentMintUrlProvider: @escaping () -> String?,
        balanceProvider: @escaping () -> UInt64,
        transactionsProvider: @escaping () -> [WalletTransaction],
        refreshWalletState: @escaping () async -> Void
    ) {
        self.walletRepositoryProvider = walletRepositoryProvider
        self.currentMintUrlProvider = currentMintUrlProvider
        self.balanceProvider = balanceProvider
        self.transactionsProvider = transactionsProvider
        self.refreshWalletState = refreshWalletState
        startPendingInvoiceMonitorIfNeeded()
    }

    func applySettings() async {
        stopListening()

        let settings = SettingsManager.shared
        let hasConnection = settings.nwcConnections.first != nil || settings.generateNWCConnection() != nil
        guard settings.enableNWC,
              settings.useWebsockets,
              hasConnection,
              !settings.nostrRelays.isEmpty else {
            return
        }

        await publishInfoEventIfNeeded()
        startListening(connection: settings.nwcConnections.first!, relays: settings.nostrRelays)
        startPendingInvoiceMonitorIfNeeded()
    }

    func reset() {
        stopListening()
        pendingInvoiceMonitorTask?.cancel()
        pendingInvoiceMonitorTask = nil
        operationRecords = []
        seenCommandIds = []
        lastError = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: recordsKey)
        defaults.removeObject(forKey: seenCommandIdsKey)
        defaults.removeObject(forKey: seenCommandsUntilKey)
    }

    private func publishInfoEventIfNeeded() async {
        guard let connection = SettingsManager.shared.nwcConnections.first else { return }

        do {
            let contentObject: [String: JSONValue] = [
                "notifications": .array([]),
                "encryption": .array([.string(NostrEncryptionMode.nip04.rawValue), .string(NostrEncryptionMode.nip44v2.rawValue)]),
            ]
            let content = try encodeJSONObject(contentObject)
            let event = try NostrCrypto.signEvent(
                privateKeyHex: connection.walletPrivateKey,
                kind: 13194,
                tags: [["p", connection.connectionPublicKey]],
                content: content
            )
            try await NostrRelayClient.publish(event: event, to: SettingsManager.shared.nostrRelays)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startListening(connection: NWCConnection, relays: [String]) {
        let filter = NostrFilter(
            kinds: [23194],
            authors: [connection.connectionPublicKey],
            since: max(seenCommandsUntil() - 60, Int(Date().timeIntervalSince1970) - 60),
            limit: nil,
            tags: ["p": [connection.walletPublicKey]]
        )

        let subscription = NostrRelaySubscription(relays: relays, filter: filter) { [weak self] event in
            await self?.handleRequestEvent(event)
        }
        self.subscription = subscription
        self.isListening = true
        subscription.start()
    }

    private func stopListening() {
        subscription?.stop()
        subscription = nil
        isListening = false
    }

    private func handleRequestEvent(_ event: NostrRelayEvent) async {
        guard NostrCrypto.verifyEvent(event) else { return }
        guard !seenCommandIds.contains(event.id) else { return }
        guard let connection = SettingsManager.shared.nwcConnections.first,
              event.pubkey == connection.connectionPublicKey else {
            return
        }

        registerSeenCommand(event)

        let mode = encryptionMode(for: event)
        do {
            let plaintext: String
            switch mode {
            case .nip04:
                plaintext = try NostrCrypto.nip04Decrypt(payload: event.content, privateKeyHex: connection.walletPrivateKey, publicKeyHex: event.pubkey)
            case .nip44v2:
                plaintext = try NostrCrypto.nip44Decrypt(payload: event.content, privateKeyHex: connection.walletPrivateKey, publicKeyHex: event.pubkey)
            }

            let command = try JSONDecoder().decode(NWCCommand.self, from: Data(plaintext.utf8))
            let response = await handleCommand(command)
            try await reply(with: response, to: event, connection: connection, mode: mode)
        } catch {
            lastError = error.localizedDescription
            let errorPayload = nwcError(resultType: "internal", code: "INTERNAL", message: error.localizedDescription)
            try? await reply(with: errorPayload, to: event, connection: connection, mode: mode)
        }
    }

    private func handleCommand(_ command: NWCCommand) async -> [String: JSONValue] {
        switch command.method {
        case "get_info":
            return handleGetInfo()
        case "get_balance":
            return handleGetBalance()
        case "pay_invoice":
            if blocking {
                return nwcError(resultType: command.method, code: "INTERNAL", message: "Already processing a payment.")
            }
            blocking = true
            defer { blocking = false }
            return await handlePayInvoice(command)
        case "make_invoice":
            return await handleMakeInvoice(command)
        case "list_transactions":
            return handleListTransactions(command)
        case "lookup_invoice":
            return handleLookupInvoice(command)
        default:
            return nwcError(resultType: command.method, code: "NOT_IMPLEMENTED", message: "Method not supported")
        }
    }

    private func handleGetInfo() -> [String: JSONValue] {
        guard let connection = SettingsManager.shared.nwcConnections.first else {
            return nwcError(resultType: "get_info", code: "INTERNAL", message: "NWC connection not configured")
        }

        return [
            "result_type": .string("get_info"),
            "result": .object([
                "alias": .string("CashuWallet"),
                "color": .string("#00E676"),
                "pubkey": .string(connection.walletPublicKey),
                "network": .string("mainnet"),
                "block_height": .number(1),
                "block_hash": .string("cashu-wallet"),
                "methods": .array(supportedMethods.map(JSONValue.string)),
            ]),
        ]
    }

    private func handleGetBalance() -> [String: JSONValue] {
        let balanceMsat = Double(balanceProvider?() ?? 0) * 1000
        return [
            "result_type": .string("get_balance"),
            "result": .object(["balance": .number(balanceMsat)]),
        ]
    }

    private func handlePayInvoice(_ command: NWCCommand) async -> [String: JSONValue] {
        guard let invoice = command.params?["invoice"]?.stringValue, !invoice.isEmpty else {
            return nwcError(resultType: command.method, code: "OTHER", message: "invoice is required")
        }
        guard let connection = SettingsManager.shared.nwcConnections.first else {
            return nwcError(resultType: command.method, code: "INTERNAL", message: "NWC connection not configured")
        }
        guard let walletRepository = walletRepositoryProvider?(),
              let currentMintUrl = currentMintUrlProvider?() else {
            return nwcError(resultType: command.method, code: "INTERNAL", message: "Wallet is not ready")
        }

        do {
            let normalizedInvoice = normalizeLightningRequest(invoice)
            let wallet = try await walletRepository.getWallet(mintUrl: MintUrl(url: currentMintUrl), unit: .sat)
            let paymentMethod = try paymentMethod(for: normalizedInvoice)
            let quote = try await wallet.meltQuote(method: paymentMethod, request: normalizedInvoice, options: nil, extra: nil)
            let maxSpend = quote.amount.value + quote.feeReserve.value
            guard Int(maxSpend) <= connection.allowanceLeft else {
                return nwcError(resultType: command.method, code: "QUOTA_EXCEEDED", message: "Your quota has exceeded")
            }

            let preparedMelt = try await wallet.prepareMelt(quoteId: quote.id)
            let result = try await preparedMelt.confirm()
            let spent = Int(result.amount.value + result.feePaid.value)
            SettingsManager.shared.updateNWCAllowance(connectionId: connection.id, allowanceLeft: connection.allowanceLeft - spent)

            let decodedInvoice = try? decodeInvoice(invoiceStr: normalizedInvoice)
            let record = NWCOperationRecord(
                direction: .outgoing,
                state: .settled,
                invoice: normalizedInvoice,
                description: decodedInvoice?.description,
                amountMsat: result.amount.value * 1000,
                feesPaidMsat: result.feePaid.value * 1000,
                createdAt: Date(),
                settledAt: Date(),
                expiresAt: decodedInvoice?.expiry.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                quoteId: nil,
                mintUrl: currentMintUrl,
                preimage: result.preimage
            )
            upsertRecord(record)
            await refreshWalletState?()

            var response: [String: JSONValue] = [
                "result_type": .string(command.method),
                "result": .object([:]),
            ]
            if let preimage = result.preimage {
                response["result"] = .object(["preimage": .string(preimage)])
            }
            return response
        } catch {
            return nwcError(resultType: command.method, code: "INTERNAL", message: "Could not pay invoice")
        }
    }

    private func handleMakeInvoice(_ command: NWCCommand) async -> [String: JSONValue] {
        guard let amountMsat = command.params?["amount"]?.uint64Value, amountMsat >= 1000 else {
            return nwcError(resultType: command.method, code: "OTHER", message: "amount must be >= 1000 msat")
        }
        guard let walletRepository = walletRepositoryProvider?(),
              let currentMintUrl = currentMintUrlProvider?() else {
            return nwcError(resultType: command.method, code: "INTERNAL", message: "Wallet is not ready")
        }

        let amountSat = amountMsat / 1000
        let description = command.params?["description"]?.stringValue
        do {
            let wallet = try await walletRepository.getWallet(mintUrl: MintUrl(url: currentMintUrl), unit: .sat)
            let quote = try await wallet.mintQuote(paymentMethod: .bolt11, amount: Amount(value: amountSat), description: description, extra: nil)
            let record = NWCOperationRecord(
                direction: .incoming,
                state: .pending,
                invoice: quote.request,
                description: description,
                amountMsat: amountSat * 1000,
                feesPaidMsat: nil,
                createdAt: Date(),
                settledAt: nil,
                expiresAt: Date(timeIntervalSince1970: TimeInterval(quote.expiry)),
                quoteId: quote.id,
                mintUrl: currentMintUrl,
                preimage: nil
            )
            upsertRecord(record)
            startPendingInvoiceMonitorIfNeeded()

            return [
                "result_type": .string(command.method),
                "result": .object([
                    "type": .string("incoming"),
                    "invoice": .string(quote.request),
                    "description": description.map(JSONValue.string) ?? .null,
                    "amount": .number(Double(amountMsat)),
                    "created_at": .number(Double(Int(Date().timeIntervalSince1970))),
                    "expires_at": .number(Double(Int(quote.expiry))),
                ]),
            ]
        } catch {
            return nwcError(resultType: command.method, code: "INTERNAL", message: "failed to request mint invoice")
        }
    }

    private func handleListTransactions(_ command: NWCCommand) -> [String: JSONValue] {
        let from = command.params?["from"]?.intValue ?? 0
        let until = command.params?["until"]?.intValue ?? Int(Date().timeIntervalSince1970)
        let limit = max(1, command.params?["limit"]?.intValue ?? 10)
        let offset = max(0, command.params?["offset"]?.intValue ?? 0)
        let unpaidOnly = command.params?["unpaid"]?.boolValue ?? false
        let type = command.params?["type"]?.stringValue

        let combined = combinedTransactions()
            .filter { transaction in
                let createdAt = Int(transaction.createdAt.timeIntervalSince1970)
                if createdAt < from || createdAt > until { return false }
                if unpaidOnly && transaction.state == .settled { return false }
                if let type, transaction.direction.rawValue != type { return false }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }

        let sliced = Array(combined.dropFirst(offset).prefix(limit))
        return [
            "result_type": .string("list_transactions"),
            "result": .object([
                "transactions": .array(sliced.map { .object($0.asJSON) }),
            ]),
        ]
    }

    private func handleLookupInvoice(_ command: NWCCommand) -> [String: JSONValue] {
        if let paymentHash = command.params?["payment_hash"]?.stringValue {
            if let match = combinedTransactions().first(where: { $0.paymentHash == paymentHash }) {
                return [
                    "result_type": .string(command.method),
                    "result": .object(match.asJSON),
                ]
            }
            return nwcError(resultType: command.method, code: "NOT_FOUND", message: "invoice not found")
        }

        if let invoice = command.params?["invoice"]?.stringValue {
            if let match = combinedTransactions().first(where: { $0.invoice == normalizeLightningRequest(invoice) }) {
                return [
                    "result_type": .string(command.method),
                    "result": .object(match.asJSON),
                ]
            }
            return nwcError(resultType: command.method, code: "NOT_FOUND", message: "invoice not found")
        }

        return nwcError(resultType: command.method, code: "OTHER", message: "invoice or payment_hash required")
    }

    private func reply(with payload: [String: JSONValue], to event: NostrRelayEvent, connection: NWCConnection, mode: NostrEncryptionMode) async throws {
        let plaintext = try encodeJSONObject(payload)
        let encrypted: String
        switch mode {
        case .nip04:
            encrypted = try NostrCrypto.nip04Encrypt(plaintext: plaintext, privateKeyHex: connection.walletPrivateKey, publicKeyHex: event.pubkey)
        case .nip44v2:
            encrypted = try NostrCrypto.nip44Encrypt(plaintext: plaintext, privateKeyHex: connection.walletPrivateKey, publicKeyHex: event.pubkey)
        }

        var tags = [["p", event.pubkey], ["e", event.id]]
        if mode == .nip44v2 {
            tags.append(["encryption", NostrEncryptionMode.nip44v2.rawValue])
        }

        let reply = try NostrCrypto.signEvent(
            privateKeyHex: connection.walletPrivateKey,
            kind: 23195,
            tags: tags,
            content: encrypted
        )
        try await NostrRelayClient.publish(event: reply, to: SettingsManager.shared.nostrRelays)
    }

    private func encryptionMode(for event: NostrRelayEvent) -> NostrEncryptionMode {
        if event.tags.contains(where: { $0.count >= 2 && $0[0] == "encryption" && $0[1] == NostrEncryptionMode.nip44v2.rawValue }) {
            return .nip44v2
        }
        return .nip04
    }

    private func paymentMethod(for invoice: String) throws -> PaymentMethod {
        let decoded = try decodeInvoice(invoiceStr: invoice)
        switch decoded.paymentType {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        }
    }

    private func normalizeLightningRequest(_ request: String) -> String {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("lightning:") {
            return String(trimmed.dropFirst("lightning:".count))
        }
        return trimmed
    }

    private func combinedTransactions() -> [NWCOperationRecord] {
        var recordsByInvoice = Dictionary(uniqueKeysWithValues: operationRecords.map { ($0.invoice, $0) })

        for transaction in transactionsProvider?() ?? [] {
            guard transaction.kind == .lightning,
                  let invoice = transaction.invoice,
                  !invoice.isEmpty else {
                continue
            }

            let normalized = normalizeLightningRequest(invoice)
            let record = NWCOperationRecord(
                direction: transaction.type == .incoming ? .incoming : .outgoing,
                state: transaction.status == .completed ? .settled : (transaction.status == .failed ? .failed : .pending),
                invoice: normalized,
                description: transaction.memo,
                amountMsat: transaction.amount * 1000,
                feesPaidMsat: transaction.fee > 0 ? transaction.fee * 1000 : nil,
                createdAt: transaction.date,
                settledAt: transaction.status == .completed ? transaction.date : nil,
                expiresAt: nil,
                quoteId: nil,
                mintUrl: transaction.mintUrl,
                preimage: transaction.preimage
            )
            recordsByInvoice[normalized] = recordsByInvoice[normalized] ?? record
        }

        return Array(recordsByInvoice.values)
    }

    private func startPendingInvoiceMonitorIfNeeded() {
        guard pendingInvoiceMonitorTask == nil || pendingInvoiceMonitorTask?.isCancelled == true else { return }
        guard operationRecords.contains(where: { $0.direction == .incoming && $0.state == .pending && $0.quoteId != nil }) else { return }

        pendingInvoiceMonitorTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.pollPendingInvoices()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func pollPendingInvoices() async {
        guard let walletRepository = walletRepositoryProvider?() else { return }

        for index in operationRecords.indices {
            guard operationRecords[index].direction == .incoming,
                  operationRecords[index].state == .pending,
                  let quoteId = operationRecords[index].quoteId,
                  let mintUrl = operationRecords[index].mintUrl else {
                continue
            }

            do {
                let wallet = try await walletRepository.getWallet(mintUrl: MintUrl(url: mintUrl), unit: .sat)
                let proofs = try await wallet.mint(quoteId: quoteId, amountSplitTarget: .none, spendingConditions: nil)
                let mintedAmount = proofs.reduce(UInt64(0)) { $0 + $1.amount.value }
                operationRecords[index].state = .settled
                operationRecords[index].settledAt = Date()
                operationRecords[index].quoteId = nil
                if operationRecords[index].amountMsat == 0 {
                    operationRecords[index].amountMsat = mintedAmount * 1000
                }
                persistRecords()
                await refreshWalletState?()
            } catch {
                continue
            }
        }

        if !operationRecords.contains(where: { $0.direction == .incoming && $0.state == .pending && $0.quoteId != nil }) {
            pendingInvoiceMonitorTask?.cancel()
            pendingInvoiceMonitorTask = nil
        }
    }

    private func upsertRecord(_ record: NWCOperationRecord) {
        if let index = operationRecords.firstIndex(where: { $0.invoice == record.invoice && $0.direction == record.direction }) {
            operationRecords[index] = record
        } else {
            operationRecords.insert(record, at: 0)
        }
        persistRecords()
    }

    private func registerSeenCommand(_ event: NostrRelayEvent) {
        seenCommandIds.append(event.id)
        seenCommandIds = Array(seenCommandIds.suffix(200))
        UserDefaults.standard.set(seenCommandIds, forKey: seenCommandIdsKey)
        UserDefaults.standard.set(max(seenCommandsUntil(), event.createdAt), forKey: seenCommandsUntilKey)
    }

    private func seenCommandsUntil() -> Int {
        UserDefaults.standard.integer(forKey: seenCommandsUntilKey)
    }

    private func loadPersistedState() {
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let records = try? JSONDecoder().decode([NWCOperationRecord].self, from: data) {
            operationRecords = records
        }
        seenCommandIds = UserDefaults.standard.stringArray(forKey: seenCommandIdsKey) ?? []
    }

    private func persistRecords() {
        if let data = try? JSONEncoder().encode(operationRecords) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }

    private func nwcError(resultType: String, code: String, message: String) -> [String: JSONValue] {
        [
            "result_type": .string(resultType),
            "error": .object([
                "code": .string(code),
                "message": .string(message),
            ]),
        ]
    }

    private func encodeJSONObject(_ object: [String: JSONValue]) throws -> String {
        let data = try JSONEncoder().encode(object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NostrSupportError.invalidUTF8
        }
        return string
    }
}

private struct NWCCommand: Decodable {
    let method: String
    let params: [String: JSONValue]?
}

private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .number(let number):
            try container.encode(number)
        case .bool(let bool):
            try container.encode(bool)
        case .object(let object):
            try container.encode(object)
        case .array(let array):
            try container.encode(array)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let string) = self { return string }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let bool) = self { return bool }
        return nil
    }

    var intValue: Int? {
        if case .number(let number) = self { return Int(number) }
        return nil
    }

    var uint64Value: UInt64? {
        if case .number(let number) = self, number >= 0 { return UInt64(number) }
        return nil
    }
}

private extension NWCOperationRecord {
    var paymentHash: String? {
        Bolt11Parser.paymentHash(from: invoice)
    }

    var asJSON: [String: JSONValue] {
        [
            "type": .string(direction.rawValue),
            "invoice": .string(invoice),
            "description": description.map(JSONValue.string) ?? .null,
            "preimage": preimage.map(JSONValue.string) ?? .null,
            "payment_hash": paymentHash.map(JSONValue.string) ?? .null,
            "amount": .number(Double(amountMsat)),
            "fees_paid": feesPaidMsat.map { .number(Double($0)) } ?? .null,
            "created_at": .number(Double(Int(createdAt.timeIntervalSince1970))),
            "settled_at": settledAt.map { .number(Double(Int($0.timeIntervalSince1970))) } ?? .null,
            "expires_at": expiresAt.map { .number(Double(Int($0.timeIntervalSince1970))) } ?? .null,
        ]
    }
}

private enum Bolt11Parser {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    static func paymentHash(from invoice: String) -> String? {
        let normalized = invoice.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let separatorIndex = normalized.lastIndex(of: "1") else { return nil }
        let dataPart = normalized[normalized.index(after: separatorIndex)...]

        var words: [UInt8] = []
        for character in dataPart {
            guard let value = charset.firstIndex(of: character) else { return nil }
            words.append(UInt8(value))
        }

        guard words.count > 7 + 104 + 6 else { return nil }
        let payloadWords = Array(words.dropLast(6))
        let taggedFields = payloadWords.dropFirst(7).dropLast(104)

        var index = taggedFields.startIndex
        while index < taggedFields.endIndex {
            guard index + 2 < taggedFields.endIndex else { return nil }
            let type = taggedFields[index]
            let length = Int(taggedFields[index + 1]) * 32 + Int(taggedFields[index + 2])
            let fieldStart = index + 3
            let fieldEnd = fieldStart + length
            guard fieldEnd <= taggedFields.endIndex else { return nil }

            if type == 1 {
                let fieldWords = Array(taggedFields[fieldStart..<fieldEnd])
                if let bytes = convertBits(fieldWords, fromBits: 5, toBits: 8, pad: false) {
                    return bytes.map { String(format: "%02x", $0) }.joined()
                }
                return nil
            }

            index = fieldEnd
        }

        return nil
    }

    private static func convertBits(_ data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var accumulator = 0
        var bits = 0
        var result: [UInt8] = []
        let maxValue = (1 << toBits) - 1

        for value in data {
            accumulator = (accumulator << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((accumulator >> bits) & maxValue))
            }
        }

        if pad {
            if bits > 0 {
                result.append(UInt8((accumulator << (toBits - bits)) & maxValue))
            }
        } else if bits >= fromBits || ((accumulator << (toBits - bits)) & maxValue) != 0 {
            return nil
        }

        return result
    }
}
