import Foundation
import Cdk

extension WalletManager {
    // MARK: - Mint Operations (Delegate to MintService)

    func addMint(url: String) async throws {
        try await mintService.addMint(url: url)
        await refreshBalance()
    }

    func removeMint(at offsets: IndexSet) async {
        await mintService.removeMint(at: offsets)
        await refreshBalance()
    }

    func setActiveMint(_ mint: MintInfo) async throws {
        try await mintService.setActiveMint(mint)
        await refreshBalance()
    }

    /// Whether the given mint URL is already tracked by the wallet.
    func isMintKnown(url: String) -> Bool {
        mintService.isMintTracked(url: url)
    }


    func refreshMintInfo() async {
        await mintService.refreshMintInfo()
    }

    /// Fetch full mint info from the mint's API via CashuDevKit
    func fetchFullMintInfo(mintUrl: String) async throws -> Cdk.MintInfo? {
        guard let walletRepository = walletRepository else {
            throw WalletError.notInitialized
        }
        let mintUrlObj = MintUrl(url: mintUrl)
        let wallet = try await walletRepository.getWallet(mintUrl: mintUrlObj, unit: .sat)
        return try await wallet.fetchMintInfo()
    }

    // MARK: - Balance Operations

    func refreshBalance() async {
        guard let walletRepository = walletRepository else { return }
        let mintUrls = trackedMintUrlsForWalletAccess()
        
        guard !mintUrls.isEmpty else {
            balance = 0
            return
        }
        
        var total: UInt64 = 0
        var balancesByMintURL: [String: UInt64] = [:]
        
        for mintUrlString in mintUrls {
            do {
                let mintUrl = MintUrl(url: mintUrlString)
                let wallet = try await walletRepository.getWallet(mintUrl: mintUrl, unit: .sat)
                let walletBalance = try await wallet.totalBalance()
                
                total += walletBalance.value
                balancesByMintURL[mintUrlString] = walletBalance.value
            } catch {
                balancesByMintURL[mintUrlString] = 0
                AppLogger.wallet.error("Failed to refresh balance for mint \(mintUrlString): \(error)")
            }
        }
        
        mintService.updateMintBalances(balancesByMintURL)
        balance = total
    }
}
