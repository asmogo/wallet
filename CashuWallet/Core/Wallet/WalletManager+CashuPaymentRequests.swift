import Foundation
import Cdk

extension WalletManager {
    // MARK: - Cashu Payment Requests

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
        let wallet = try await walletRepository.getWallet(mintUrl: MintUrl(url: selectedMint.url), unit: .sat)
        let customAmount = request.amount() == nil ? Amount(value: amount) : nil

        try await wallet.payRequest(paymentRequest: request, customAmount: customAmount)
        await refreshBalance()
        await loadTransactions()
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
}
