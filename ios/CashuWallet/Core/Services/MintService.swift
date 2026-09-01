import Foundation
import Cdk

enum MintRemovalPolicyError: LocalizedError {
    case multipleUnits

    var errorDescription: String? {
        switch self {
        case .multipleUnits:
            return "This mint uses multiple currency units and cannot be removed safely yet. Keep it connected and try again after updating the app."
        }
    }
}

@MainActor
enum MintRemovalPolicy {
    static func normalizedUnits(_ registeredUnits: [String]) -> [String] {
        let units = registeredUnits
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let unique = units.filter { seen.insert($0).inserted }
        return unique
    }

    /// The native repository has no atomic multi-unit removal API. Refuse
    /// before touching it rather than leave only part of a mint removed.
    static func removalUnit(registeredUnits: [String]) throws -> String? {
        let units = normalizedUnits(registeredUnits)
        guard units.count <= 1 else { throw MintRemovalPolicyError.multipleUnits }
        return units.first
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalizedMintURL(lhs) == normalizedMintURL(rhs)
    }

    static func removingMint(withURL targetURL: String, from mints: [MintInfo]) -> [MintInfo] {
        mints.filter { !matches($0.url, targetURL) }
    }

    private static func normalizedMintURL(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            return trimmed
        }

        // URL scheme and host are case-insensitive, but paths are not. Folding
        // the whole string could remove a distinct mint at `/Mint` when the
        // user selected `/mint`.
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        var path = components.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" {
            path = ""
        }
        components.percentEncodedPath = path
        return components.string ?? trimmed
    }

    /// Commit local mint metadata only after the native removal succeeds.
    static func removeBeforeCommit(
        mint: MintInfo,
        registeredUnits: [String],
        removeWallet: @escaping (String, String) async throws -> Void,
        commitMetadata: () -> Void
    ) async throws {
        let unit = try removalUnit(registeredUnits: registeredUnits)
        try Task.checkCancellation()
        if let unit {
            // An unstructured child does not inherit later cancellation from
            // this caller. Once native removal begins, await its definite
            // result and mirror a success into metadata before cancellation
            // can escape across the commit boundary.
            let nativeRemoval = Task { @MainActor in
                try await removeWallet(mint.url, unit)
            }
            try await nativeRemoval.value
        }
        // Native removal is the commit point. Mirror it into local metadata
        // before propagating cancellation that arrived during the native call.
        commitMetadata()
        try Task.checkCancellation()
    }
}

// MARK: - Mint Service

/// Service responsible for mint management operations.
/// Handles adding, removing, and updating mint configurations.
@MainActor
class MintService: ObservableObject {
    
    // MARK: - Published Properties
    
    /// List of configured mints
    @Published var mints: [MintInfo] = []
    
    /// Currently active mint
    @Published var activeMint: MintInfo? {
        didSet {
            persistActiveMint()
        }
    }
    
    /// Whether an operation is in progress
    @Published var isLoading = false
    
    // MARK: - Dependencies
    
    private let walletRepository: () -> WalletRepository?
    private let walletStore: WalletStore
    
    // MARK: - Initialization
    
    init(
        walletRepository: @escaping () -> WalletRepository?,
        walletStore: WalletStore = WalletStore()
    ) {
        self.walletRepository = walletRepository
        self.walletStore = walletStore
    }
    
    // MARK: - Public Methods
    
    /// Add a new mint to the wallet
    /// - Parameter url: The mint URL to add
    /// - Throws: WalletError if already exists or if initialization fails
    func addMint(url: String) async throws -> MintInfo {
        isLoading = true
        defer { isLoading = false }
        
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }
        
        // Normalize URL
        let normalizedUrl = normalizeUrl(url)

        // Validate HTTPS
        if let validationError = validateMintUrl(normalizedUrl) {
            throw WalletError.networkError(validationError)
        }

        // Check if already exists locally
        if mints.contains(where: { $0.url == normalizedUrl }) {
            throw WalletError.mintAlreadyExists
        }
        
        // Parse and add to wallet repository
        let mintUrlObj = MintUrl(url: normalizedUrl)
        
        // Always call createWallet to ensure the unit is set
        try await repo.createWallet(mintUrl: mintUrlObj, unit: .sat, targetProofCount: nil)
        
        // Get wallet and fetch mint info
        let wallet = try await repo.getWallet(mintUrl: mintUrlObj, unit: .sat)
        let info = try await wallet.fetchMintInfo()

