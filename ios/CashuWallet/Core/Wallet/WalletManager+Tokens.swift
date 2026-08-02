import Foundation
import Cdk

extension WalletManager {
    // MARK: - Token Operations (Delegate to TokenService)

    func sendTokens(
        amount: UInt64,
        memo: String? = nil,
        p2pkPubkey: String? = nil,
        mintUrl preferredMintURL: String? = nil,
        unit: String = "sat"
    ) async throws -> SendTokenResult {
        let currencyUnit = PaymentRequestDecoder.currencyUnit(from: unit)
        let recoveryMintURL = preferredMintURL ?? activeMint?.url
        let result = try await operationCoordinator.perform(
            kind: .send,
            resourceID: recoveryMintURL,
            protectsBackgroundExecution: true,
            defaultFailureOutcome: .ambiguousFailure
        ) {
            do {
                return try await self.tokenService.sendTokens(
                    amount: amount,
                    memo: memo,
                    p2pkPubkey: p2pkPubkey,
                    mintUrl: preferredMintURL,
                    unit: currencyUnit
                )
            } catch {
                await self.captureWalletFailureDiagnostics(kind: .send)
                await self.recoverWalletStateAfterFailureAssumingWalletOperationLease(
                    kind: .send,
                    preferredMintURL: recoveryMintURL,
                    unit: currencyUnit
                )
                await self.captureWalletFailureDiagnostics(kind: .send)
                throw error
            }
        }
        let tokenMintURL = recoveryMintURL ?? ""
        
        // Save pending token for tracking
        let tokenId = UUID().uuidString
        let pendingToken = PendingToken(
            tokenId: tokenId,
            token: result.token,
            amount: amount,
            fee: result.fee,
            date: Date(),
            mintUrl: tokenMintURL,
            memo: memo,
            unit: unit
        )
        transactionService.savePendingToken(pendingToken)
        
        await refreshBalance()
        await loadTransactions()
        SentryService.breadcrumb("Token sent", category: "wallet.token")
        return result
    }

    /// Balance of a specific (mint, unit) wallet, in that unit's base units.
    /// "sat" resolves from the cached per-mint balance; other units query CDK
    /// directly since the app doesn't cache non-sat balances. Returns nil on any
    /// failure (e.g. a mint that doesn't actually support the unit).
    func unitBalance(mintURL: String, unit: String) async -> UInt64? {
        if unit.lowercased() == "sat" {
            return mints.first(where: { $0.url == mintURL })?.balance
        }
        guard let repo = walletRepository else { return nil }
        do {
            return try await operationCoordinator.perform(
                kind: .balance,
                resourceID: mintURL
            ) {
                let mintUrl = MintUrl(url: mintURL)
                let currencyUnit = PaymentRequestDecoder.currencyUnit(from: unit)
                try await repo.createWallet(mintUrl: mintUrl, unit: currencyUnit, targetProofCount: nil)
                let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: currencyUnit)
                return try await wallet.totalBalance().value
            }
        } catch {
            AppLogger.wallet.debug(
                "unit balance failed unit=\(unit, privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            return nil
        }
    }

    func receiveTokens(tokenString: String) async throws -> UInt64 {
        let outcome = try await performTokenReceive(tokenString: tokenString)

        if let transactionID = outcome.transactionID {
            transactionService.saveToken(txId: transactionID, token: tokenString)
        }

        await refreshBalance()
        await loadTransactions()
        SentryService.breadcrumb("Token received", category: "wallet.token")
        return outcome.amount
    }

    /// Holds one repository lease across transaction attribution, redemption,
    /// and post-receive mint setup. This is the critical receive workflow used
    /// both by the review screen and automatic Cashu Request claims.
    private func performTokenReceive(
        tokenString: String
    ) async throws -> (amount: UInt64, transactionID: String?) {
        let recoveryContext: (mintURL: String, unit: Cdk.CurrencyUnit)? = {
            guard let token = try? tokenService.decodeToken(tokenString: tokenString),
                  let mintURL = try? token.mintUrl().url else { return nil }
            return (mintURL, token.unit() ?? .sat)
        }()

        return try await operationCoordinator.perform(
            kind: .receive,
            resourceID: recoveryContext?.mintURL,
            protectsBackgroundExecution: true,
            defaultFailureOutcome: .ambiguousFailure
        ) {
            do {
                // Receive first: tokenService creates the CDK wallet and consumes the
                // keyset counter. Enriching the mint (createWallet/fetchMintInfo) before
                // this desyncs the counter and makes the mint reject "duplicate outputs"
                // on the first attempt. Track/enrich the mint only after a successful
                // receive, so an unredeemed token never adds the mint either.
                let beforeIds = await self.incomingTxIds(forTokenString: tokenString)
                let amount = try await self.tokenService.receiveTokens(tokenString: tokenString)
                let newTransactionID = (await self.incomingTxIds(forTokenString: tokenString))
                    .subtracting(beforeIds)
                    .first

                try? await self.ensureMintTrackedForToken(tokenString)
                return (amount, newTransactionID)
            } catch {
                await self.captureWalletFailureDiagnostics(kind: .receive)
                await self.recoverWalletStateAfterFailureAssumingWalletOperationLease(
                    kind: .receive,
                    preferredMintURL: recoveryContext?.mintURL,
                    unit: recoveryContext?.unit ?? .sat
                )
                await self.captureWalletFailureDiagnostics(kind: .receive)
                throw error
            }
        }
    }

