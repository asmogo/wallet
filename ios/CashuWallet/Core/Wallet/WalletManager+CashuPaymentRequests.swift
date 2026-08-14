import Foundation
import Cdk

/// How a scanned/pasted Cashu payment request should be paid, decided against
/// what the wallet currently holds. Shared by the home scanner, the Send flow,
/// and NFC so all three route identically.
enum CashuRequestRoute {
    /// A held mint can satisfy the request now — land on the creq pay screen.
    case payWithEcash(CashuPaymentRequestSummary)
    /// Can't pay from ecash, but a BIP-321 bolt11 fallback rides along — hand the
    /// normalized invoice to the existing Lightning melt flow (the recipient
    /// offered it for exactly this).
    case payBolt11Fallback(String)
    /// Can't pay from ecash and no bolt11 fallback — land on the creq screen so
    /// the user can add the required mint and fund it ("Add & pay").
    case acquireThenPay(CashuPaymentRequestSummary)
}

/// User-visible explanation for a Cashu Request route that materially changes
/// rails or requires recovery. The ordinary compatible-mint path intentionally
/// maps to nil so confirmations do not repeat the mint selector as "Pay from".
enum CashuRequestRouteExplanation: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case compatibleMint
        case lightningFallback
        case addRequestedMint(targetMintURL: String?)
        case topUpTargetMint(targetMintURL: String?)
        case unavailable
    }

    case lightningFallback
    case addRequestedMint(target: String?)
    case topUpTargetMint(target: String?)

    init?(state: State) {
        switch state {
        case .compatibleMint, .unavailable:
            return nil
        case .lightningFallback:
            self = .lightningFallback
        case .addRequestedMint(let targetMintURL):
            self = .addRequestedMint(target: Self.displayTarget(from: targetMintURL))
        case .topUpTargetMint(let targetMintURL):
            self = .topUpTargetMint(target: Self.displayTarget(from: targetMintURL))
        }
    }

    /// Localized row value shared by confirmation and terminal status screens.
    var localizedValue: String {
        switch self {
        case .lightningFallback:
            return String(localized: "Lightning fallback")
        case .addRequestedMint(let target):
            if let target {
                return String(localized: "Add requested mint: \(target)")
            }
            return String(localized: "Add requested mint")
        case .topUpTargetMint(let target):
            if let target {
                return String(localized: "Top up target mint: \(target)")
            }
            return String(localized: "Top up target mint")
        }
    }

    private static func displayTarget(from rawURL: String?) -> String? {
        guard let rawURL else { return nil }
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let components = URLComponents(string: trimmed) else {
            return trimmed
        }
        if let host = components.host, !host.isEmpty {
            if let port = components.port {
                return "\(host):\(port)"
            }
            return host
        }
        // A malformed absolute URL is not useful payment context. A bare mint
        // name remains useful and is kept as a safe fallback.
        return components.scheme == nil ? trimmed : nil
    }
}

/// Progress checkpoints for the "Add mint & pay" flow, driven back to the
/// confirm screen's overlay so the user sees what's happening.
enum AddMintPayStage: Equatable {
    case addingMint, preparingTransfer, waitingForPayment, minting, paying
}

/// Thrown by the acquire-then-pay flow when no held mint can bankroll the
/// transfer. Carries the already-created target mint quote so the caller can
/// present a Lightning top-up QR and finish once it's paid.
struct NeedsExternalTopUp: Error {
    let targetQuote: MintQuoteInfo
    let targetMintURL: String
    let mintAmount: UInt64
}

/// Thrown when the Lightning payment landed but the mint hasn't issued proofs
/// yet — a soft, self-healing state (History refresh / claim retries finish it).
struct MintSettling: Error {}

extension WalletManager {
    // MARK: - Cashu Payment Requests

    /// Whether a held mint can satisfy `summary` from ecash right now. Mirrors the
    /// candidate selection in `selectMint(forCashuPaymentRequest:...)`: filter
    /// held mints to the requested hosts (empty = any mint), then check balance.
    /// Amountless requests are fulfillable as long as some candidate is held —
    /// the pay screen enforces per-mint affordability once an amount is entered.
    func canFulfillFromEcash(_ summary: CashuPaymentRequestSummary) -> Bool {
        guard summary.isSatUnit else { return false }

        let candidates: [MintInfo]
        if summary.mints.isEmpty {
            candidates = mints
        } else {
            let requestedHosts = Set(summary.mints.map(normalizedMintURL))
            candidates = mints.filter { requestedHosts.contains(normalizedMintURL($0.url)) }
        }

        guard !candidates.isEmpty else { return false }

        if let amount = summary.amount, amount > 0 {
            return candidates.contains { $0.balance >= amount }
        }
        return true
    }

