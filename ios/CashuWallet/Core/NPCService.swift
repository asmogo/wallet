import Foundation
import SwiftUI
import Cdk

/// Service for NPubCash integration using CDK NpubCashClient
/// Provides Lightning address functionality via Nostr identity
@MainActor
class NPCService: ObservableObject {
    static let shared = NPCService()
    
    // MARK: - Settings (persisted)
    
    @Published var isEnabled: Bool {
        didSet {
            guard !suppressSettingsSideEffects, isEnabled != oldValue else { return }
            settingsStore.npcEnabled = isEnabled
            if isEnabled {
                Task { await connect() }
            } else {
                disconnect()
            }
        }
    }
    
    @Published var automaticClaim: Bool {
        didSet { settingsStore.npcAutomaticClaim = automaticClaim }
    }
    
    @Published var selectedMintUrl: String? {
        didSet {
            settingsStore.npcSelectedMint = selectedMintUrl
        }
    }
    
    @Published var lastCheck: Date? {
        didSet {
            settingsStore.npcLastCheck = lastCheck
        }
    }
    
    // MARK: - State
    
    @Published var lightningAddress: String = ""
    @Published var configuredMintUrl: String = ""
    @Published var isLoading: Bool = false
    @Published var isConnected: Bool = false
    @Published var errorMessage: String?
    
    /// Whether the service has been initialized with keys
    var isInitialized: Bool {
        return nostrSecretKey != nil && nostrPubkey != nil
    }
    
    // MARK: - Configuration
    
    let baseURL = "https://npubx.cash"
    var domain: String { 
        URL(string: baseURL)?.host ?? "npub.cash" 
    }
    
    // MARK: - Private
    
    private var client: (any NpubCashClientProtocol)?
    private var suppressSettingsSideEffects = false
    private var connectionTask: Task<Void, Never>?
    private var sessionID = UUID()
    private let makeClient: (String, String) throws -> any NpubCashClientProtocol
    private var nostrSecretKey: String?
    private var nostrPubkey: String?
    private var refreshTimer: Timer?
    private var paymentCheckInProgress = false
    private let settingsStore: SettingsStore
    private let refreshInterval: TimeInterval
    private var shouldCheckIncomingInvoices: Bool {
        settingsStore.checkIncomingInvoices
    }
    private var shouldPeriodicallyCheckIncomingInvoices: Bool {
        settingsStore.periodicallyCheckIncomingInvoices
    }
    
    // MARK: - Initialization
    
    init(
        settingsStore: SettingsStore = .shared,
        refreshInterval: TimeInterval = 120,
        makeClient: @escaping (String, String) throws -> any NpubCashClientProtocol = {
            try NpubCashClient(baseUrl: $0, nostrSecretKey: $1)
        }
    ) {
        self.settingsStore = settingsStore
        self.refreshInterval = refreshInterval
        self.makeClient = makeClient
        self.isEnabled = settingsStore.npcEnabled
        self.automaticClaim = settingsStore.npcAutomaticClaim
        self.selectedMintUrl = settingsStore.npcSelectedMint
        self.lastCheck = settingsStore.npcLastCheck
    }
    
    /// Initialize connection on app startup if enabled
    /// Should be called after wallet seed is available
    func initializeIfEnabled() async {
        await connect()
        applyPollingPreferences()
    }

    func reloadWalletScopedData() {
        suppressSettingsSideEffects = true
        defer { suppressSettingsSideEffects = false }
        isEnabled = settingsStore.npcEnabled
        automaticClaim = settingsStore.npcAutomaticClaim
        selectedMintUrl = settingsStore.npcSelectedMint
        lastCheck = settingsStore.npcLastCheck
    }

    // MARK: - Key Derivation
    
    /// Initialize with wallet seed
    func initializeWithSeed(_ seed: Data) throws {
        // Derive Nostr secret key from wallet seed using CDK function
        let derivedSecretKey = try npubcashDeriveSecretKeyFromSeed(seed: seed)
        let derivedPubkey = try npubcashGetPubkey(nostrSecretKey: derivedSecretKey)
        
        // Convert hex pubkey to bech32 npub format for Lightning address
        let npub = try hexToNpub(derivedPubkey)
        
        if nostrSecretKey != derivedSecretKey {
            disconnect()
            configuredMintUrl = ""
        }
        nostrSecretKey = derivedSecretKey
        nostrPubkey = derivedPubkey
        lightningAddress = "\(npub)@\(domain)"
        
        // Restored settings do not invoke isEnabled.didSet. Start only after
        // keys exist, without blocking local wallet startup on the network.
        if isEnabled {
            Task { await initializeIfEnabled() }
        }
    }
    
