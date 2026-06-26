import Foundation
import Cdk

extension WalletManager {
    // MARK: - Nostr & NPC Integration

    @discardableResult
    func initializeNostrKeypairLocally(mnemonic: String) -> Bool {
        do {
            let seedData = Data(mnemonic.utf8).sha256()
            try NostrService.shared.deriveKeypair(from: seedData)
            try NPCService.shared.initializeWithSeed(seedData)
            return true
        } catch {
            AppLogger.security.error("Failed to initialize Nostr keypair: \(error)")
            return false
        }
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
                guard let walletRepository = walletRepository else {
                    throw WalletError.notInitialized
                }

                let mintUrl = mintQuote.mintUrl
                await mintService.ensureMintTracked(url: mintUrl.url)

                if let db {
                    try await replaceStoredNPCMintQuote(mintQuote, in: db)
                }

                let wallet = try await walletRepository.getWallet(mintUrl: mintUrl, unit: .sat)

                let proofs = try await wallet.mintUnified(
                    quoteId: mintQuote.id,
                    amountSplitTarget: SplitTarget.none,
                    spendingConditions: spendingConditions
                )
                let totalAmount = proofs.reduce(UInt64(0)) { $0 + $1.amount.value }

                markNPCQuoteProcessed(mintQuote.id)

                await refreshBalance()
                await loadTransactions()
                SentryService.breadcrumb("NPC quote minted", category: "wallet.npc")

                NotificationCenter.default.post(
                    name: .cashuTokenReceived,
                    object: nil,
                    userInfo: ["amount": totalAmount, "source": "npub.cash"]
                )
            }
        } catch {
            if isAlreadyIssuedMintError(error) {
                markNPCQuoteProcessed(mintQuote.id)
            } else {
                SentryService.capture(error)
            }
            AppLogger.wallet.error("Failed to mint NPC quote: \(error)")
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
