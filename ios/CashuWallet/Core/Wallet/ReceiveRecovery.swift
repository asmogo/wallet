import Cdk
import Foundation

/// Durable evidence of a receipt account, without copying bearer tokens out of CDK.
struct ReceiveRecoveryCandidate: Hashable {
    let mintURL: String
    let unit: CurrencyUnit

    static func fromSaga(_ json: String) -> Self? {
        struct Identity: Decodable {
            let kind: String
            let mint_url: String
            let unit: String
        }
        guard let data = json.data(using: .utf8),
              let identity = try? JSONDecoder().decode(Identity.self, from: data),
              identity.kind == "receive" else { return nil }
        return Self(mintURL: identity.mint_url, unit: PaymentRequestDecoder.currencyUnit(from: identity.unit))
    }

    static func discover(database: WalletSqliteDatabase) async throws -> [Self] {
        let proofs = try await database.getProofs(mintUrl: nil, unit: nil, state: [.unspent, .reserved, .pending], spendingConditions: nil)
        let sagas = try await database.getIncompleteSagas()
        return Array(Set(proofs.map { Self(mintURL: $0.mintUrl.url, unit: $0.unit) } + sagas.compactMap(fromSaga)))
            .sorted { ($0.mintURL, PaymentRequestDecoder.unitDescription($0.unit)) < ($1.mintURL, PaymentRequestDecoder.unitDescription($1.unit)) }
    }
}

extension WalletManager {
    /// Own the repository lease before calling. CDK remains the recovery journal;
    /// preview wallets and app-side tokens awaiting approval provide no evidence.
    @discardableResult
    func reconcileReceivedAccountsAssumingLease() async -> Bool {
        guard let db, let walletRepository else { return false }
        let candidates: [ReceiveRecoveryCandidate]
        do { candidates = try await ReceiveRecoveryCandidate.discover(database: db) }
        catch {
            AppLogger.wallet.error("Unable to discover interrupted receipts")
            return false
        }
        for candidate in candidates {
            mintService.trackReceivedMintLocally(url: candidate.mintURL, unit: candidate.unit)
        }
        for candidate in candidates {
            guard !Task.isCancelled else { break }
            do {
                let wallets = await walletRepository.getWallets()
                if !wallets.contains(where: { MintRemovalPolicy.matches($0.mintUrl().url, candidate.mintURL) && $0.unit() == candidate.unit }) {
                    // createWallet builds a local handle; metadata is unnecessary.
                    try await walletRepository.createWallet(mintUrl: MintUrl(url: candidate.mintURL), unit: candidate.unit, targetProofCount: nil)
                }
                let wallet = try await walletRepository.getWallet(mintUrl: MintUrl(url: candidate.mintURL), unit: candidate.unit)
                _ = try await wallet.recoverIncompleteSagas()
            } catch {
                AppLogger.wallet.error("Receipt recovery remains pending")
            }
        }
        if !candidates.isEmpty {
            await refreshBalanceAssumingWalletOperationLease()
            await transactionService.loadTransactions(includeRemoteObservations: false)
        }
        // No original token redemption or second payment announcement.
        return !candidates.isEmpty
    }
}
