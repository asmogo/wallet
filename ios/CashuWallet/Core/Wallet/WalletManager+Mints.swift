import Foundation
import Cdk

extension WalletManager {
    /// Stored accounts remain authoritative even if a mint stops advertising
    /// a currency. Include every tracked account in recovery and settlement.
    func trackedWalletsAssumingWalletOperationLease() async -> [Wallet] {
        guard let walletRepository else { return [] }
        let tracked = trackedMintUrlsForWalletAccess().map(MintURLIdentity.normalized)
        return await walletRepository.getWallets()
            .filter { tracked.contains(MintURLIdentity.normalized($0.mintUrl().url)) }
            .sorted {
                (tracked.firstIndex(of: MintURLIdentity.normalized($0.mintUrl().url)) ?? .max)
                    < (tracked.firstIndex(of: MintURLIdentity.normalized($1.mintUrl().url)) ?? .max)
            }
    }

    // MARK: - Mint Operations (Delegate to MintService)

    func addMint(url: String) async throws {
        let mint = try await operationCoordinator.perform(
            kind: .addMint,
            resourceID: url
        ) {
            try await self.mintService.addMint(url: url)
        }
        performICloudBackup()
        Task { await NostrMintBackupService.shared.backupCurrentMintsIfEnabled() }
        restoreAddedMintInBackground(url: mint.url)
        SentryService.breadcrumb("Mint added", category: "wallet.mint")
    }

