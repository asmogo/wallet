import Foundation
import CryptoKit
import CashuDevKit

typealias NUT18PaymentRequest = CashuDevKit.PaymentRequest
typealias NUT18PaymentRequestPayload = CashuDevKit.PaymentRequestPayload

struct StoredPaymentRequest: Codable, Identifiable, Hashable {
    let id: String
    let encoded: String
    let unit: String?
    let mints: [String]?
    let memo: String?
    let createdAt: Date
    var receivedPaymentIds: [String]
}

struct IncomingPaymentRequestPayment: Codable, Identifiable, Hashable {
    enum State: String, Codable {
        case pending
        case claimed
    }

    let id: String
    let requestId: String?
    let payloadJSON: String
    let mintUrl: String
    let amount: UInt64
    let unit: String
    let memo: String?
    let createdAt: Date
    var state: State
    var claimedAt: Date?
}

@MainActor
final class PaymentRequestService: ObservableObject {
    static let shared = PaymentRequestService()

    @Published private(set) var ourPaymentRequests: [StoredPaymentRequest] = []
    @Published var selectedRequestIndex: Int = 0
    @Published private(set) var incomingPayments: [IncomingPaymentRequestPayment] = []
    @Published private(set) var isListening = false
    @Published var lastError: String?

    var currentPaymentRequest: StoredPaymentRequest? {
        guard !ourPaymentRequests.isEmpty else { return nil }
        let clampedIndex = min(max(0, selectedRequestIndex), ourPaymentRequests.count - 1)
        return ourPaymentRequests[clampedIndex]
    }

    private let requestsKey = "paymentRequest.ourRequests"
    private let selectedIndexKey = "paymentRequest.selectedIndex"
    private let incomingPaymentsKey = "paymentRequest.incomingPayments"
    private let seenWrapIdsKey = "paymentRequest.seenWrapIds"
    private let lastTimestampKey = "paymentRequest.lastTimestamp"

    private struct SeenWrapRecord: Codable {
        let id: String
        let createdAt: Date
    }

    private var seenWrapRecords: [SeenWrapRecord] = []
    private var subscription: NostrRelaySubscription?

    private var walletRepositoryProvider: (() -> WalletRepository?)?
    private var ensureMintExists: ((String) async throws -> Void)?
    private var refreshWalletState: (() async -> Void)?
    private var currentMintUrlProvider: (() -> String?)?
    private var knownMintUrlsProvider: (() -> [String])?

    private init() {
        loadState()
    }

    func configure(
        walletRepositoryProvider: @escaping () -> WalletRepository?,
        ensureMintExists: @escaping (String) async throws -> Void,
        currentMintUrlProvider: @escaping () -> String?,
        knownMintUrlsProvider: @escaping () -> [String],
        refreshWalletState: @escaping () async -> Void
    ) {
        self.walletRepositoryProvider = walletRepositoryProvider
        self.ensureMintExists = ensureMintExists
        self.currentMintUrlProvider = currentMintUrlProvider
        self.knownMintUrlsProvider = knownMintUrlsProvider
        self.refreshWalletState = refreshWalletState
    }

    func applySettings() async {
        stopListening()

        let settings = SettingsManager.shared
        guard settings.enablePaymentRequests,
              settings.useWebsockets,
              !settings.nostrRelays.isEmpty,
              !NostrService.shared.publicKeyHex.isEmpty,
              NostrService.shared.getPrivateKeyHex() != nil else {
            return
        }

        startListening(on: settings.nostrRelays)
    }