        let mintInfo = await makeMintInfo(
            url: normalizedUrl,
            existing: nil,
            fetchedInfo: info
        )
        
        mints.append(mintInfo)
        saveMints()
        
        // Set as active if first mint
        if activeMint == nil {
            activeMint = mintInfo
        }

        return mintInfo
    }
    
    /// Remove one mint by stable identity. Array offsets can shift while this
    /// operation waits in the repository coordinator.
    func removeMint(_ requestedMint: MintInfo) async throws {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        guard let mint = mints.first(where: {
            MintRemovalPolicy.matches($0.url, requestedMint.url)
        }) else {
            throw WalletError.networkError("Mint is no longer tracked.")
        }
        let registeredUnits = await repo.getWallets()
            .filter { wallet in
                MintRemovalPolicy.matches(wallet.mintUrl().url, mint.url)
            }
            .map { PaymentRequestDecoder.unitDescription($0.unit()) }

        try await MintRemovalPolicy.removeBeforeCommit(
            mint: mint,
            registeredUnits: registeredUnits,
            removeWallet: { mintURL, unit in
                try await repo.removeWallet(
                    mintUrl: MintUrl(url: mintURL),
                    currencyUnit: PaymentRequestDecoder.currencyUnit(from: unit)
                )
            },
            commitMetadata: {
                self.mints = MintRemovalPolicy.removingMint(
                    withURL: mint.url,
                    from: self.mints
                )
                if let activeMint = self.activeMint,
                   MintRemovalPolicy.matches(activeMint.url, mint.url) {
                    self.activeMint = self.mints.first
                }
                self.saveMints()
            }
        )
    }
    
    /// Set the active mint
    func setActiveMint(_ mint: MintInfo) async throws {
        guard walletRepository() != nil else {
            throw WalletError.notInitialized
        }
        activeMint = mint
    }
    
    /// Load mints from persistent storage without touching the network-backed wallet repository.
    func loadCachedMints() {
        mints = walletStore.loadMints()
        restoreActiveMint()
    }

    /// Load mints from persistent storage and prepare matching wallet repository entries.
    func loadMints() async {
        loadCachedMints()
        await prepareLoadedMintsInRepository()
    }

    /// Prepare wallet repository entries for the currently loaded mints.
    func prepareLoadedMintsInRepository() async {
        guard let repo = walletRepository() else { return }
        
        // Add each mint to wallet repository (with unit)
        // Always call createWallet to ensure the unit is set, even if mint exists.
        for mint in mints {
            do {
                let mintUrl = MintUrl(url: mint.url)
                try await repo.createWallet(mintUrl: mintUrl, unit: .sat, targetProofCount: nil)
            } catch {
                AppLogger.wallet.error(
                    "add mint failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(mint.url), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }
    }

    func clearState() {
        mints = []
        activeMint = nil
        isLoading = false
    }
    
    /// Refresh mint info and payment capabilities for all configured mints.
    func refreshMintInfo() async {
        guard let repo = walletRepository() else { return }
        var updated = false

        for i in mints.indices {
            do {
                if try await refreshMintInfo(at: i, using: repo) {
                    updated = true
                }
            } catch {
                AppLogger.wallet.error(
                    "mint info refresh failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(self.mints[i].url), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }

        if updated {
            if let activeMintUrl = activeMint?.url,
               let refreshed = mints.first(where: { $0.url == activeMintUrl }) {
                activeMint = refreshed
            }
            saveMints()
        }
    }

    /// Update balance for a specific mint
    func updateMintBalance(url: String, balance: UInt64) {
        updateMintBalances([url: balance])
    }

    func updateMintBalances(_ balancesByURL: [String: UInt64]) {
        var normalizedBalances: [String: UInt64] = [:]
        for (url, balance) in balancesByURL {
            normalizedBalances[normalizeUrl(url)] = balance
        }
        var updated = false

        for index in mints.indices {
            let normalizedURL = normalizeUrl(mints[index].url)
            guard let balance = normalizedBalances[normalizedURL],
                  mints[index].balance != balance else {
                continue
            }
            mints[index].balance = balance
            updated = true
        }

        guard updated else { return }

        if let activeMintUrl = activeMint?.url,
           let refreshed = mints.first(where: { normalizeUrl($0.url) == normalizeUrl(activeMintUrl) }) {
            activeMint = refreshed
        }
        saveMints()
    }
    
    /// Whether a mint with the given URL is already tracked.
    func isMintTracked(url: String) -> Bool {
        mints.contains { $0.url == normalizeUrl(url) }
    }

    /// Ensure a mint discovered via an incoming token or NPC quote is tracked with
    /// full metadata (NUT-04/05 payment methods, on-chain confirmations), not a bare
    /// placeholder. Fetches mint info through the CDK wallet so the send/receive
    /// payment-method choosers reflect the mint's real capabilities.
    ///
    /// - A previously saved broken placeholder (no fetched metadata) is refreshed
    ///   in place rather than skipped.
    /// - The mint is set as active only when no active mint exists; an existing
    ///   user-selected active mint and the mint's balance are preserved.
    func ensureMintTracked(url: String, name: String? = nil) async {
        let normalizedUrl = normalizeUrl(url)
        let existingIndex = mints.firstIndex(where: { $0.url == normalizedUrl })

        // Already tracked with real metadata — nothing to do.
        if let existingIndex, !mintNeedsEnrichment(mints[existingIndex]) {
            return
        }

        guard let repo = walletRepository() else {
            // Repository not ready: fall back to a placeholder so the mint is at
            // least visible; it will be enriched on a later receive/refresh.
            if existingIndex == nil {
                appendPlaceholderMint(url: normalizedUrl, name: name)
            }
            return
        }

        do {
            let mintUrlObj = MintUrl(url: normalizedUrl)
            // Only create the CDK wallet if it isn't already present, so we never
            // reset an existing keyset counter mid-flight.
            if await !repo.hasMint(mintUrl: mintUrlObj) {
                try await repo.createWallet(mintUrl: mintUrlObj, unit: .sat, targetProofCount: nil)
            }
            let wallet = try await repo.getWallet(mintUrl: mintUrlObj, unit: .sat)
            let info = try await wallet.fetchMintInfo()
            let enriched = await makeMintInfo(
                url: normalizedUrl,
                existing: existingIndex.map { mints[$0] },
                fetchedInfo: info
            )

            if let existingIndex {
                mints[existingIndex] = enriched
            } else {
                mints.append(enriched)
            }
            saveMints()

            if activeMint == nil {
                activeMint = enriched
            }
        } catch {
            AppLogger.wallet.error(
                "Failed to enrich token-discovered mint resource=\(WalletOperationCoordinator.privacySafeIdentifier(normalizedUrl), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            if existingIndex == nil {
                appendPlaceholderMint(url: normalizedUrl, name: name)
            }
        }
    }

    /// A mint still carrying the default placeholder name has never had its
    /// metadata fetched and should be enriched.
    private func mintNeedsEnrichment(_ mint: MintInfo) -> Bool {
        mint.name == "Unknown Mint"
    }

    private func appendPlaceholderMint(url: String, name: String?) {
        let placeholder = MintInfo(
            url: url,
            name: name ?? "Unknown Mint",
            description: nil,
            isActive: true,
            balance: 0
        )
        mints.append(placeholder)
        saveMints()
        if activeMint == nil {
            activeMint = placeholder
        }
    }
    
    // MARK: - Private Methods

    private func refreshMintInfo(
        at index: Int,
        using repo: WalletRepository
    ) async throws -> Bool {
        let mintUrl = MintUrl(url: mints[index].url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let info = try await wallet.fetchMintInfo()
        let refreshedMint = await makeMintInfo(
            url: mints[index].url,
            existing: mints[index],
            fetchedInfo: info
        )

        guard refreshedMint != mints[index] else { return false }
        mints[index] = refreshedMint
        return true
    }
    
    /// Normalize a mint URL
    private func normalizeUrl(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if explicitUrlScheme(in: normalized) == nil {
            normalized = "https://" + normalized
        }
        if normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        return normalized
    }

    /// Validate that a mint URL uses http or https
    func validateMintUrl(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = explicitUrlScheme(in: trimmed),
           scheme != "https" && scheme != "http" {
            return "Mint URL must use http or https."
        }

        let normalized = normalizeUrl(url)
        guard let components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            return "Invalid URL format."
        }
        guard scheme == "https" || scheme == "http" else {
            return "Mint URL must use http or https."
        }
        guard isValidMintHost(host) else {
            return "Invalid URL format."
        }
        return nil
    }

    private func explicitUrlScheme(in url: String) -> String? {
        guard let schemeSeparator = url.range(of: "://") else {
            return nil
        }

        let scheme = String(url[..<schemeSeparator.lowerBound]).lowercased()
        guard !scheme.isEmpty,
              scheme.range(
                of: #"^[a-z][a-z0-9+.-]*$"#,
                options: .regularExpression
              ) != nil else {
            return nil
        }

        return scheme
    }

    private func isValidMintHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        if normalizedHost == "localhost" || normalizedHost.contains(":") {
            return true
        }

        if normalizedHost.range(
            of: #"^\d{1,3}(\.\d{1,3}){3}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        return normalizedHost.split(separator: ".").count >= 2
    }
    
    /// Save mints to persistent storage
    func saveMints() {
        walletStore.saveMints(mints)
    }

    private func restoreActiveMint() {
        let savedActiveMintUrl = walletStore.activeMintURL
        if let savedActiveMintUrl,
           let savedActiveMint = mints.first(where: { $0.url == savedActiveMintUrl }) {
            activeMint = savedActiveMint
        } else {
            activeMint = mints.first
        }
    }

    private func persistActiveMint() {
        walletStore.activeMintURL = activeMint?.url
    }

    private func makeMintInfo(
        url: String,
        existing: MintInfo?,
        fetchedInfo: Cdk.MintInfo?
    ) async -> MintInfo {
        var mintInfo = existing ?? MintInfo(
            url: url,
            name: fetchedInfo?.name ?? "Unknown Mint",
            description: fetchedInfo?.description,
            isActive: true,
            balance: 0,
            iconUrl: fetchedInfo?.iconUrl
        )

        if let fetchedInfo {
            mintInfo.name = fetchedInfo.name ?? mintInfo.name
            mintInfo.description = fetchedInfo.description ?? mintInfo.description
            mintInfo.iconUrl = fetchedInfo.iconUrl ?? mintInfo.iconUrl

            mintInfo.units = supportedUnits(from: fetchedInfo.nuts)
            mintInfo.mintUnits = mintableUnits(from: fetchedInfo.nuts)

            let mintMethods = supportedMintPaymentMethods(from: fetchedInfo.nuts.nut04.methods)
            if !mintMethods.isEmpty {
                mintInfo.supportedMintMethods = mintMethods
            }

            let meltMethods = supportedMeltPaymentMethods(from: fetchedInfo.nuts.nut05.methods)
            if !meltMethods.isEmpty {
                mintInfo.supportedMeltMethods = meltMethods
            }
        }

        mintInfo.lastUpdated = Date()
        return mintInfo
    }

    private func supportedMintPaymentMethods(from methods: [Cdk.MintMethodSettings]) -> [PaymentMethodKind] {
        // No unit filter: a mint that offers bolt11 only in a non-sat unit must
        // still surface the Lightning mint method (the unit is chosen separately).
        let mappedMethods = methods
            .compactMap { PaymentMethodKind.from($0.method) }
        return PaymentMethodKind.allCases.filter { mappedMethods.contains($0) }
    }

    private func supportedMeltPaymentMethods(from methods: [Cdk.MeltMethodSettings]) -> [PaymentMethodKind] {
        let mappedMethods = methods
            .filter { isSatUnit($0.unit) }
            .compactMap { PaymentMethodKind.from($0.method) }
        return PaymentMethodKind.allCases.filter { mappedMethods.contains($0) }
    }

    private func supportedUnits(from nuts: Cdk.Nuts) -> [String] {
        let units = (nuts.mintUnits + nuts.meltUnits)
            .map(PaymentRequestDecoder.unitDescription)
        let uniqueUnits = Array(Set(units)).sorted()
        return uniqueUnits.isEmpty ? ["sat"] : uniqueUnits
    }

    /// Units the mint can MINT (NUT-04) — used to gate the Receive unit selector
    /// so we never offer a melt-only unit for minting.
    private func mintableUnits(from nuts: Cdk.Nuts) -> [String] {
        let units = nuts.mintUnits.map(PaymentRequestDecoder.unitDescription)
        let uniqueUnits = Array(Set(units)).sorted()
        return uniqueUnits.isEmpty ? ["sat"] : uniqueUnits
    }

    private func isSatUnit(_ unit: Cdk.CurrencyUnit) -> Bool {
        if case .sat = unit {
            return true
        }
        return false
    }

}
