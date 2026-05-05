import CashuDevKit
import Foundation

enum NFCPaymentError: LocalizedError {
    case nfcUnavailable
    case invalidPaymentRequest(String)
    case noAmountSpecified
    case unsupportedUnit(String)
    case noMatchingMint(requestedMints: [String])
    case insufficientBalance(required: UInt64, available: UInt64)
    case tokenCreationFailed(String)
    case nfcReadFailed(String)
    case nfcWriteFailed(String)
    case tagConnectionFailed

    var errorDescription: String? {
        switch self {
        case .nfcUnavailable:
            return "NFC is not available on this device"
        case .invalidPaymentRequest(let detail):
            return "Invalid payment request: \(detail)"
        case .noAmountSpecified:
            return "Payment request does not specify an amount"
        case .unsupportedUnit(let unit):
            return "Unsupported unit: \(unit)"
        case .noMatchingMint(let requestedMints):
            if requestedMints.count == 1 {
                let mint = formatMintURL(requestedMints[0])
                return "This payment requires funds from \(mint), but you don't have any balance there. Add this mint to your wallet and receive some ecash first."
            } else {
                let mintList = requestedMints.map { formatMintURL($0) }.joined(separator: ", ")
                return "This payment requires funds from one of these mints: \(mintList). You don't have any balance with these mints. Add one of them to your wallet and receive some ecash first."
            }
        case .insufficientBalance(let required, let available):
            return "Insufficient balance: need \(required), have \(available)"
        case .tokenCreationFailed(let detail):
            return "Failed to create token: \(detail)"
        case .nfcReadFailed(let detail):
            return "Failed to read NFC tag: \(detail)"
        case .nfcWriteFailed(let detail):
            return "Failed to write to NFC tag: \(detail)"
        case .tagConnectionFailed:
            return "Failed to connect to NFC tag"
        }
    }

    private func formatMintURL(_ urlString: String) -> String {
        if let url = URL(string: urlString), let host = url.host {
            return host
        }
        return urlString
    }
}

@MainActor
final class NFCPaymentService {
    enum NFCInput {
        case creq(CashuDevKit.PaymentRequest)
        case bolt11(String)
    }

    private let walletManager: WalletManager

    init(walletManager: WalletManager) {
        self.walletManager = walletManager
    }

    func decode(_ raw: String) throws -> NFCInput {
        var input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            throw NFCPaymentError.invalidPaymentRequest("Empty payment request")
        }

        if input.lowercased().hasPrefix("bitcoin:") {
            guard let parsed = Self.parseBIP321(input) else {
                throw NFCPaymentError.invalidPaymentRequest("Could not parse bitcoin URI")
            }

            if let creq = parsed.creq, !creq.isEmpty {
                do {
                    return .creq(try CashuDevKit.PaymentRequest.fromString(encoded: creq))
                } catch {
                    throw NFCPaymentError.invalidPaymentRequest(error.localizedDescription)
                }
            }

            if let bolt11 = parsed.bolt11, !bolt11.isEmpty {
                return .bolt11(bolt11)
            }

            throw NFCPaymentError.invalidPaymentRequest("No supported payment method in bitcoin URI")
        }

        input = Self.stripPrefix("cashu://", from: input)
        input = Self.stripPrefix("cashu:", from: input)
        input = Self.stripPrefix("lightning://", from: input)
        input = Self.stripPrefix("lightning:", from: input)

        let lowercasedInput = input.lowercased()
        let bolt11Prefixes = ["lnbc", "lntbs", "lntb", "lnbcrt"]
        if bolt11Prefixes.contains(where: { lowercasedInput.hasPrefix($0) }) {
            return .bolt11(input)
        }

        do {
            return .creq(try CashuDevKit.PaymentRequest.fromString(encoded: input))
        } catch {
            throw NFCPaymentError.invalidPaymentRequest(error.localizedDescription)
        }
    }

    func prepareToken(for request: CashuDevKit.PaymentRequest) async throws -> String {
        guard let requestedAmount = request.amount() else {
            throw NFCPaymentError.noAmountSpecified
        }

        let amount = requestedAmount.value

        if let unit = request.unit() {
            switch unit {
            case .sat:
                break
            default:
                throw NFCPaymentError.unsupportedUnit(Self.description(for: unit))
            }
        }

        let selectedMint = try selectMint(for: request, amount: amount)
        if selectedMint.url != walletManager.activeMint?.url {
            try await walletManager.setActiveMint(selectedMint)
        }

        do {
            let result = try await walletManager.sendTokens(amount: amount, memo: nil, p2pkPubkey: nil)
            return result.token
        } catch {
            throw NFCPaymentError.tokenCreationFailed(error.localizedDescription)
        }
    }

    private func selectMint(for request: CashuDevKit.PaymentRequest, amount: UInt64) throws -> MintInfo {
        let requested = request.mints() ?? []
        let candidates: [MintInfo]

        if requested.isEmpty {
            candidates = walletManager.mints
        } else {
            candidates = walletManager.mints.filter { requested.contains($0.url) }
        }

        guard !candidates.isEmpty else {
            throw NFCPaymentError.noMatchingMint(requestedMints: requested)
        }

        guard let selectedMint = candidates.first(where: { $0.balance >= amount }) else {
            let available = candidates.map(\.balance).max() ?? 0
            throw NFCPaymentError.insufficientBalance(required: amount, available: available)
        }

        return selectedMint
    }

    private static func parseBIP321(_ s: String) -> (creq: String?, bolt11: String?)? {
        guard let components = URLComponents(string: s),
              components.scheme?.lowercased() == "bitcoin" else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        let creq = queryItems.first { $0.name.lowercased() == "creq" }?.value
        let bolt11 = queryItems.first {
            let name = $0.name.lowercased()
            return name == "lightning" || name == "lightninginvoice"
        }?.value

        return (creq, bolt11)
    }

    private static func stripPrefix(_ prefix: String, from input: String) -> String {
        if input.lowercased().hasPrefix(prefix) {
            return String(input.dropFirst(prefix.count))
        }
        return input
    }

    private static func description(for unit: CashuDevKit.CurrencyUnit) -> String {
        switch unit {
        case .sat:
            return "sat"
        case .msat:
            return "msat"
        case .usd:
            return "usd"
        case .eur:
            return "eur"
        case .auth:
            return "auth"
        case .custom(let unit):
            return unit
        }
    }
}