    func reset() {
        stopListening()
        ourPaymentRequests = []
        incomingPayments = []
        selectedRequestIndex = 0
        seenWrapRecords = []
        lastError = nil

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: requestsKey)
        defaults.removeObject(forKey: selectedIndexKey)
        defaults.removeObject(forKey: incomingPaymentsKey)
        defaults.removeObject(forKey: seenWrapIdsKey)
        defaults.removeObject(forKey: lastTimestampKey)
    }

    func createPaymentRequest(amount: UInt64?, memo: String?, mintUrl: String?) throws -> StoredPaymentRequest {
        let pubkey = NostrService.shared.publicKeyHex
        let privateKey = NostrService.shared.getPrivateKeyHex()
        guard !pubkey.isEmpty, privateKey != nil else {
            throw NostrSupportError.missingPrivateKey
        }

        let requestId = UUID().uuidString.split(separator: "-").first.map(String.init) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let relays = SettingsManager.shared.nostrRelays
        let nprofile = try NostrProfilePointer.encodeNprofile(pubkeyHex: pubkey, relays: relays)

        var transports: [[String: Any]] = [[
            "t": "nostr",
            "a": nprofile,
            "g": [["n", "17"]],
        ]]

        if let callbackURL = SettingsManager.shared.paymentRequestCallbackURL, !callbackURL.isEmpty {
            transports.append([
                "t": "post",
                "a": callbackURL,
            ])
        }

        var rawRequest: [String: Any] = [
            "i": requestId,
            "u": "sat",
            "s": true,
            "t": transports,
        ]

        if let amount {
            rawRequest["a"] = amount
        }

        let allowedMint = (mintUrl?.isEmpty == false ? mintUrl : currentMintUrlProvider?())?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let allowedMint, !allowedMint.isEmpty {
            rawRequest["m"] = [allowedMint]
        }

        let trimmedMemo = memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedMemo, !trimmedMemo.isEmpty {
            rawRequest["d"] = trimmedMemo
        }

        let encoded = "creqA" + PaymentRequestCBOR.base64URLEncoded(from: try PaymentRequestCBOR.encode(rawRequest))
        let request = try decode(encoded)
        let stored = ensureStoredRequest(request: request, encoded: encoded, memo: trimmedMemo)
        return stored
    }

    @discardableResult
    func ensureStoredRequest(request: NUT18PaymentRequest, encoded: String, memo: String? = nil) -> StoredPaymentRequest {
        let entry = StoredPaymentRequest(
            id: request.paymentId() ?? UUID().uuidString,
            encoded: encoded,
            unit: request.unit().map(Self.unitString),
            mints: request.mints(),
            memo: memo ?? request.description(),
            createdAt: Date(),
            receivedPaymentIds: existingRequest(withId: request.paymentId() ?? "")?.receivedPaymentIds ?? []
        )

        if let existingIndex = ourPaymentRequests.firstIndex(where: { $0.id == entry.id }) {
            ourPaymentRequests[existingIndex] = entry
            selectedRequestIndex = existingIndex
        } else {
            ourPaymentRequests.append(entry)
            selectedRequestIndex = ourPaymentRequests.count - 1
        }
        persistRequests()
        return entry
    }

    func selectPreviousRequest() {
        guard !ourPaymentRequests.isEmpty else { return }
        selectedRequestIndex = (selectedRequestIndex - 1 + ourPaymentRequests.count) % ourPaymentRequests.count
        persistSelectedIndex()
    }

    func selectNextRequest() {
        guard !ourPaymentRequests.isEmpty else { return }
        selectedRequestIndex = (selectedRequestIndex + 1) % ourPaymentRequests.count
        persistSelectedIndex()
    }

    func selectRequest(at index: Int) {
        guard !ourPaymentRequests.isEmpty else { return }
        selectedRequestIndex = min(max(0, index), ourPaymentRequests.count - 1)
        persistSelectedIndex()
    }

    func payments(for requestId: String) -> [IncomingPaymentRequestPayment] {
        incomingPayments
            .filter { $0.requestId == requestId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func decode(_ encoded: String) throws -> NUT18PaymentRequest {
        let decoded = try decodePaymentRequest(encoded: encoded)
        _ = ensureStoredRequest(request: decoded, encoded: encoded)
        return decoded
    }

    func payPaymentRequest(encoded: String, customAmount: UInt64?) async throws {
        let request = try decode(encoded)
        guard request.unit().map(Self.unitString) != "msat" else {
            throw PaymentRequestServiceError.unsupportedUnit
        }

        guard let targetMint = request.mints()?.first ?? currentMintUrlProvider?(),
              let walletRepository = walletRepositoryProvider?() else {
            throw WalletError.notInitialized
        }

        let wallet = try await walletForMintURL(targetMint, walletRepository: walletRepository)
        _ = try await wallet.refreshKeysets()
        let amount = customAmount.map { Amount(value: $0) }
        try await wallet.payRequest(paymentRequest: request, customAmount: amount)
        await refreshWalletState?()
    }

    func claimIncomingPayment(_ payment: IncomingPaymentRequestPayment) async throws -> UInt64 {
        guard let index = incomingPayments.firstIndex(where: { $0.id == payment.id }) else {
            throw PaymentRequestServiceError.paymentNotFound
        }
        guard incomingPayments[index].state == .pending else {
            return incomingPayments[index].amount
        }

        guard let walletRepository = walletRepositoryProvider?() else {
            throw WalletError.notInitialized
        }

        let payload = try NUT18PaymentRequestPayload.fromString(json: payment.payloadJSON)
        guard payload.unit() == .sat else {
            throw PaymentRequestServiceError.unsupportedUnit
        }

        let mintUrl = payload.mint().url
        let wallet = try await walletForMintURL(mintUrl, walletRepository: walletRepository)
        _ = try await wallet.refreshKeysets()
        let options = ReceiveOptions(amountSplitTarget: .none, p2pkSigningKeys: [], preimages: [], metadata: [:])
        _ = try await wallet.receiveProofs(proofs: payload.proofs(), options: options, memo: payload.memo(), token: nil)

        incomingPayments[index].state = .claimed
        incomingPayments[index].claimedAt = Date()
        persistIncomingPayments()

        NotificationCenter.default.post(name: .cashuTokenReceived, object: nil, userInfo: ["amount": payment.amount])
        await refreshWalletState?()
        return payment.amount
    }

    private func startListening(on relays: [String]) {
        let filter = NostrFilter(
            kinds: [1059],
            authors: nil,
            since: max(lastSeenTimestamp() - 172_800, Int(Date().timeIntervalSince1970) - 172_800),
            limit: nil,
            tags: ["p": [NostrService.shared.publicKeyHex]]
        )

        let subscription = NostrRelaySubscription(relays: relays, filter: filter) { [weak self] event in
            await self?.handleWrappedEvent(event)
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

    private func handleWrappedEvent(_ wrapEvent: NostrRelayEvent) async {
        guard NostrCrypto.verifyEvent(wrapEvent) else { return }
        guard seenWrapRecords.contains(where: { $0.id == wrapEvent.id }) == false else { return }
        guard let privateKeyHex = NostrService.shared.getPrivateKeyHex() else { return }

        do {
            let sealJSON = try NostrCrypto.nip44Decrypt(payload: wrapEvent.content, privateKeyHex: privateKeyHex, publicKeyHex: wrapEvent.pubkey)
            guard let sealData = sealJSON.data(using: String.Encoding.utf8) else { return }
            let sealEvent = try JSONDecoder().decode(NostrRelayEvent.self, from: sealData)
            guard NostrCrypto.verifyEvent(sealEvent) else { return }

            let rumorJSON = try NostrCrypto.nip44Decrypt(payload: sealEvent.content, privateKeyHex: privateKeyHex, publicKeyHex: sealEvent.pubkey)
            guard let rumorData = rumorJSON.data(using: String.Encoding.utf8) else { return }
            let rumorEvent = try JSONDecoder().decode(NostrDirectMessageEvent.self, from: rumorData)
            guard rumorEvent.kind == 14 else { return }

            registerSeenWrap(id: wrapEvent.id)
            try await processIncomingPayloadJSON(rumorEvent.content)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func processIncomingPayloadJSON(_ json: String) async throws {
        let payload = try NUT18PaymentRequestPayload.fromString(json: json)
        guard payload.unit() == .sat else {
            throw PaymentRequestServiceError.unsupportedUnit
        }

        let proofs = payload.proofs()
        let amount = proofs.reduce(UInt64(0)) { $0 + $1.amount.value }
        let paymentId = Data(CryptoKit.SHA256.hash(data: Data(json.utf8))).map { String(format: "%02x", $0) }.joined()
        guard !incomingPayments.contains(where: { $0.id == paymentId }) else {
            return
        }

        let requestId = payload.id()
        var payment = IncomingPaymentRequestPayment(
            id: paymentId,
            requestId: requestId,
            payloadJSON: json,
            mintUrl: payload.mint().url,
            amount: amount,
            unit: Self.unitString(payload.unit()),
            memo: payload.memo(),
            createdAt: Date(),
            state: .pending,
            claimedAt: nil
        )

        incomingPayments.insert(payment, at: 0)
        if let requestId {
            registerIncomingPayment(for: requestId, paymentId: payment.id)
        }
        persistIncomingPayments()

        let settings = SettingsManager.shared
        let knownMints = Set(knownMintUrlsProvider?() ?? [])
        if settings.receivePaymentRequestsAutomatically && knownMints.contains(payment.mintUrl) {
            do {
                _ = try await claimIncomingPayment(payment)
                if let updated = incomingPayments.first(where: { $0.id == payment.id }) {
                    payment = updated
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func existingRequest(withId id: String) -> StoredPaymentRequest? {
        ourPaymentRequests.first { $0.id == id }
    }

    private func registerIncomingPayment(for requestId: String, paymentId: String) {
        guard let index = ourPaymentRequests.firstIndex(where: { $0.id == requestId }) else { return }
        if !ourPaymentRequests[index].receivedPaymentIds.contains(paymentId) {
            ourPaymentRequests[index].receivedPaymentIds.append(paymentId)
            persistRequests()
        }
    }

    private func registerSeenWrap(id: String) {
        seenWrapRecords.append(SeenWrapRecord(id: id, createdAt: Date()))
        seenWrapRecords = seenWrapRecords
            .filter { $0.createdAt > Date().addingTimeInterval(-7 * 24 * 60 * 60) }
            .suffix(200)
        persistSeenWraps()
        UserDefaults.standard.set(Int(Date().timeIntervalSince1970), forKey: lastTimestampKey)
    }

    private func lastSeenTimestamp() -> Int {
        UserDefaults.standard.integer(forKey: lastTimestampKey)
    }

    private func walletForMintURL(_ mintUrlString: String, walletRepository: WalletRepository) async throws -> Wallet {
        try await ensureMintExists?(mintUrlString)
        let mintUrl = try MintUrl(url: mintUrlString)
        try await walletRepository.createWallet(mintUrl: mintUrl, unit: .sat, targetProofCount: nil)
        return try await walletRepository.getWallet(mintUrl: mintUrl, unit: .sat)
    }

    private func loadState() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()

        if let data = defaults.data(forKey: requestsKey),
           let stored = try? decoder.decode([StoredPaymentRequest].self, from: data) {
            ourPaymentRequests = stored
        }

        let storedIndex = defaults.integer(forKey: selectedIndexKey)
        selectedRequestIndex = min(max(0, storedIndex), max(0, ourPaymentRequests.count - 1))

        if let data = defaults.data(forKey: incomingPaymentsKey),
           let storedPayments = try? decoder.decode([IncomingPaymentRequestPayment].self, from: data) {
            incomingPayments = storedPayments
        }

        if let data = defaults.data(forKey: seenWrapIdsKey),
           let storedWraps = try? decoder.decode([SeenWrapRecord].self, from: data) {
            seenWrapRecords = storedWraps
        }
    }

    private func persistRequests() {
        if let data = try? JSONEncoder().encode(ourPaymentRequests) {
            UserDefaults.standard.set(data, forKey: requestsKey)
        }
        persistSelectedIndex()
    }

    private func persistSelectedIndex() {
        UserDefaults.standard.set(selectedRequestIndex, forKey: selectedIndexKey)
    }

    private func persistIncomingPayments() {
        if let data = try? JSONEncoder().encode(incomingPayments) {
            UserDefaults.standard.set(data, forKey: incomingPaymentsKey)
        }
    }

    private func persistSeenWraps() {
        if let data = try? JSONEncoder().encode(seenWrapRecords) {
            UserDefaults.standard.set(data, forKey: seenWrapIdsKey)
        }
    }

    static func unitString(_ unit: CurrencyUnit) -> String {
        switch unit {
        case .sat:
            return "sat"
        case .msat:
            return "msat"
        case .usd:
            return "usd"
        case .eur:
            return "eur"
        case .auth:
            return "auth"
        case .custom(let unit):
            return unit
        }
    }
}

enum PaymentRequestServiceError: LocalizedError {
    case unsupportedUnit
    case paymentNotFound

    var errorDescription: String? {
        switch self {
        case .unsupportedUnit:
            return "Only sat-denominated payment requests are supported right now."
        case .paymentNotFound:
            return "Payment request payment not found."
        }
    }
}

private enum PaymentRequestCBOR {
    static func encode(_ object: [String: Any]) throws -> Data {
        try encodeMap(object)
    }

    static func base64URLEncoded(from data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    private static func encodeValue(_ value: Any) throws -> Data {
        switch value {
        case let string as String:
            return encodeText(string)
        case let uint as UInt64:
            return encodeUnsignedInteger(uint)
        case let int as Int:
            return encodeUnsignedInteger(UInt64(max(0, int)))
        case let bool as Bool:
            return Data([bool ? 0xF5 : 0xF4])
        case let array as [Any]:
            return try encodeArray(array)
        case let map as [String: Any]:
            return try encodeMap(map)
        default:
            throw PaymentRequestServiceError.unsupportedUnit
        }
    }

    private static func encodeMap(_ map: [String: Any]) throws -> Data {
        var data = encodeMajorType(5, value: UInt64(map.count))
        for key in map.keys.sorted() {
            data.append(encodeText(key))
            if let value = map[key] {
                data.append(try encodeValue(value))
            }
        }
        return data
    }

    private static func encodeArray(_ array: [Any]) throws -> Data {
        var data = encodeMajorType(4, value: UInt64(array.count))
        for value in array {
            data.append(try encodeValue(value))
        }
        return data
    }

    private static func encodeText(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        var data = encodeMajorType(3, value: UInt64(bytes.count))
        data.append(bytes)
        return data
    }

    private static func encodeUnsignedInteger(_ value: UInt64) -> Data {
        encodeMajorType(0, value: value)
    }

    private static func encodeMajorType(_ majorType: UInt8, value: UInt64) -> Data {
        switch value {
        case 0...23:
            return Data([majorType << 5 | UInt8(value)])
        case 24...0xFF:
            return Data([majorType << 5 | 24, UInt8(value)])
        case 0x100...0xFFFF:
            let high = UInt16(value).bigEndian
            return Data([majorType << 5 | 25, UInt8(high >> 8), UInt8(high & 0xFF)])
        case 0x1_0000...0xFFFF_FFFF:
            let high = UInt32(value).bigEndian
            return Data([
                majorType << 5 | 26,
                UInt8(high >> 24),
                UInt8((high >> 16) & 0xFF),
                UInt8((high >> 8) & 0xFF),
                UInt8(high & 0xFF),
            ])
        default:
            let high = value.bigEndian
            return Data([
                majorType << 5 | 27,
                UInt8(high >> 56),
                UInt8((high >> 48) & 0xFF),
                UInt8((high >> 40) & 0xFF),
                UInt8((high >> 32) & 0xFF),
                UInt8((high >> 24) & 0xFF),
                UInt8((high >> 16) & 0xFF),
                UInt8((high >> 8) & 0xFF),
                UInt8(high & 0xFF),
            ])
        }
    }
}

private extension SettingsManager {
    var paymentRequestCallbackURL: String? {
        nil
    }
}