    /// Get the npub (bech32 public key) for display
    func getNpub() -> String? {
        guard let hexPubkey = nostrPubkey else { return nil }
        return try? hexToNpub(hexPubkey)
    }

    /// The compressed public key used when minting NPubCash locked quotes.
    var p2pkPublicKey: String? {
        guard let nostrPubkey, nostrPubkey.count == 64 else { return nil }
        return "02\(nostrPubkey)"
    }
    
    /// Convert hex public key to bech32 npub format
    private func hexToNpub(_ hexPubkey: String) throws -> String {
        // Convert hex string to bytes
        var bytes = [UInt8]()
        var hex = hexPubkey
        while hex.count >= 2 {
            let byteString = String(hex.prefix(2))
            hex = String(hex.dropFirst(2))
            guard let byte = UInt8(byteString, radix: 16) else {
                throw NPCError.invalidResponse
            }
            bytes.append(byte)
        }
        
        // Use Bech32 encoder from NostrService
        return try Bech32.encode(hrp: "npub", data: Data(bytes))
    }
    
    // MARK: - Connection
    
    /// Share one attempt across startup, foreground, settings, and payment checks.
    func connect() async {
        guard isEnabled, let secretKey = nostrSecretKey else { return }
        if isConnected, client != nil { return }
        if let connectionTask {
            await connectionTask.value
            return
        }

        let session = sessionID
        isLoading = true
        errorMessage = nil
        let task = Task { await establishConnection(secretKey: secretKey, session: session) }
        connectionTask = task
        await task.value
    }

    private func establishConnection(secretKey: String, session: UUID) async {
        defer {
            if sessionID == session {
                connectionTask = nil
                isLoading = false
            }
        }
        guard isCurrentSession(session), !Task.isCancelled else { return }
        do {
            let connectedClient = try makeClient(baseURL, secretKey)
            let quotes = try await connectedClient.getQuotes(since: nil)
            guard isCurrentSession(session), !Task.isCancelled else { return }

            var configured = quotes.compactMap(\.mintUrl).first ?? ""
            if let selected = selectedMintUrl {
                do {
                    let response = try await connectedClient.setMintUrl(mintUrl: selected)
                    if !response.error, let confirmed = response.mintUrl {
                        configured = confirmed
                    }
                } catch {
                    // A mint reconciliation failure does not invalidate authentication.
                    print("NPC: mint reconciliation failed: \(error)")
                }
            }
            guard isCurrentSession(session), !Task.isCancelled else { return }
            client = connectedClient
            configuredMintUrl = configured
            isConnected = true
            errorMessage = nil
            startBackgroundRefresh()
        } catch {
            guard isCurrentSession(session), !Task.isCancelled else { return }
            client = nil
            isConnected = false
            errorMessage = ActionErrorMessages.message(for: error, context: .lightningConnection)
            // Keep periodic recovery available after a failed initial attempt.
            startBackgroundRefresh()
        }
    }

    private func isCurrentSession(_ session: UUID) -> Bool {
        isEnabled && sessionID == session
    }

    /// Disconnect and stop background refresh
    func disconnect() {
        sessionID = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        isLoading = false
        paymentCheckInProgress = false
        stopBackgroundRefresh()
        isConnected = false
        client = nil
        // A stale error must not outlive the session it came from — Android
        // clears it on disable, and the status dot reads it as red forever.
        errorMessage = nil
    }
    
    // MARK: - API Methods
    
    /// Change configured mint on NpubCash server.
    /// Local selection is only persisted once the server confirms the change,
    /// otherwise incoming payments keep landing on the server's default mint.
    func changeMint(to mintUrl: String) async throws {
        let session = sessionID
        await connect()
        guard isCurrentSession(session) else { throw CancellationError() }
        guard let client, isConnected else { throw NPCError.notConnected }

        let response = try await client.setMintUrl(mintUrl: mintUrl)
        guard isCurrentSession(session) else { throw CancellationError() }

        if response.error {
            throw NPCError.apiError("Failed to change mint")
        }

        let confirmed = response.mintUrl ?? mintUrl
        configuredMintUrl = confirmed
        selectedMintUrl = confirmed
        errorMessage = nil
    }
    
    /// Get quotes from NpubCash
    func getQuotes(since: UInt64? = nil) async throws -> [NpubCashQuote] {
        guard let client = client else {
            throw NPCError.notConnected
        }
        
        return try await client.getQuotes(since: since)
    }
    