    /// The single routing decision: prefer ecash when a held mint can pay; else
    /// fall back to a bundled bolt11; else offer to add the mint and fund it.
    func routeForCashuPaymentRequest(
        _ summary: CashuPaymentRequestSummary,
        rawContent: String
    ) -> CashuRequestRoute {
        if canFulfillFromEcash(summary) {
            return .payWithEcash(summary)
        }
        if let bolt11 = PaymentRequestDecoder.encodedLightningRequest(from: rawContent) {
            return .payBolt11Fallback(bolt11)
        }
        return .acquireThenPay(summary)
    }

    func payCashuPaymentRequest(
        encoded: String,
        customAmountSats: UInt64? = nil,
        preferredMintURL: String? = nil
    ) async throws {
        let request = try PaymentRequestDecoder.parseCashuPaymentRequest(encoded)
        try await payCashuPaymentRequest(
            request,
            customAmountSats: customAmountSats,
            preferredMintURL: preferredMintURL
        )
    }

    func payCashuPaymentRequest(
        _ request: Cdk.PaymentRequest,
        customAmountSats: UInt64? = nil,
        preferredMintURL: String? = nil
    ) async throws {
        guard let walletRepository else {
            throw WalletError.notInitialized
        }

        if let unit = request.unit() {
            guard case .sat = unit else {
                throw NFCPaymentError.unsupportedUnit(PaymentRequestDecoder.unitDescription(unit))
            }
        }

        let requestedAmount = request.amount()?.value ?? customAmountSats
        guard let amount = requestedAmount, amount > 0 else {
            throw NFCPaymentError.noAmountSpecified
        }

        let selectedMint = try selectMint(
            forCashuPaymentRequest: request,
            amount: amount,
            preferredMintURL: preferredMintURL
        )
        try await operationCoordinator.perform(
            kind: .send,
            resourceID: selectedMint.url,
            protectsBackgroundExecution: true,
            defaultFailureOutcome: .ambiguousFailure
        ) {
            do {
                let wallet = try await walletRepository.getWallet(
                    mintUrl: MintUrl(url: selectedMint.url),
                    unit: .sat
                )
                let customAmount = request.amount() == nil ? Amount(value: amount) : nil

                try await wallet.payRequest(paymentRequest: request, customAmount: customAmount)
                await self.refreshBalanceAssumingWalletOperationLease()
                await self.loadTransactionsAssumingWalletOperationLease()
            } catch {
                await self.captureWalletFailureDiagnostics(kind: .send)
                await self.recoverWalletStateAfterFailureAssumingWalletOperationLease(
                    kind: .send,
                    preferredMintURL: selectedMint.url
                )
                await self.captureWalletFailureDiagnostics(kind: .send)
                throw error
            }
        }
    }

    // MARK: - Fee estimation (for the pay-request screen)

    /// The active keyset's input fee (parts per thousand proofs) for `mintURL`,
    /// or nil if it can't be read. A value of 0 means the mint charges no swap
    /// fee, so paying a request from it is always free regardless of amount —
    /// the common case, which the UI can resolve without a `prepareSend`.
    func mintInputFeePpk(mintURL: String) async -> UInt64? {
        guard let walletRepository else { return nil }
        do {
            return try await operationCoordinator.perform(
                kind: .feeEstimate,
                resourceID: mintURL,
                defaultFailureOutcome: .ambiguousFailure
            ) {
                let wallet = try await walletRepository.getWallet(mintUrl: MintUrl(url: mintURL), unit: .sat)
                let keysets = try await wallet.keysets(policy: .refresh).map {
                    KeySetInfo(id: $0.id, unit: $0.unit, active: $0.active ?? false, inputFeePpk: $0.inputFeePpk)
                }
                let active = keysets.first(where: { $0.active }) ?? keysets.first
                return active?.inputFeePpk
            }
        } catch {
            return nil
        }
    }

