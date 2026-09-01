import Foundation
import CommonCrypto
import Cdk

extension WalletManager {
    // MARK: - Nostr & NPC Integration

    @discardableResult
    func initializeNostrKeypairLocally(mnemonic: String) -> Bool {
        do {
            // The app's Nostr identity is the NIP-06 key (m/44'/1237'/0'/0/0)
            // derived from the same 64-byte BIP39 seed WalletRepository uses.
            // Any NIP-06 Nostr client reproduces this npub from the mnemonic,
            // and it is the same key npub.cash uses.
            let walletSeed = try Self.bip39Seed(mnemonic: mnemonic)
            let nostrSecretKeyHex = try npubcashDeriveSecretKeyFromSeed(seed: walletSeed)
            guard let nostrSecretKey = Data(hexString: nostrSecretKeyHex) else {
                throw WalletError.notInitialized
            }
            try NostrService.shared.deriveKeypair(from: nostrSecretKey)
            try NPCService.shared.initializeWithSeed(walletSeed)
            return true
        } catch {
            AppLogger.security.error("Failed to initialize Nostr keypair: \(error)")
            return false
        }
    }

    /// BIP39 seed (PBKDF2-HMAC-SHA512, 2048 rounds, empty passphrase),
    /// matching cdk's `Mnemonic::to_seed_normalized("")`.
    private static func bip39Seed(mnemonic: String, passphrase: String = "") throws -> Data {
        let password = Array(mnemonic.decomposedStringWithCompatibilityMapping.utf8)
        let salt = Array(("mnemonic" + passphrase).decomposedStringWithCompatibilityMapping.utf8)
        var seed = [UInt8](repeating: 0, count: 64)

        let status = password.withUnsafeBytes { passwordBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.bindMemory(to: CChar.self).baseAddress,
                password.count,
                salt,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                2048,
                &seed,
                seed.count
            )
        }

        guard status == kCCSuccess else {
            throw WalletError.notInitialized
        }

        return Data(seed)
    }

    func setupNPCQuoteListener() {
        if let npcQuoteObserver {
            NotificationCenter.default.removeObserver(npcQuoteObserver)
        }
        
        npcQuoteObserver = NotificationCenter.default.addObserver(forName: .npcQuoteReceived, object: nil, queue: .main) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let mintQuote = userInfo["mintQuote"] as? MintQuote else { return }
            let spendingConditions = userInfo["spendingConditions"] as? SpendingConditions
            Task {
                await self.mintNPCQuote(
                    mintQuote: mintQuote,
                    spendingConditions: spendingConditions
                )
            }
        }
    }

    func mintNPCQuote(
        mintQuote: MintQuote,
        spendingConditions: SpendingConditions? = nil
    ) async {
        guard !processedQuotes.contains(mintQuote.id),
              !npcQuotesInFlight.contains(mintQuote.id) else { return }

        npcQuotesInFlight.insert(mintQuote.id)
        defer {
            npcQuotesInFlight.remove(mintQuote.id)
        }
        
        do {
            // The NPC poller can fire as the app backgrounds; hold a background-task
            // assertion so this SQLite-writing mint finishes before suspension.
            try await withBackgroundWriteAssertion("npc-mint-claim") {
                try await self.operationCoordinator.perform(
                    kind: .mint,
                    priority: .maintenance,
                    resourceID: mintQuote.id,
                    defaultFailureOutcome: .ambiguousFailure
                ) {
                    do {
                        guard let walletRepository = self.walletRepository else {
                            throw WalletError.notInitialized
                        }

                        let mintUrl = mintQuote.mintUrl
                        await self.mintService.ensureMintTracked(url: mintUrl.url)

                        if let db = self.db {
                            try await self.replaceStoredNPCMintQuote(mintQuote, in: db)
                        }

                        let wallet = try await walletRepository.getWallet(mintUrl: mintUrl, unit: .sat)

                        let proofs = try await wallet.mintUnified(
                            quoteId: mintQuote.id,
                            amountSplitTarget: SplitTarget.none,
                            spendingConditions: spendingConditions
                        )
                        let totalAmount = proofs.reduce(UInt64(0)) { $0 + $1.amount.value }

                        self.markNPCQuoteProcessed(mintQuote.id)

                        await self.refreshBalanceAssumingWalletOperationLease()
                        await self.loadTransactionsAssumingWalletOperationLease()
                        SentryService.breadcrumb("NPC quote minted", category: "wallet.npc")

                        NotificationCenter.default.post(
                            name: .cashuTokenReceived,
                            object: nil,
                            // Background receive: no receive sheet is up to confirm it, so
                            // ask the home beat to fire the "sats landed" haptic.
                            userInfo: ["amount": totalAmount, "source": "npub.cash", "homeHaptic": true]
                        )
                    } catch {
                        await self.captureWalletFailureDiagnostics(kind: .mint, quoteID: mintQuote.id)
                        await self.recoverWalletStateAfterFailureAssumingWalletOperationLease(
                            kind: .mint,
                            preferredMintURL: mintQuote.mintUrl.url
                        )
                        await self.captureWalletFailureDiagnostics(kind: .mint, quoteID: mintQuote.id)
                        throw error
                    }
                }
            }
        } catch {
            if isAlreadyIssuedMintError(error) {
                markNPCQuoteProcessed(mintQuote.id)
            } else {
                SentryService.capture(error)
            }
            AppLogger.wallet.error(
                "NPC quote mint failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(mintQuote.id), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
        }
    }

    private func replaceStoredNPCMintQuote(
        _ quote: MintQuote,
        in walletDatabase: WalletSqliteDatabase
    ) async throws {
        do {
            try await walletDatabase.addMintQuote(quote: quote)
        } catch {
            try await walletDatabase.removeMintQuote(quoteId: quote.id)
            try await walletDatabase.addMintQuote(quote: quote)
        }
    }

    private func markNPCQuoteProcessed(_ quoteId: String) {
        processedQuotes.insert(quoteId)
        walletStore.saveProcessedNPCQuotes(processedQuotes.sorted())
    }
}