    /// Auto-claim a token that arrived via a NUT-18 Cashu Request, optionally attributing
    /// the payment to a specific request in CashuRequestStore.
    /// Identifies the CDK transaction id by diffing wallet.listTransactions() before
    /// and after the receive, then links it to the request so History can suppress
    /// the duplicate "Received ecash" row.
    @discardableResult
    func receiveCashuRequestPayment(tokenString: String, requestId: String?) async throws -> UInt64 {
        let outcome = try await performTokenReceive(tokenString: tokenString)
        if let transactionID = outcome.transactionID {
            transactionService.saveToken(txId: transactionID, token: tokenString)
        }

        if let requestId, let txId = outcome.transactionID {
            CashuRequestStore.shared.attachPayment(
                requestId: requestId,
                transactionId: txId,
                amount: outcome.amount
            )
        }

        await refreshBalance()
        await loadTransactions()
        SentryService.breadcrumb("Token received", category: "wallet.token")

        var userInfo: [String: Any] = ["amount": outcome.amount, "source": "cashu-request"]
        if let requestId { userInfo["requestId"] = requestId }
        NotificationCenter.default.post(
            name: .cashuTokenReceived,
            object: nil,
            userInfo: userInfo
        )
        return outcome.amount
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
            // Match the wallet the receive actually swapped into (the token's own
            // unit), so tx attribution works for non-sat receives too.
            let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: token.unit() ?? .sat)
            let txs = try await wallet.listTransactions(direction: .incoming)
            return Set(txs.map { $0.id.hex })
        } catch {
            AppLogger.wallet.debug(
                "incoming transaction attribution failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
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
        return try await operationCoordinator.perform(
            kind: .receiveFee,
            priority: .maintenance
        ) {
            try await self.tokenService.calculateReceiveFee(tokenString: tokenString)
        }
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
        let amount: UInt64
        if token.cashuRequestId != nil {
            // NUT-18 payment held for approval: claim through the attribution
            // path so History links it to the originating Cashu Request. An
            // empty id marks a listener-held payment whose payload carried no
            // request id — claim the same way, just without attribution.
            let requestId = token.cashuRequestId.flatMap { $0.isEmpty ? nil : $0 }
            amount = try await receiveCashuRequestPayment(
                tokenString: token.token,
                requestId: requestId
            )
        } else {
            amount = try await receiveTokens(tokenString: token.token)
        }
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
        do {
            return try await operationCoordinator.perform(
                kind: .tokenStatus,
                resourceID: resolvedMintUrl
            ) {
                await self.tokenService.checkTokenSpendable(token: token, mintUrl: resolvedMintUrl)
            }
        } catch {
            return false
        }
    }

    func checkTokenSpent(token: String, mintUrl: String) async throws -> Bool {
        try await operationCoordinator.perform(kind: .tokenStatus, resourceID: mintUrl) {
            try await self.tokenService.checkTokenSpent(token: token, mintUrl: mintUrl)
        }
    }

    @discardableResult
    func checkPendingTokenStatus(pendingToken: PendingToken) async throws -> Bool {
        let isSpent = try await checkTokenSpent(
            token: pendingToken.token,
            mintUrl: pendingToken.mintUrl
        )
        if isSpent {
            transactionService.markTokenAsClaimed(token: pendingToken.token)
            await loadTransactions()
        }
        return isSpent
    }

    func checkAllPendingTokens() async {
        // MainWalletView already loads history after the cached shell appears.
        // Avoid a second all-mint transaction pass on the common empty queue.
        guard !pendingTokens.isEmpty else { return }

        do {
            try await operationCoordinator.performIfIdle(kind: .pendingTokenCheck) {
                for token in self.pendingTokens {
                    do {
                        let isSpent = try await self.tokenService.checkTokenSpent(
                            token: token.token,
                            mintUrl: token.mintUrl
                        )
                        if isSpent {
                            self.transactionService.markTokenAsClaimed(token: token.token)
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        AppLogger.wallet.error(
                            "pending token status check failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                        )
                    }

                    if await self.operationCoordinator.hasWaitingUserOperation() {
                        break
                    }
                }
                await self.loadTransactionsAssumingWalletOperationLease()
            }
        } catch is CancellationError {
            return
        } catch {
            AppLogger.wallet.error(
                "pending token maintenance failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
        }
    }
}
