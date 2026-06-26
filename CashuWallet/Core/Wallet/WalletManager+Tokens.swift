import Foundation
import Cdk

extension WalletManager {
    // MARK: - Token Operations (Delegate to TokenService)

    func sendTokens(
        amount: UInt64,
        memo: String? = nil,
        p2pkPubkey: String? = nil,
        mintUrl preferredMintURL: String? = nil
    ) async throws -> SendTokenResult {
        let result = try await tokenService.sendTokens(
            amount: amount,
            memo: memo,
            p2pkPubkey: p2pkPubkey,
            mintUrl: preferredMintURL
        )
        let tokenMintURL = preferredMintURL ?? activeMint?.url ?? ""
        
        // Save pending token for tracking
        let tokenId = UUID().uuidString
        let pendingToken = PendingToken(
            tokenId: tokenId,
            token: result.token,
            amount: amount,
            fee: result.fee,
            date: Date(),
            mintUrl: tokenMintURL,
            memo: memo
        )
        transactionService.savePendingToken(pendingToken)
        
        await refreshBalance()
        await loadTransactions()
        SentryService.breadcrumb("Token sent", category: "wallet.token")
        return result
    }

    func receiveTokens(tokenString: String) async throws -> UInt64 {
        // Receive first: tokenService creates the CDK wallet and consumes the
        // keyset counter. Enriching the mint (createWallet/fetchMintInfo) before
        // this desyncs the counter and makes the mint reject "duplicate outputs"
        // on the first attempt. Track/enrich the mint only after a successful
        // receive, so an unredeemed token never adds the mint either.
        let amount = try await tokenService.receiveTokens(tokenString: tokenString)
        try? await ensureMintTrackedForToken(tokenString)
        await refreshBalance()
        await loadTransactions()
        SentryService.breadcrumb("Token received", category: "wallet.token")
        return amount
    }

    /// Auto-claim a token that arrived via a NUT-18 Cashu Request, optionally attributing
    /// the payment to a specific request in CashuRequestStore.
    /// Identifies the CDK transaction id by diffing wallet.listTransactions() before
    /// and after the receive, then links it to the request so History can suppress
    /// the duplicate "Received ecash" row.
    @discardableResult
    func receiveCashuRequestPayment(tokenString: String, requestId: String?) async throws -> UInt64 {
        let beforeIds = await incomingTxIds(forTokenString: tokenString)
        let amount = try await receiveTokens(tokenString: tokenString)
        let afterIds = await incomingTxIds(forTokenString: tokenString)
        let newTxId = afterIds.subtracting(beforeIds).first

        if let requestId, let txId = newTxId {
            CashuRequestStore.shared.attachPayment(
                requestId: requestId,
                transactionId: txId,
                amount: amount
            )
        }

        var userInfo: [String: Any] = ["amount": amount, "source": "cashu-request"]
        if let requestId { userInfo["requestId"] = requestId }
        NotificationCenter.default.post(
            name: .cashuTokenReceived,
            object: nil,
            userInfo: userInfo
        )
        return amount
    }

    /// Lists incoming transaction ids for the mint encoded in a token string.
    /// Used by `receiveCashuRequestPayment` to identify the CDK tx id created by
    /// the receive. Returns an empty set on any failure so the diff degrades to
    /// "could not attribute payment" rather than crashing the receive.
    private func incomingTxIds(forTokenString tokenString: String) async -> Set<String> {
        guard let repo = walletRepository else { return [] }
        do {
            let token = try Token.decode(encodedToken: tokenString)
            let mintUrl = try token.mintUrl()
            let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
            let txs = try await wallet.listTransactions(direction: .incoming)
            return Set(txs.map { $0.id.hex })
        } catch {
            AppLogger.wallet.debug("incomingTxIds lookup failed: \(String(describing: error))")
            return []
        }
    }

    func decodeToken(tokenString: String) throws -> Token {
        return try tokenService.decodeToken(tokenString: tokenString)
    }

    func calculateReceiveFee(tokenString: String) async throws -> UInt64 {
        // Fee preview must not track/enrich the mint: doing so adds it to the
        // visible mint list (hiding the "new mint" badge on a later scan) and
        // disturbs the keyset counter before the receive. tokenService creates
        // the throwaway CDK wallet entry it needs for the calculation itself.
        return try await tokenService.calculateReceiveFee(tokenString: tokenString)
    }

    // MARK: - Pending Token Operations (Delegate to TransactionService)

    func savePendingToken(_ pendingToken: PendingToken) {
        transactionService.savePendingToken(pendingToken)
    }

    func loadPendingTokens() {
        transactionService.loadPendingTokens()
    }

    func removePendingToken(tokenId: String) {
        transactionService.removePendingToken(tokenId: tokenId)
    }

    func markTokenAsClaimed(token: String) async {
        transactionService.markTokenAsClaimed(token: token)
        await loadTransactions()
    }

    func savePendingReceiveToken(_ token: PendingReceiveToken) {
        transactionService.savePendingReceiveToken(token)
    }

    func loadPendingReceiveTokens() {
        transactionService.loadPendingReceiveTokens()
    }

    func removePendingReceiveToken(tokenId: String) {
        transactionService.removePendingReceiveToken(tokenId: tokenId)
    }

    func claimPendingReceiveToken(_ token: PendingReceiveToken) async throws -> UInt64 {
        let amount = try await receiveTokens(tokenString: token.token)
        transactionService.removePendingReceiveToken(tokenId: token.tokenId)
        await loadTransactions()
        return amount
    }

    func loadClaimedTokens() {
        transactionService.loadClaimedTokens()
    }

    // MARK: - Token Status Checks

    func checkTokenSpendable(token: String, mintUrl: String? = nil) async -> Bool {
        let resolvedMintUrl = mintUrl ?? activeMint?.url ?? ""
        guard !resolvedMintUrl.isEmpty else { return false }
        return await tokenService.checkTokenSpendable(token: token, mintUrl: resolvedMintUrl)
    }

    func checkPendingTokenStatus(pendingToken: PendingToken) async {
        let isSpent = await checkTokenSpendable(token: pendingToken.token, mintUrl: pendingToken.mintUrl)
        if isSpent {
            transactionService.markTokenAsClaimed(token: pendingToken.token)
        }
    }

    func checkAllPendingTokens() async {
        for token in pendingTokens {
            await checkPendingTokenStatus(pendingToken: token)
        }
        await loadTransactions()
    }
}