    /// NUT-09 can take noticeably longer than connecting to a mint. Keep that
    /// recovery alive after the add sheet closes, then publish the recovered
    /// balance and history together. The second tracked-mint check prevents a
    /// completed restore from updating a mint the user removed meanwhile.
    private func restoreAddedMintInBackground(url: String) {
        Task { [weak self] in
            guard let self,
                  self.mintService.isMintTracked(url: url),
                  let walletRepository = self.walletRepository else {
                return
            }

            do {
                try await self.operationCoordinator.perform(
                    kind: .restore,
                    priority: .maintenance,
                    resourceID: url,
                    protectsBackgroundExecution: true
                ) {
                    let wallet = try await walletRepository.getWallet(
                        mintUrl: MintUrl(url: url),
                        unit: .sat
                    )
                    _ = try await wallet.restore()
                }

                guard self.mintService.isMintTracked(url: url) else { return }

                await self.refreshBalance()
                await self.loadTransactions()
                SentryService.breadcrumb("Mint restore completed", category: "wallet.mint")
            } catch {
                AppLogger.wallet.error(
                    "background restore failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(url), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }
    }

    @discardableResult
    func removeMint(_ mint: MintInfo) async -> Bool {
        errorMessage = nil
        do {
            try await operationCoordinator.perform(kind: .removeMint) {
                try await self.mintService.removeMint(mint)
            }
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.userFacingWalletMessage
            AppLogger.wallet.error(
                "remove mint failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            return false
        }
        await refreshBalance()
        performICloudBackup()
        Task { await NostrMintBackupService.shared.backupCurrentMintsIfEnabled() }
        SentryService.breadcrumb("Mint removed", category: "wallet.mint")
        return true
    }

    func setActiveMint(_ mint: MintInfo) async throws {
        try await operationCoordinator.perform(
            kind: .mintInfo,
            resourceID: mint.url
        ) {
            try await self.mintService.setActiveMint(mint)
        }
        await refreshBalance()
    }

    /// Whether the given mint URL is already tracked by the wallet.
    func isMintKnown(url: String) -> Bool {
        mintService.isMintTracked(url: url)
    }


    func refreshMintInfo() async {
        do {
            try await operationCoordinator.perform(kind: .mintInfo) {
                await self.mintService.refreshMintInfo()
            }
        } catch {
            // Cancellation is expected when the owning view disappears.
        }
    }

    /// Fetch full mint info from the mint's API via CashuDevKit
    func fetchFullMintInfo(mintUrl: String) async throws -> Cdk.MintInfo? {
        guard let walletRepository = walletRepository else {
            throw WalletError.notInitialized
        }
        return try await operationCoordinator.perform(kind: .mintInfo, resourceID: mintUrl) {
            let mintUrlObj = MintUrl(url: mintUrl)
            let wallet = try await walletRepository.getWallet(mintUrl: mintUrlObj, unit: .sat)
            return try await wallet.fetchMintInfo()
        }
    }

    /// Best-effort preview of a mint's identity (name, icon, payment methods),
    /// fetched through CashuDevKit. CDK requires a wallet entry before
    /// `fetchMintInfo()`, so this may prepare the mint in the CDK repository,
    /// but it does not add the mint to the app's saved mint list.
    func fetchMintPreviewInfo(url: String) async -> MintPreviewInfo? {
        guard let walletRepository else {
            return nil
        }

        let normalized = normalizePreviewMintUrl(url)
        let mintUrl = MintUrl(url: normalized)
        do {
            return try await operationCoordinator.perform(
                kind: .mintInfo,
                resourceID: normalized
            ) {
                if await !walletRepository.hasMint(mintUrl: mintUrl) {
                    try await walletRepository.createWallet(mintUrl: mintUrl, unit: .sat, targetProofCount: nil)
                }
                let wallet = try await walletRepository.getWallet(mintUrl: mintUrl, unit: .sat)
                guard let info = try await wallet.fetchMintInfo() else {
                    return nil
                }
                let mintMethods = info.nuts.nut04.methods.compactMap { PaymentMethodKind.from($0.method) }
                let meltMethods = info.nuts.nut05.methods.compactMap { PaymentMethodKind.from($0.method) }
                let methods = PaymentMethodKind.allCases.filter {
                    mintMethods.contains($0) || meltMethods.contains($0)
                }
                return MintPreviewInfo(name: info.name, iconUrl: info.iconUrl, methods: methods)
            }
        } catch {
            AppLogger.wallet.error(
                "mint preview failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(normalized), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            return nil
        }
    }

    private func normalizePreviewMintUrl(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.contains("://") {
            normalized = "https://" + normalized
        }
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Balance Operations
    func refreshBalance() async {
        do {
            try await operationCoordinator.perform(kind: .balance) {
                await self.refreshBalanceAssumingWalletOperationLease()
            }
        } catch {
            // Balance refresh is best effort. The coordinator already records
            // cancellation and timing without exposing wallet identifiers.
        }
    }

    /// Internal form for a higher-level workflow that already owns the shared
    /// repository lease. Never call this from an uncoordinated task.
    func refreshBalanceAssumingWalletOperationLease() async {
        guard let walletRepository = walletRepository else { return }
        let mintUrls = trackedMintUrlsForWalletAccess()
        
        guard !mintUrls.isEmpty else {
            balance = 0
            balancesByUnit = [:]
            walletStore.saveBalancesByUnit([:])
            return
        }

        var balancesByMintURL = Dictionary(uniqueKeysWithValues: mintUrls.map { ($0, UInt64(0)) })
        var unitTotals: [String: UInt64] = [:]
        var failedUnits: Set<String> = []
        let wallets = await walletRepository.getWallets()

        for mintURL in mintUrls {
            for wallet in wallets where MintURLIdentity.normalized(wallet.mintUrl().url) == MintURLIdentity.normalized(mintURL) {
                let unit = PaymentRequestDecoder.unitDescription(wallet.unit())
                do {
                    let amount = try await wallet.totalBalance().value
                    unitTotals[unit, default: 0] += amount
                    if unit == "sat" { balancesByMintURL[mintURL] = amount }
                } catch {
                    failedUnits.insert(unit)
                    if unit == "sat" {
                        balancesByMintURL[mintURL] = mints.first { $0.url == mintURL }?.balance ?? 0
                    }
                    AppLogger.wallet.error(
                        "balance refresh failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(mintURL), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                    )
                }
            }
        }
        guard !Task.isCancelled else { return }
        // A failed read is not a zero balance. Keep that unit's last complete
        // total until all of its accounts can be read successfully.
        for unit in failedUnits { unitTotals[unit] = balancesByUnit[unit] }
        mintService.updateMintBalances(balancesByMintURL)
        balance = unitTotals["sat"] ?? 0
        balancesByUnit = unitTotals
        walletStore.saveBalancesByUnit(unitTotals)
    }
}
