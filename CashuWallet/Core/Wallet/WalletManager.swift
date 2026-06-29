import Foundation
import SwiftUI
import Combine
import Cdk

// MARK: - Wallet Manager

/// Central wallet coordinator that orchestrates all wallet operations.
/// Delegates to specialized services for specific functionality.
/// Views should observe this facade instead of individual services.
@MainActor
class WalletManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Total wallet balance in satoshis
    @Published var balance: UInt64 = 0
    
    /// Pending balance (invoices not yet claimed)
    @Published var pendingBalance: UInt64 = 0
    
    /// Whether the wallet is initialized
    @Published var isInitialized = false
    
    /// Whether the user needs to go through onboarding
    @Published var needsOnboarding = false
    
    /// Whether an operation is in progress
    @Published var isLoading = false
    
    /// Error message
    @Published var errorMessage: String?

    /// Active unit (sat, usd, etc.)
    @Published var activeUnit: String = "sat"

    /// Outcome of the most recent `performICloudBackup()`. Lets the enable path
    /// (which runs the backup via the `iCloudBackupEnabled` setter) read the real
    /// result without triggering a second write.
    var lastICloudBackupOutcome: ICloudBackupOutcome? = nil

    var mintQuoteSyncsInFlight: Set<String> = []

    /// Throttle state for passive mint-quote syncs (opening History, app
    /// foreground). Collapses overlapping triggers and rate-limits how often
    /// we re-poll the mint so reusable BOLT12 offers don't hammer it.
    var isSyncingMintQuotes = false
    var lastMintQuoteSyncAt: Date?
    let mintQuoteSyncCooldown: TimeInterval = 45

    // MARK: - Services

    let walletStore = WalletStore()
    var processedQuotes: Set<String>
    var npcQuotesInFlight: Set<String> = []
    
    /// Mint management service
    private(set) lazy var mintService = MintService(
        walletRepository: { [weak self] in self?.walletRepository },
        walletStore: walletStore
    )
    
    /// Transaction history service
    private(set) lazy var transactionService = TransactionService(
        walletRepository: { [weak self] in self?.walletRepository },
        walletDatabase: { [weak self] in self?.db },
        getTrackedMintUrls: { [weak self] in
            guard let self else { return [] }
            return self.trackedMintUrlsForWalletAccess()
        },
        walletStore: walletStore
    )
    
    /// Token operations service
    private(set) lazy var tokenService = TokenService(
        walletRepository: { [weak self] in self?.walletRepository },
        getActiveMint: { [weak self] in self?.activeMint }
    )
    
    /// Lightning operations service
    private(set) lazy var lightningService = LightningService(
        walletRepository: { [weak self] in self?.walletRepository },
        walletDatabase: { [weak self] in self?.db },
        getActiveMint: { [weak self] in self?.activeMint },
        getMints: { [weak self] in self?.mints ?? [] }
    )
    
    // MARK: - Computed Properties (Delegate to Services)
    
    /// List of configured mints
    var mints: [MintInfo] {
        get { mintService.mints }
        set { mintService.mints = newValue }
    }
    
    /// Currently active mint
    var activeMint: MintInfo? {
        get { mintService.activeMint }
        set { mintService.activeMint = newValue }
    }
    
    /// All wallet transactions
    var transactions: [WalletTransaction] {
        transactionService.transactions
    }
    
    /// Pending tokens (sent but not yet claimed)
    var pendingTokens: [PendingToken] {
        transactionService.pendingTokens
    }
    
    /// Pending receive tokens
    var pendingReceiveTokens: [PendingReceiveToken] {
        transactionService.pendingReceiveTokens
    }
    
    // MARK: - Stored State
    
    var walletRepository: WalletRepository?
    var db: WalletSqliteDatabase?
    let keychainService = KeychainService()
    var mnemonic: String?
    var hasInitialized = false
    var npcQuoteObserver: NSObjectProtocol?
    var serviceChangeCancellables: Set<AnyCancellable> = []
    let walletDatabaseDirectoryName = "cashu-swift"
    let walletDatabaseFilename = "wallet.db"
    
    // MARK: - Initialization
    
    init() {
        processedQuotes = Set(walletStore.loadProcessedNPCQuotes())
        bindServiceChanges()
    }

    private func bindServiceChanges() {
        [
            mintService.objectWillChange.eraseToAnyPublisher(),
            transactionService.objectWillChange.eraseToAnyPublisher()
        ]
        .forEach { publisher in
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.objectWillChange.send()
                    }
                }
                .store(in: &serviceChangeCancellables)
        }
    }
    

    deinit {
        if let npcQuoteObserver {
            NotificationCenter.default.removeObserver(npcQuoteObserver)
        }
    }
}
