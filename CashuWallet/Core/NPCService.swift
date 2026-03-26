import Foundation
import SwiftUI
import CashuDevKit

/// Service for npub.cash integration using CDK NpubCashClient
/// Provides Lightning address functionality via Nostr identity
@MainActor
class NPCService: ObservableObject {
    static let shared = NPCService()
    
    // MARK: - Settings (persisted)
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "npc.enabled")
            if isEnabled {
                Task { await connect() }
            } else {
                disconnect()
            }
        }
    }
    
    @Published var automaticClaim: Bool {
        didSet { UserDefaults.standard.set(automaticClaim, forKey: "npc.automaticClaim") }
    }
    
    @Published var selectedMintUrl: String? {
        didSet {
            if let url = selectedMintUrl {
                UserDefaults.standard.set(url, forKey: "npc.selectedMint")
            }
        }
    }
    
    @Published var lastCheck: Date? {
        didSet {
            if let date = lastCheck {
                UserDefaults.standard.set(date, forKey: "npc.lastCheck")
            }
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
    
    private var client: NpubCashClient?
    private var nostrSecretKey: String?
    private var nostrPubkey: String?
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 120  // Check every 2 minutes
    private var shouldCheckIncomingInvoices: Bool {
        UserDefaults.standard.object(forKey: "checkIncomingInvoices") as? Bool ?? true
    }
    private var shouldPeriodicallyCheckIncomingInvoices: Bool {
        UserDefaults.standard.object(forKey: "periodicallyCheckIncomingInvoices") as? Bool ?? true
    }
    
    // MARK: - Initialization
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "npc.enabled")
        self.automaticClaim = UserDefaults.standard.object(forKey: "npc.automaticClaim") as? Bool ?? true
        self.selectedMintUrl = UserDefaults.standard.string(forKey: "npc.selectedMint")
        self.lastCheck = UserDefaults.standard.object(forKey: "npc.lastCheck") as? Date
    }
    
    /// Initialize connection on app startup if enabled
    /// Should be called after wallet seed is available
    func initializeIfEnabled() async {
        if isEnabled {
            await connect()
        }
    }
    
    // MARK: - Key Derivation
    
    /// Initialize with wallet seed
    func initializeWithSeed(_ seed: Data) throws {
        // Derive Nostr secret key from wallet seed using CDK function
        let derivedSecretKey = try npubcashDeriveSecretKeyFromSeed(seed: seed)
        let derivedPubkey = try npubcashGetPubkey(nostrSecretKey: derivedSecretKey)
        
        // Convert hex pubkey to bech32 npub format for Lightning address
        let npub = try hexToNpub(derivedPubkey)
        
        nostrSecretKey = derivedSecretKey
        nostrPubkey = derivedPubkey
        lightningAddress = "\(npub)@\(domain)"
        
        print("NPC: Initialized with npub: \(npub.prefix(20))...")
    }
    
    /// Get the npub (bech32 public key) for display
    func getNpub() -> String? {
        guard let hexPubkey = nostrPubkey else { return nil }
        return try? hexToNpub(hexPubkey)
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
    
    /// Initialize NPC connection
    func connect() async {
        guard isEnabled else { return }
        
        guard let secretKey = nostrSecretKey else {
            errorMessage = "Nostr keys not initialized"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            // Create NpubCashClient with CDKaaaaaaaaaaaa
            print(baseURL)
            let connectedClient = try NpubCashClient(baseUrl: baseURL, nostrSecretKey: secretKey)
            client = connectedClient
            
            // Try to get user info by fetching quotes (this validates connection)
            // The client handles authentication internally
            let quotes = try await connectedClient.getQuotes(since: nil)
            print("NPC: Connected successfully, found \(quotes.count) quotes")
            
            // If user hasn't selected a mint and we have quotes, use the mint from first quote
            if selectedMintUrl == nil, let firstQuote = quotes.first, let mintUrl = firstQuote.mintUrl {
                selectedMintUrl = mintUrl
                configuredMintUrl = mintUrl
            }
            
            isConnected = true
            errorMessage = nil
            
            // Start background refresh
            startBackgroundRefresh()
            
        } catch {
            errorMessage = error.localizedDescription
            print("NPC connection error: \(error)")
            isConnected = false
        }
    }
    
    /// Disconnect and stop background refresh
    func disconnect() {
        stopBackgroundRefresh()
        isConnected = false
        client = nil
    }
    
    // MARK: - API Methods
    
    /// Change configured mint on NpubCash server
    func changeMint(to mintUrl: String) async throws {
        guard let client = client else {
            throw NPCError.notConnected
        }
        
        let response = try await client.setMintUrl(mintUrl: mintUrl)
        
        if response.error {
            throw NPCError.apiError("Failed to change mint")
        }
        
        if let newMintUrl = response.mintUrl {
            configuredMintUrl = newMintUrl
            selectedMintUrl = newMintUrl
        }
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
        guard isEnabled, isConnected, client != nil, shouldCheckIncomingInvoices else { return }
        
        do {
            // Get since timestamp from last check
            let sinceTimestamp: UInt64? = lastCheck.map { UInt64($0.timeIntervalSince1970) }
            
            let quotes = try await getQuotes(since: sinceTimestamp)
            
            // Update last check time
            if let latestQuote = quotes.max(by: { $0.createdAt < $1.createdAt }) {
                lastCheck = Date(timeIntervalSince1970: TimeInterval(latestQuote.createdAt))
            }
            
            // Process paid quotes
            let paidQuotes = quotes.filter { $0.state == "PAID" && $0.locked != true }
            
            for quote in paidQuotes {
                if automaticClaim {
                    await claimQuote(quote)
                } else {
                    // Notify user about pending payment
                    await notifyPendingPayment(quote)
                }
            }
            
        } catch {
            print("Failed to check NPC payments: \(error)")
        }
    }
    
    /// Claim a specific quote by minting the tokens
    private func claimQuote(_ quote: NpubCashQuote) async {
        // Convert to MintQuote using CDK helper and notify WalletManager
        let mintQuote = npubcashQuoteToMintQuote(quote: quote)
        
        NotificationCenter.default.post(
            name: .npcQuoteReceived,
            object: nil,
            userInfo: [
                "mintQuote": mintQuote,
                "npcQuote": quote
            ]
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

        guard shouldCheckIncomingInvoices else { return }

        // Initial check
        Task { await checkAndClaimPayments() }

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
        guard isEnabled, isConnected else {
            stopBackgroundRefresh()
            return
        }
        startBackgroundRefresh()
    }

    /// Clear persisted and in-memory npub.cash state after wallet deletion.
    func reset() {
        disconnect()
        
        UserDefaults.standard.removeObject(forKey: "npc.enabled")
        UserDefaults.standard.removeObject(forKey: "npc.automaticClaim")
        UserDefaults.standard.removeObject(forKey: "npc.selectedMint")
        UserDefaults.standard.removeObject(forKey: "npc.lastCheck")
        
        isEnabled = false
        automaticClaim = true
        selectedMintUrl = nil
        lastCheck = nil
        lightningAddress = ""
        configuredMintUrl = ""
        isLoading = false
        isConnected = false
        errorMessage = nil
        nostrSecretKey = nil
        nostrPubkey = nil
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
