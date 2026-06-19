import Foundation
import Cdk

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
    func addMint(url: String) async throws {
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
    }
    
    /// Remove mints at the specified offsets
    func removeMint(at offsets: IndexSet) async {
        guard let repo = walletRepository() else { return }
        
        for index in offsets {
            let mint = mints[index]
            if activeMint?.url == mint.url {
                activeMint = mints.first { $0.url != mint.url }
            }
            
            // Remove from wallet repository
            let mintUrl = MintUrl(url: mint.url)
            try? await repo.removeWallet(mintUrl: mintUrl, currencyUnit: .sat)
        }
        mints.remove(atOffsets: offsets)
        saveMints()
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
                AppLogger.wallet.error("Failed to add mint \(mint.url): \(error)")
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
                AppLogger.wallet.error("Failed to refresh mint info for \(self.mints[i].url): \(error)")
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
    
    /// Add a mint if it doesn't exist (used for NPC and token receiving)
    func ensureMintExists(url: String, name: String? = nil) async {
        let normalizedUrl = normalizeUrl(url)
        
        guard !mints.contains(where: { $0.url == normalizedUrl }) else {
            return
        }
        
        let mintInfo = MintInfo(
            url: normalizedUrl,
            name: name ?? "Unknown Mint",
            description: nil,
            isActive: true,
            balance: 0
        )
        mints.append(mintInfo)
        saveMints()
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
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        if normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        return normalized
    }

    /// Validate that a mint URL uses http or https
    func validateMintUrl(_ url: String) -> String? {
        let normalized = normalizeUrl(url)
        guard let parsedUrl = URL(string: normalized), parsedUrl.host != nil else {
            return "Invalid URL format."
        }
        guard parsedUrl.scheme == "https" || parsedUrl.scheme == "http" else {
            return "Mint URL must use http or https."
        }
        return nil
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

            let mintMethods = supportedMintPaymentMethods(from: fetchedInfo.nuts.nut04.methods)
            if !mintMethods.isEmpty {
                mintInfo.supportedMintMethods = mintMethods
            }

            let meltMethods = supportedMeltPaymentMethods(from: fetchedInfo.nuts.nut05.methods)
            if !meltMethods.isEmpty {
                mintInfo.supportedMeltMethods = meltMethods
            }
        }

        if let confirmations = await fetchOnchainMintConfirmations(for: url) {
            mintInfo.onchainMintConfirmations = confirmations
        }

        mintInfo.lastUpdated = Date()
        return mintInfo
    }

    private func supportedMintPaymentMethods(from methods: [Cdk.MintMethodSettings]) -> [PaymentMethodKind] {
        let mappedMethods = methods
            .filter { isSatUnit($0.unit) }
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

    private func isSatUnit(_ unit: Cdk.CurrencyUnit) -> Bool {
        if case .sat = unit {
            return true
        }
        return false
    }

    private func fetchOnchainMintConfirmations(for url: String) async -> Int? {
        guard let infoURL = URL(string: "\(url)/v1/info") else {
            AppLogger.wallet.error("Invalid mint info URL for \(url)")
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: infoURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.wallet.error("Mint info request for \(url) returned a non-HTTP response")
                return nil
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                AppLogger.wallet.error("Mint info request for \(url) failed with status \(httpResponse.statusCode)")
                return nil
            }

            let rawInfo = try JSONDecoder().decode(RawMintInfoResponse.self, from: data)
            return rawInfo.nuts.nut04?.methods.first(where: {
                $0.method.lowercased() == PaymentMethodKind.onchain.rawValue
            })?.options?.confirmations
        } catch {
            AppLogger.wallet.error("Failed to fetch raw mint info for \(url): \(error)")
            return nil
        }
    }
}

private struct RawMintInfoResponse: Decodable {
    let nuts: Nuts

    struct Nuts: Decodable {
        let nut04: Nut04?

        enum CodingKeys: String, CodingKey {
            case nut04 = "4"
        }
    }

    struct Nut04: Decodable {
        let methods: [Method]
    }

    struct Method: Decodable {
        let method: String
        let options: Options?
    }

    struct Options: Decodable {
        let confirmations: Int?
    }
}
