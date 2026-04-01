import Foundation
import CashuDevKit

// MARK: - Mint Service

/// Service responsible for mint management operations.
/// Handles adding, removing, and updating mint configurations.
@MainActor
class MintService: ObservableObject {
    
    // MARK: - Published Properties
    
    /// List of configured mints
    @Published var mints: [MintInfo] = []
    
    /// Currently active mint
    @Published var activeMint: MintInfo?
    
    /// Whether an operation is in progress
    @Published var isLoading = false
    
    // MARK: - Dependencies
    
    private let walletRepository: () -> WalletRepository?
    private let storageKey = "savedMints"
    
    // MARK: - Initialization
    
    init(walletRepository: @escaping () -> WalletRepository?) {
        self.walletRepository = walletRepository
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
        let mintUrlObj = try MintUrl(url: normalizedUrl)
        
        // Always call createWallet to ensure the unit is set
        try await repo.createWallet(mintUrl: mintUrlObj, unit: .sat, targetProofCount: nil)
        
        // Get wallet and fetch mint info
        let wallet = try await repo.getWallet(mintUrl: mintUrlObj, unit: .sat)
        let info = try await wallet.fetchMintInfo()
        
        let mintInfo = MintInfo(
            url: normalizedUrl,
            name: info?.name ?? "Unknown Mint",
            description: info?.description,
            isActive: true,
            balance: 0
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
            if let mintUrl = try? MintUrl(url: mint.url) {
                try? await repo.removeWallet(mintUrl: mintUrl, currencyUnit: .sat)
            }
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
    
    /// Load mints from persistent storage
    func loadMints() async {
        guard let repo = walletRepository() else { return }
        
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            do {
                mints = try JSONDecoder().decode([MintInfo].self, from: data)
                
                // Add each mint to wallet repository (with unit)
                // Always call addMint to ensure the unit is set, even if mint exists
                for mint in mints {
                    do {
                        let mintUrl = try MintUrl(url: mint.url)
                        // Call createWallet even if hasMint returns true, to ensure unit is set
                        try await repo.createWallet(mintUrl: mintUrl, unit: .sat, targetProofCount: nil)
                    } catch {
                        AppLogger.wallet.error("Failed to add mint \(mint.url): \(error)")
                    }
                }
                
                // Set first mint as active if none set
                if activeMint == nil, let firstMint = mints.first {
                    activeMint = firstMint
                }
            } catch {
                AppLogger.wallet.error("Failed to load mints: \(error)")
            }
        }
    }
    
    /// Update balance for a specific mint
    func updateMintBalance(url: String, balance: UInt64) {
        let normalizedUrl = normalizeUrl(url)
        if let index = mints.firstIndex(where: { $0.url == normalizedUrl }) {
            mints[index].balance = balance
            if activeMint?.url == normalizedUrl {
                activeMint = mints[index]
            }
            saveMints()
        }
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
    
    /// Normalize a mint URL
    private func normalizeUrl(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        return normalized
    }

    /// Validate that a mint URL uses HTTPS
    func validateMintUrl(_ url: String) -> String? {
        let normalized = normalizeUrl(url)
        guard let parsedUrl = URL(string: normalized), parsedUrl.host != nil else {
            return "Invalid URL format."
        }
        guard parsedUrl.scheme == "https" else {
            return "Mint URL must use HTTPS for security."
        }
        return nil
    }
    
    /// Save mints to persistent storage
    func saveMints() {
        do {
            let data = try JSONEncoder().encode(mints)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            AppLogger.wallet.error("Failed to save mints: \(error)")
        }
    }
}