    /// Exact total fee (sats) to pay `amountSats` from `mintURL`, or nil if it
    /// can't be determined. Used only for the rare fee-charging mint, where the
    /// fee depends on coin selection: we `prepareSend` to read the real fee and
    /// immediately `cancel()` so no proofs stay reserved.
    ///
    /// Must mirror CDK's `pay_request`, which prepares with `includeFee: true`
    /// (the token carries the recipient's redeem fee on top of the requested
    /// amount). Estimating with `includeFee: false` here previously reported
    /// only the swap fee — "No fee" while the actual pay debited amount + fee.
    func estimateCashuPaymentFee(amountSats: UInt64, mintURL: String) async -> UInt64? {
        guard let walletRepository, amountSats > 0 else { return nil }
        do {
            return try await operationCoordinator.perform(
                kind: .feeEstimate,
                resourceID: mintURL
            ) {
                do {
                    let wallet = try await walletRepository.getWallet(mintUrl: MintUrl(url: mintURL), unit: .sat)
                    let options = SendOptions(
                        memo: nil,
                        conditions: nil,
                        amountSplitTarget: SplitTarget.none,
                        sendKind: SendKind.onlineExact,
                        includeFee: true,
                        useP2bk: false,
                        maxProofs: nil,
                        metadata: [:],
                        p2pkSigningKeys: [],
                        p2pkLockedProofSendMode: .swap
                    )
                    let prepared = try await wallet.prepareSend(amount: Amount(value: amountSats), options: options)
                    let fee = prepared.fee().value
                    try await prepared.cancel()
                    return fee
                } catch {
                    await self.captureWalletFailureDiagnostics(kind: .feeEstimate)
                    await self.recoverWalletStateAfterFailureAssumingWalletOperationLease(
                        kind: .feeEstimate,
                        preferredMintURL: mintURL
                    )
                    await self.captureWalletFailureDiagnostics(kind: .feeEstimate)
                    throw error
                }
            }
        } catch {
            return nil
        }
    }

    private func selectMint(
        forCashuPaymentRequest request: Cdk.PaymentRequest,
        amount: UInt64,
        preferredMintURL: String?
    ) throws -> MintInfo {
        let requested = request.mints()
        let candidates: [MintInfo]

        if requested.isEmpty {
            candidates = mints
        } else {
            let requestedHosts = Set(requested.map(normalizedMintURL))
            candidates = mints.filter { requestedHosts.contains(normalizedMintURL($0.url)) }
        }

        guard !candidates.isEmpty else {
            throw NFCPaymentError.noMatchingMint(requestedMints: requested)
        }

        if let preferredMintURL,
           let preferredMint = candidates.first(where: {
               normalizedMintURL($0.url) == normalizedMintURL(preferredMintURL)
           }) {
            guard preferredMint.balance >= amount else {
                throw NFCPaymentError.insufficientBalance(required: amount, available: preferredMint.balance)
            }

            return preferredMint
        }

        if let activeMint,
           let preferredMint = candidates.first(where: {
               normalizedMintURL($0.url) == normalizedMintURL(activeMint.url)
           }),
           preferredMint.balance >= amount {
            return preferredMint
        }

        guard let selectedMint = candidates.first(where: { $0.balance >= amount }) else {
            let available = candidates.map(\.balance).max() ?? 0
            throw NFCPaymentError.insufficientBalance(required: amount, available: available)
        }

        return selectedMint
    }

