import Foundation
import SwiftUI
import Cdk

/// Nostr Wallet Connect (NIP-47) wallet service integration.
///
/// Turns the wallet into a NIP-47 *wallet service*: it exposes a
/// `nostr+walletconnect://` connection URI that a Nostr app (the client) can use
/// to remotely request `make_invoice` / `pay_invoice` / `get_balance` etc. The
/// heavy lifting lives in CDK's `NwcService`; this type owns its lifecycle,
/// persistence, and the bridge to `WalletManager` for the backing CDK wallet.
///
/// The NWC service is bound to a single mint (`selectedMintUrl`). The service
/// signer key is derived deterministically from the wallet seed, and the client
/// secret is persisted inside the connection URI, so the same URI keeps working
/// across restarts (we `restore` instead of `create` once a URI exists).
@MainActor
final class NWCManager: ObservableObject {
    static let shared = NWCManager()

    // MARK: - Settings (persisted)

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            settingsStore.nwcEnabled = isEnabled
            guard !suppressSideEffects else { return }
            if isEnabled {
                Task { await start() }
            } else {
                Task { await stop() }
            }
        }
    }

    /// Mint URL the NWC service operates on. Changing it restarts a running service.
    @Published var selectedMintUrl: String? {
        didSet {
            guard selectedMintUrl != oldValue else { return }
            settingsStore.nwcSelectedMint = selectedMintUrl
            // A different mint means a different backing wallet: rebuild.
            if isEnabled {
                Task { await restartService() }
            }
        }
    }

    /// Optional cap (in sats) on any single `pay_invoice` request. `nil` = no cap.
    @Published var budgetSats: UInt64? {
        didSet {
            guard budgetSats != oldValue else { return }
            settingsStore.nwcBudgetSats = budgetSats
            if isEnabled {
                Task { await restartService() }
            }
        }
    }

    /// The `nostr+walletconnect://` URI to hand to the Nostr app (QR / copy).
    @Published private(set) var connectionUri: String? {
        didSet { settingsStore.nwcConnectionUri = connectionUri }
    }

    // MARK: - Runtime state

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isBusy: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private

    private var service: NwcService?
    private let settingsStore = SettingsStore.shared

    /// When true, `isEnabled`/`selectedMintUrl`/`budgetSats` `didSet` skip their
    /// start/stop side effects (used for internal state corrections).
    private var suppressSideEffects = false

    /// Resolves the CDK wallet for a given mint URL. Injected by `WalletManager`.
    private var walletProvider: ((String) async throws -> Wallet)?
    /// Provides 64-byte seed material for service-key derivation. Injected by `WalletManager`.
    private var seedProvider: (() -> Data?)?

    /// Relays the service listens on. Reuses the shared Nostr relay list.
    private var relays: [String] { settingsStore.nostrRelays }

    private init() {
        self.isEnabled = settingsStore.nwcEnabled
        self.selectedMintUrl = settingsStore.nwcSelectedMint
        self.budgetSats = settingsStore.nwcBudgetSats
        self.connectionUri = settingsStore.nwcConnectionUri
    }

    // MARK: - Wiring

    /// Inject the wallet/seed providers. Call once from `WalletManager` after the
    /// wallet is available.
    func configure(
        walletProvider: @escaping (String) async throws -> Wallet,
        seedProvider: @escaping () -> Data?
    ) {
        self.walletProvider = walletProvider
        self.seedProvider = seedProvider
    }

    /// Start the service on launch if the user previously enabled it.
    func startIfEnabled() async {
        guard isEnabled, !isRunning else { return }
        await start()
    }

    // MARK: - Lifecycle

    /// Build (create or restore) the NWC service and start listening.
    func start() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        guard let mintUrl = selectedMintUrl, !mintUrl.isEmpty else {
            errorMessage = "Select a mint to use with Nostr Wallet Connect."
            setEnabled(false)
            return
        }

        guard let seed = seedProvider?(), seed.count >= 64 else {
            errorMessage = "Wallet seed is not available yet. Try again in a moment."
            return
        }

        guard !relays.isEmpty else {
            errorMessage = "Add at least one Nostr relay before enabling NWC."
            setEnabled(false)
            return
        }

        // Tear down any previous instance first.
        await stopService()

        do {
            let serviceSecretKey = try nwcDeriveServiceSecretKeyFromSeed(seed: seed)
            let wallet = try await resolveWallet(mintUrl: mintUrl)
            let budgetMsat = budgetSats.map { $0 * 1000 }

            let svc: NwcService
            if let uri = connectionUri,
               let clientSecret = Self.clientSecret(fromConnectionUri: uri) {
                // Reuse the existing connection so the previously shared URI keeps working.
                svc = try NwcService.restore(
                    wallet: wallet,
                    relays: relays,
                    serviceSecretKey: serviceSecretKey,
                    clientSecretKey: clientSecret,
                    budgetMsat: budgetMsat
                )
            } else {
                svc = try NwcService.create(
                    wallet: wallet,
                    relays: relays,
                    serviceSecretKey: serviceSecretKey,
                    budgetMsat: budgetMsat
                )
                connectionUri = svc.connectionUri()
            }

            try await svc.start()
            service = svc
            isRunning = svc.isRunning()
        } catch {
            isRunning = false
            service = nil
            errorMessage = error.userFacingWalletMessage
            AppLogger.wallet.error("Failed to start NWC service: \(String(describing: error))")
        }
    }

    /// Stop the service but keep the configuration (URI, mint, budget) so it can
    /// be re-enabled later with the same connection.
    func stop() async {
        isBusy = true
        defer { isBusy = false }
        await stopService()
    }

    /// Generate a brand-new connection (fresh client secret → new URI). Any app
    /// paired with the old URI stops working.
    func regenerateConnection() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        await stopService()
        connectionUri = nil

        if isEnabled {
            // start() handles its own busy flag; release ours first.
            isBusy = false
            await start()
        }
    }

    /// Reset all NWC state at a wallet boundary (create/restore/delete wallet).
    func resetForWalletBoundary() {
        Task { await stopService() }
        suppressSideEffects = true
        isEnabled = false
        connectionUri = nil
        selectedMintUrl = nil
        budgetSats = nil
        suppressSideEffects = false
        errorMessage = nil
    }

    // MARK: - Helpers

    private func restartService() async {
        guard !isBusy else { return }
        await start()
    }

    private func stopService() async {
        if let service {
            do {
                try await service.stop()
            } catch {
                AppLogger.wallet.error("Failed to stop NWC service: \(String(describing: error))")
            }
        }
        service = nil
        isRunning = false
    }

    private func resolveWallet(mintUrl: String) async throws -> Wallet {
        guard let walletProvider else {
            throw WalletError.notInitialized
        }
        return try await walletProvider(mintUrl)
    }

    /// Set `isEnabled` without re-triggering the start/stop side effects. Used
    /// when an internal guard fails and we must reflect "off" in the UI.
    private func setEnabled(_ value: Bool) {
        suppressSideEffects = true
        isEnabled = value
        suppressSideEffects = false
    }

    /// Extract the `secret` (client secret key) from a `nostr+walletconnect://` URI.
    static func clientSecret(fromConnectionUri uri: String) -> String? {
        if let components = URLComponents(string: uri),
           let secret = components.queryItems?.first(where: { $0.name == "secret" })?.value,
           !secret.isEmpty {
            return secret
        }

        // Fallback for schemes URLComponents fails to split: manual query parse.
        guard let queryStart = uri.firstIndex(of: "?") else { return nil }
        let query = uri[uri.index(after: queryStart)...]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0] == "secret" {
                return kv[1]
                    .removingPercentEncoding ?? String(kv[1])
            }
        }
        return nil
    }
}
