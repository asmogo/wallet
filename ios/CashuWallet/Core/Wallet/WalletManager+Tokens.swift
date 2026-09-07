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

        // Keep the token string under its (stable, saga-derived) CDK
        // transaction id so History can re-display it and claim checks can
        // resolve the send operation. Lifecycle state lives in CDK itself.
        if let transactionId = result.transactionId {
            transactionService.saveToken(txId: transactionId, token: result.token)
        } else {
            AppLogger.wallet.warning("send completed without a transaction id resource=\(WalletOperationCoordinator.privacySafeIdentifier(tokenMintURL), privacy: .public)")
        }

        await refreshBalance()
        await loadTransactions()
        SentryService.breadcrumb("Token sent", category: "wallet.token")
        return result
    }

    /// Existing units for balance displays; payment options still use metadata.
    func storedAccountUnits(mintURL: String) async -> [String]? {
        guard let db, let repo = walletRepository else { return nil }
        return try? await operationCoordinator.perform(kind: .balance, resourceID: mintURL) {
            let accounts = try await StoredWalletAccount.discover(database: db, repository: repo)
            return Set(accounts.filter { $0.matches(mintURL: mintURL) }.map(\.unitName)).sorted()
        }
    }

    /// Balance of a durable account. Returns nil when storage is unavailable.
    func unitBalance(mintURL: String, unit: String) async -> UInt64? {
        if unit.lowercased() == "sat" {
            return mints.first(where: { $0.url == mintURL })?.balance
        }
        guard let db, let repo = walletRepository else { return nil }
        do {
            return try await operationCoordinator.perform(
                kind: .balance,
                resourceID: mintURL
            ) {
                let currencyUnit = PaymentRequestDecoder.currencyUnit(from: unit)
                let accounts = try await StoredWalletAccount.discover(database: db, repository: repo)
                    .filter { $0.unit == currencyUnit && $0.matches(mintURL: mintURL) }
                var total: UInt64 = 0
                for account in accounts {
                    total += try await db.getBalance(mintUrl: MintUrl(url: account.mintURL), unit: account.unit, state: [.unspent])
                }
                return total
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

                if let recoveryContext {
                    self.mintService.trackReceivedMintLocally(url: recoveryContext.mintURL, unit: recoveryContext.unit)
                }
                try? await self.ensureMintTrackedForToken(tokenString)
                return (amount, newTransactionID)
            } catch {
                await self.reconcileReceivedAccountsAssumingLease()
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

    // MARK: - Pending Receive Token Operations (Delegate to TransactionService)

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
    func checkPendingTokenStatus(transaction: WalletTransaction) async throws -> Bool {
        guard let sagaId = transaction.sagaId else {
            // App-synthesized rows carry no operation; fall back to a direct
            // proof-state probe against the mint.
            guard let token = transaction.token, let mintUrl = transaction.mintUrl else {
                return false
            }
            return try await checkTokenSpent(token: token, mintUrl: mintUrl)
        }
        let mintUrl = transaction.mintUrl ?? activeMint?.url ?? ""
        let claimed = try await operationCoordinator.perform(
            kind: .tokenStatus,
            resourceID: mintUrl
        ) {
            let unit = PaymentRequestDecoder.currencyUnit(from: transaction.unit)
            let wallet = try await self.walletRepository?.getWallet(
                mintUrl: MintUrl(url: mintUrl),
                unit: unit
            )
            guard let wallet else { throw WalletError.notInitialized }
            return try await wallet.checkSendStatus(operationId: sagaId)
        }
        if claimed {
            await loadTransactions()
        }
        return claimed
    }

    /// Manual claim check for a just-created send, where the caller only holds
    /// the token string (Send flow success screen).
    @discardableResult
    func checkSentTokenClaim(token: String, mintUrl: String, unit: String = "sat") async throws -> Bool {
        try await operationCoordinator.perform(kind: .tokenStatus, resourceID: mintUrl) {
            if let txId = self.transactionService.transactionId(forToken: token),
               let operationId = SagaTransactionId.operationId(fromTransactionIdHex: txId),
               let wallet = try? await self.walletRepository?.getWallet(
                   mintUrl: MintUrl(url: mintUrl),
                   unit: PaymentRequestDecoder.currencyUnit(from: unit)
               ),
               let claimed = try? await wallet.checkSendStatus(operationId: operationId) {
                return claimed
            }
            // The token predates transaction-id-keyed storage (or came from
            // elsewhere): probe the proofs directly.
            return try await self.tokenService.checkTokenSpent(token: token, mintUrl: mintUrl)
        }
    }

    /// Reclaim an unclaimed sent token: CDK swaps the proofs back and marks the
    /// transaction failed/revoked, so no local bookkeeping remains.
    func reclaimPendingSend(transaction: WalletTransaction) async throws -> UInt64 {
        guard let sagaId = transaction.sagaId else {
            throw WalletError.notInitialized
        }
        let mintUrl = transaction.mintUrl ?? activeMint?.url ?? ""
        let amount = try await operationCoordinator.perform(
            kind: .send,
            resourceID: mintUrl,
            protectsBackgroundExecution: true
        ) {
            let unit = PaymentRequestDecoder.currencyUnit(from: transaction.unit)
            let wallet = try await self.walletRepository?.getWallet(
                mintUrl: MintUrl(url: mintUrl),
                unit: unit
            )
            guard let wallet else { throw WalletError.notInitialized }
            return try await wallet.revokeSend(operationId: sagaId).value
        }
        await refreshBalance()
        await loadTransactions()
        return amount
    }

    func checkAllPendingTokens() async {
        guard walletRepository != nil else { return }

        do {
            try await operationCoordinator.performIfIdle(kind: .pendingTokenCheck) {
                var claimedAny = false
                var foundPending = false

                walletSweep: for wallet in await self.trackedWalletsAssumingWalletOperationLease() {
                    guard !Task.isCancelled else { break }
                    do {
                        for operationId in try await wallet.getPendingSends() {
                            foundPending = true
                            do {
                                if try await wallet.checkSendStatus(operationId: operationId) {
                                    claimedAny = true
                                }
                            } catch is CancellationError {
                                break walletSweep
                            } catch {
                                AppLogger.wallet.error(
                                    "pending send status check failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                                )
                            }
                            if await self.operationCoordinator.hasWaitingUserOperation() { break walletSweep }
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        AppLogger.wallet.error(
                            "pending send maintenance failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                        )
                    }
                }

                // No local rows to merge anymore: only a claim changes history.
                if claimedAny {
                    await self.refreshBalanceAssumingWalletOperationLease()
                    await self.loadTransactionsAssumingWalletOperationLease()
                } else if foundPending {
                    await self.loadTransactionsAssumingWalletOperationLease()
                }
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
