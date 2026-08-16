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

    /// Per-unit balance totals summed across all mints, in each unit's base
    /// units (sat, or eur/usd cents, …). Drives the multi-unit home hero;
    /// `balance` mirrors `balancesByUnit["sat"]`.
    @Published var balancesByUnit: [String: UInt64] = [:]

    /// True when the wallet holds spendable ecash in *any* unit (sat or
    /// otherwise). Send gates on this rather than `balance` (sats only) so a
    /// USD-only wallet isn't told it has "nothing to send".
    var hasAnyBalance: Bool { balancesByUnit.values.contains { $0 > 0 } }

    /// Pending balance (invoices not yet claimed)
    @Published var pendingBalance: UInt64 = 0
    
    /// Whether the wallet is initialized
    @Published var isInitialized = false

    /// Cached wallet state may be visible before CDK finishes opening its
    /// repository. Money-moving actions stay disabled until this becomes true.
    @Published var isRuntimeReady = false
    
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

    /// Cooldown gate for passive mint-quote syncs (opening History, app
    /// foreground, the foreground poll). Collapses overlapping triggers and
    /// rate-limits how often we re-poll the mint so reusable BOLT12 offers
    /// don't hammer it. Kept equal to `pendingQuotePollInterval` (Android
    /// parity) so the poll drives one sync pass per interval.
    var lastMintQuoteSyncAt: Date?
    let mintQuoteSyncCooldown: TimeInterval = 5

    /// Foreground quote poll (started/stopped on scenePhase changes). Re-checks
    /// pending mint + melt quotes while the app is active so a payment lands
    /// without pull-to-refresh (Android parity).
    var pendingQuotePollTask: Task<Void, Never>?
    let pendingQuotePollInterval: TimeInterval = 5

    // MARK: - Services

    /// One exclusive CDK/database lane for this repository. Main-actor
    /// isolation alone is reentrant across `await` and cannot provide this.
    let operationCoordinator = WalletOperationCoordinator()

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
        getUnitsForMint: { [weak self] mintURL in
            self?.mintService.mints.first(where: { $0.url == mintURL })?.units ?? ["sat"]
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
    /// Per-mint launch reconciliation. The usable wallet state is published
    /// before this task starts, and wallet-boundary resets cancel it.
    var startupMaintenanceTask: Task<Void, Never>?
    var npcQuoteObserver: NSObjectProtocol?
    var serviceChangeCancellables: Set<AnyCancellable> = []
    let walletDatabaseDirectoryName = "cashu-swift"
    let walletDatabaseFilename = "wallet.db"
    
    // MARK: - Initialization
    
    init() {
        processedQuotes = Set(walletStore.loadProcessedNPCQuotes())
        bindServiceChanges()
        configureNWCManager()
    }

    /// Connect the NWC service to the live CDK wallet and this wallet's
    /// deterministic seed material. The providers deliberately capture the
    /// manager weakly so the singleton never retains a discarded wallet.
    /// Wallet acquisition is coordinated here. CDK's long-lived `NwcService`
    /// performs later wallet work internally and exposes no per-request hook,
    /// so that activity cannot yet participate in this app-side execution lane.
    private func configureNWCManager() {
        NWCManager.shared.configure(
            walletProvider: { [weak self] mintURL in
                guard let self, let walletRepository = self.walletRepository else {
                    throw WalletError.notInitialized
                }
                return try await self.operationCoordinator.perform(
                    kind: .mintInfo,
                    resourceID: mintURL
                ) {
                    let parsedMintURL = MintUrl(url: mintURL)
                    try? await walletRepository.createWallet(
                        mintUrl: parsedMintURL,
                        unit: .sat,
                        targetProofCount: nil
                    )
                    return try await walletRepository.getWallet(mintUrl: parsedMintURL, unit: .sat)
                }
            },
            seedProvider: { [weak self] in
                guard let mnemonic = self?.mnemonic else { return nil }
                return Data(mnemonic.utf8).sha512()
            }
        )
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