    /// Check for new payments and claim them
    func checkAndClaimPayments() async {
        guard isEnabled, shouldCheckIncomingInvoices else { return }
        guard !paymentCheckInProgress else { return }

        let session = sessionID
        paymentCheckInProgress = true
        defer {
            if sessionID == session { paymentCheckInProgress = false }
        }

        if !isConnected || client == nil {
            await connect()
        }

        guard isCurrentSession(session), isConnected, client != nil else { return }
        
        do {
            let quotes = try await getQuotes(since: nil)
            guard isCurrentSession(session), !Task.isCancelled else { return }
            lastCheck = Date()
            errorMessage = nil
            
            // Process paid quotes
            let paidQuotes = quotes
                .filter { $0.isPaid }
                .sorted {
                    ($0.paidAt ?? $0.createdAt) < ($1.paidAt ?? $1.createdAt)
                }
            
            for quote in paidQuotes {
                guard isCurrentSession(session), !Task.isCancelled else { return }
                if automaticClaim {
                    await claimQuote(quote)
                } else {
                    // Notify user about pending payment
                    await notifyPendingPayment(quote)
                }
            }
            
        } catch {
            guard isCurrentSession(session), !Task.isCancelled else { return }
            isConnected = false
            client = nil
            errorMessage = ActionErrorMessages.message(for: error, context: .lightningPayments)
            print("Failed to check NPC payments: \(error)")
        }
    }
    
    /// Claim a specific quote by minting the tokens
    private func claimQuote(_ quote: NpubCashQuote) async {
        // Convert to MintQuote using CDK helper and notify WalletManager
        let mintQuote = npubcashQuoteToMintQuote(quote: quote)

        var userInfo: [String: Any] = [
            "mintQuote": mintQuote,
            "npcQuote": quote
        ]

        if quote.locked == true, let p2pkPublicKey {
            userInfo["spendingConditions"] = SpendingConditions.p2pk(
                pubkey: p2pkPublicKey,
                conditions: nil
            )
        }
        
        NotificationCenter.default.post(
            name: .npcQuoteReceived,
            object: nil,
            userInfo: userInfo
        )
    }
    
    /// Notify about pending payment (when auto-claim is disabled)
    private func notifyPendingPayment(_ quote: NpubCashQuote) async {
        NotificationCenter.default.post(
            name: .npcPaymentPending,
            object: nil,
            userInfo: [
                "amount": quote.amount,
                "quoteId": quote.id
            ]
        )
    }
    
    // MARK: - Background Refresh
    
    func startBackgroundRefresh() {
        stopBackgroundRefresh()

        guard isEnabled, isInitialized, shouldCheckIncomingInvoices else { return }

        // A failed connection waits for the timer; do not immediately recurse.
        if isConnected {
            Task { await checkAndClaimPayments() }
        }

        guard shouldPeriodicallyCheckIncomingInvoices else { return }

        // Setup timer
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAndClaimPayments()
            }
        }
    }
    
    func stopBackgroundRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func applyPollingPreferences() {
        guard isEnabled, isInitialized else {
            stopBackgroundRefresh()
            return
        }
        startBackgroundRefresh()
    }

    func resetForWalletBoundary() {
        stopBackgroundRefresh()
        disconnect()
        nostrSecretKey = nil
        nostrPubkey = nil
        client = nil
        lightningAddress = ""
        configuredMintUrl = ""
        errorMessage = nil
        isLoading = false
        paymentCheckInProgress = false
        selectedMintUrl = nil
        lastCheck = nil
        automaticClaim = true
        isEnabled = false
    }

    deinit {
        refreshTimer?.invalidate()
    }
}

// MARK: - Error Types

enum NPCError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case notConnected
    case authFailed
    case notInitialized
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return message
        case .notConnected:
            return "Not connected to npub.cash"
        case .authFailed:
            return "Authentication failed"
        case .notInitialized:
            return "NPC service not initialized"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let npcQuoteReceived = Notification.Name("npcQuoteReceived")
    static let npcPaymentPending = Notification.Name("npcPaymentPending")
}

private extension NpubCashQuote {
    var isPaid: Bool {
        state?.caseInsensitiveCompare("PAID") == .orderedSame
    }
}

/// Retry orchestration with injectable boundaries; identity derivation stays in NPCService.
@MainActor
enum LightningAddressSetupRecovery {
    static func retry(
        isRuntimeReady: () -> Bool,
        initializeRuntime: () async -> Void,
        isAddressInitialized: () -> Bool,
        loadSeed: () throws -> Data,
        initializeAddress: (Data) throws -> Void
    ) async throws {
        if !isRuntimeReady() { await initializeRuntime() }
        guard isRuntimeReady() else { throw WalletError.notInitialized }
        guard !isAddressInitialized() else { return }
        try initializeAddress(loadSeed())
    }
}