    private func normalizedMintURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        var normalized = host
        if let port = url.port {
            normalized += ":\(port)"
        }
        normalized += url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized
    }

    // MARK: - Add mint & pay (acquire ecash at an unheld mint, then pay)

    /// A held mint (other than the target) that can bankroll a Lightning transfer
    /// of `amount` into the target mint. Highest balance first; final
    /// affordability (incl. the melt fee reserve) is confirmed by `createMeltQuote`.
    private func fundingSourceMint(excluding targetMintURL: String, amount: UInt64) -> MintInfo? {
        let targetHost = normalizedMintURL(targetMintURL)
        return mints
            .filter { normalizedMintURL($0.url) != targetHost }
            .filter { $0.supportedMeltMethods.contains(.bolt11) }
            .filter { $0.balance >= amount }
            .max { $0.balance < $1.balance }
    }

    /// Whether some held mint could fund an `amount`-sat transfer into `targetMintURL`.
    /// Lets the confirm screen choose between the cross-mint path and a top-up QR
    /// (and word the fee row) before committing.
    func hasFundingSource(excluding targetMintURL: String, amount: UInt64) -> Bool {
        fundingSourceMint(excluding: targetMintURL, amount: amount) != nil
    }

    /// Add the required mint, acquire `amount` sats of ecash there, then pay the
    /// request. Funds the target by transferring from a held mint over Lightning
    /// (cross-mint swap). If no held mint can fund it, throws `NeedsExternalTopUp`
    /// carrying the target mint quote so the caller can show a top-up QR instead.
    /// `onStage` drives the caller's progress UI.
    func addMintAndPayCashuRequest(
        _ summary: CashuPaymentRequestSummary,
        amount: UInt64,
        targetMintURL: String,
        onStage: (AddMintPayStage) -> Void
    ) async throws {
        // 1. Commit the mint to the wallet so the final pay can select it.
        onStage(.addingMint)
        try await operationCoordinator.perform(
            kind: .addMint,
            resourceID: targetMintURL
        ) {
            await self.mintService.ensureMintTracked(url: targetMintURL)
        }

        // 2. Cover the target's input fee (if any) so the minted proofs can still
        //    send exactly `amount`. Virtually all mints charge 0 → no buffer.
        let ppk = await mintInputFeePpk(mintURL: targetMintURL) ?? 0
        let mintAmount = ppk == 0 ? amount : amount + max(1, (ppk * 32 + 999) / 1000)

        // 3. Mint quote at the TARGET mint → the bolt11 we must pay.
        onStage(.preparingTransfer)
        let targetQuote = try await createMintQuote(
            amount: mintAmount, method: .bolt11, targetMintURL: targetMintURL
        )

        // 4-5. Fund it from a held mint, or hand off to an external top-up.
        guard let source = fundingSourceMint(excluding: targetMintURL, amount: mintAmount) else {
            throw NeedsExternalTopUp(targetQuote: targetQuote, targetMintURL: targetMintURL, mintAmount: mintAmount)
        }

        let meltQuote: MeltQuoteInfo
        do {
            meltQuote = try await createMeltQuote(request: targetQuote.request, preferredMintURL: source.url)
        } catch let error as NFCPaymentError {
            // Source can't actually cover amount + fee reserve → top up externally.
            if case .insufficientBalance = error {
                throw NeedsExternalTopUp(targetQuote: targetQuote, targetMintURL: targetMintURL, mintAmount: mintAmount)
            }
            throw error
        }

        // 6. Pay the target's invoice from the source mint.
        onStage(.waitingForPayment)
        _ = try await meltTokens(quoteId: meltQuote.id, mintUrl: source.url)

        // 7-9. Mint the proofs at the target and pay the request (shared tail).
        onStage(.minting)
        try await finishTopUpAndPayCashuRequest(
            summary,
            amount: amount,
            targetMintURL: targetMintURL,
            targetQuoteId: targetQuote.id
        )
    }

    /// Mint the proofs for a now-paid target quote and pay the request. Shared by
    /// the cross-mint path and the external top-up (`CashuTopUpInvoiceSheet`). If
    /// the mint hasn't issued proofs in time, the pay fails with insufficient
    /// balance → surfaced as `MintSettling` so the caller shows a soft "settling"
    /// state rather than a hard error (the pending quote mints later).
    func finishTopUpAndPayCashuRequest(
        _ summary: CashuPaymentRequestSummary,
        amount: UInt64,
        targetMintURL: String,
        targetQuoteId: String
    ) async throws {
        _ = await mintWithRetries(quoteId: targetQuoteId)
        do {
            try await payCashuPaymentRequest(
                encoded: summary.encoded,
                customAmountSats: summary.amount == nil ? amount : nil,
                preferredMintURL: targetMintURL
            )
        } catch {
            if error.isInsufficientBalanceError { throw MintSettling() }
            throw error
        }
    }

    /// Mint proofs for a paid quote, retrying so a slow/settling mint doesn't fail
    /// the whole flow. Returns false if all attempts are exhausted (the pending
    /// quote is minted later by `claimPaidMintQuote`/History refresh).
    private func mintWithRetries(quoteId: String) async -> Bool {
        for attempt in 0..<8 {
            do {
                _ = try await mintTokens(quoteId: quoteId)
                return true
            } catch {
                if attempt < 7 { try? await Task.sleep(nanoseconds: 2_500_000_000) }
            }
        }
        return false
    }
}
