import Foundation
import Cdk

// MARK: - Token Service

/// Service responsible for ecash token operations.
/// Handles sending, receiving, encoding, and decoding tokens.
@MainActor
class TokenService: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether an operation is in progress
    @Published var isLoading = false
    
    // MARK: - Dependencies
    
    private let walletRepository: () -> WalletRepository?
    private let getActiveMint: () -> MintInfo?
    
    // MARK: - Initialization
    
    init(
        walletRepository: @escaping () -> WalletRepository?,
        getActiveMint: @escaping () -> MintInfo?
    ) {
        self.walletRepository = walletRepository
        self.getActiveMint = getActiveMint
    }

    // MARK: - State

    /// Reset transient state when the wallet is torn down.
    func clearState() {
        isLoading = false
    }
    
    // MARK: - Send Operations
    
    /// Send tokens (create ecash token string)
    /// - Parameters:
    ///   - amount: Amount to send in satoshis
    ///   - memo: Optional memo to include
    /// - Returns: Result containing token string and fee paid
    func sendTokens(amount: UInt64, memo: String? = nil, p2pkPubkey: String? = nil, mintUrl preferredMintURL: String? = nil, unit: Cdk.CurrencyUnit = .sat) async throws -> SendTokenResult {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        let mintUrlString: String
        if let preferredMintURL, !preferredMintURL.isEmpty {
            mintUrlString = preferredMintURL
        } else if let activeMint = getActiveMint() {
            mintUrlString = activeMint.url
        } else {
            throw WalletError.notInitialized
        }

        isLoading = true
        defer { isLoading = false }

        let mintUrl = MintUrl(url: mintUrlString)
        // For a non-sat unit, ensure the per-unit wallet exists before fetching
        // it (the sat wallet is always already tracked). `amount` is denominated
        // in this unit's base units (e.g. eur/usd cents).
        if PaymentRequestDecoder.unitDescription(unit) != "sat" {
            try await repo.createWallet(mintUrl: mintUrl, unit: unit, targetProofCount: nil)
        }
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: unit)
        
        let sendMemo = memo.map { SendMemo(memo: $0, includeMemo: true) }
        let normalizedP2PKPubkey = try normalizedP2PKPubkey(p2pkPubkey)
        let spendingConditions = normalizedP2PKPubkey.map {
            SpendingConditions.p2pk(pubkey: $0, conditions: nil)
        }
        
        // Sign with the full set: the seed-derived primary key plus any stored
        // device/imported keys. Lets a locked send be re-claimed by the sender.
        let localP2PKSigningKeys = SettingsManager.shared.allP2PKSigningKeyHexes().map { SecretKey(hex: $0) }

        // Create SendOptions
        // includeFee: false — the token carries exactly `amount`; the redeem
        // fee is the recipient's cost and their wallet shows it (see
        // ReceiveTokenDetailView's fee preview). Crucially this lets Send Max
        // move the whole balance: all proofs go out as-is, no swap, no fee —
        // also on fee-charging mints. The fee we return below is only the
        // sender-side change-swap fee (zero for a max send). Payment requests
        // stay includeFee: true — there the requester must net the asked
        // amount (see estimateCashuPaymentFee).
        let sendOptions = SendOptions(
            memo: sendMemo,
            conditions: spendingConditions,
            amountSplitTarget: SplitTarget.none,
            sendKind: SendKind.onlineExact,
            includeFee: false,
            useP2bk: false,
            maxProofs: nil,
            metadata: [:],
            p2pkSigningKeys: localP2PKSigningKeys,
            p2pkLockedProofSendMode: .swap
        )
        
        let prepared = try await wallet.prepareSend(
            amount: Amount(value: amount),
            options: sendOptions
        )

        // Capture fee before confirm() consumes the prepared send.
        // Avoids calling token.proofsSimple() after confirm, which fails for
        // IDv2 keyset tokens because proofsSimple passes an empty keyset list
        // to the underlying token.proofs() call and can't resolve the short ID.
        let fee = prepared.fee().value

        let token = try await prepared.confirm(memo: memo)
        let tokenString = token.encode()

        if let normalizedP2PKPubkey,
           SettingsManager.shared.p2pkKeys.contains(where: {
               normalizedP2PKForComparison($0.publicKey) == normalizedP2PKForComparison(normalizedP2PKPubkey)
           }) {
            SettingsManager.shared.markP2PKKeyUsed(publicKey: normalizedP2PKPubkey)
        }
        
        return SendTokenResult(token: tokenString, fee: fee)
    }
    
    // MARK: - Receive Operations
    
    /// Receive tokens (redeem ecash token string)
    /// - Parameter tokenString: The encoded cashu token
    /// - Returns: Amount received in satoshis
    func receiveTokens(tokenString: String) async throws -> UInt64 {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Parse the token string
        let token = try Token.decode(encodedToken: tokenString)
        let tokenMintUrl = try token.mintUrl()
        // Redeem into the token's own unit (sat, eur, usd, …) rather than
        // assuming sat, so non-sat tokens land in the matching per-unit wallet.
        let tokenUnit = token.unit() ?? .sat

        // Ensure the mint is added with the correct unit
        try await repo.createWallet(mintUrl: tokenMintUrl, unit: tokenUnit, targetProofCount: nil)

        // Offer the full signing set (primary seed-derived key + stored keys) so a
        // token locked to the user's own identity is redeemable.
        let localP2PKSigningKeys = SettingsManager.shared.allP2PKSigningKeyHexes().map { SecretKey(hex: $0) }
        let tokenP2PKPubkeys = token.p2pkPubkeys()

        if !tokenP2PKPubkeys.isEmpty,
           !tokenP2PKPubkeys.contains(where: { SettingsManager.shared.isKnownP2PKPublicKey($0) }) {
            throw TokenServiceError.missingP2PKSigningKey
        }

        // A stored-key match is only needed to bump that key's "used" counter;
        // the primary key has no counter to advance.
        let matchingLocalP2PKKey = SettingsManager.shared.p2pkKeys.first {
            let localKey = normalizedP2PKForComparison($0.publicKey)
            return tokenP2PKPubkeys.contains { normalizedP2PKForComparison($0) == localKey }
        }

        // Create ReceiveOptions
        let receiveOptions = ReceiveOptions(
            amountSplitTarget: SplitTarget.none,
            p2pkSigningKeys: localP2PKSigningKeys,
            preimages: [],
            metadata: [:]
        )

        // The receive performs a swap whose blinded outputs are derived
        // deterministically from the keyset counter (NUT-13). If that counter is
        // behind what the mint has already signed (e.g. the same seed received
        // from this mint before, or a reinstall/DB reset that kept the seed), the
        // mint rejects the swap — worded either "Duplicate outputs" (Nutshell) or
        // "Blinded Message is already signed" (macadamia et al.), both matched by
        // isCounterDesyncError.
        //
        // Two recovery levers, both advancing the counter past already-signed
        // indices: (1) a one-shot restore() rescan on the first collision jumps
        // past the bulk in a single step, and (2) each failed swap also advances
        // the persisted counter, so re-fetching a fresh wallet and retrying mops
        // up any residual. Retry a few times before surfacing the error.
        let maxAttempts = 4
        var lastError: Error?
        var didRestore = false
        for attempt in 0..<maxAttempts {
            let wallet = try await repo.getWallet(mintUrl: tokenMintUrl, unit: tokenUnit)
            do {
                let amount = try await wallet.receive(token: token, options: receiveOptions)
                if let matchingLocalP2PKKey {
                    SettingsManager.shared.markP2PKKeyUsed(publicKey: matchingLocalP2PKKey.publicKey)
                }
                return amount.value
            } catch {
                lastError = error
                guard Self.isCounterDesyncError(error), attempt < maxAttempts - 1 else {
                    throw error
                }
                if !didRestore {
                    // One-shot NUT-13 restore fast-forwards the keyset counter past
                    // every index the mint has already signed. Safe here: it doesn't
                    // consume the pending token, and it recovers any other unspent
                    // proofs for this mint as a bonus. Best-effort — if it fails we
                    // still fall back to the per-attempt counter bump below.
                    didRestore = true
                    AppLogger.wallet.warning("Receive hit NUT-13 counter desync; restoring to resync the counter")
                    _ = try? await wallet.restore()
                } else {
                    AppLogger.wallet.warning("Receive still colliding after restore; retrying with a fresh wallet (attempt \(attempt + 1)/\(maxAttempts))")
                }
            }
        }
        throw lastError ?? WalletError.notInitialized
    }

    /// Whether an error is a mint rejection caused by a stale NUT-13 keyset
    /// counter — i.e. the wallet asked the mint to sign blinded outputs it has
    /// already signed for this seed. Mints word this differently ("Duplicate
    /// outputs" on Nutshell, "Blinded Message is already signed" on macadamia and
    /// others); all are recoverable by advancing the counter and retrying.
    static func isCounterDesyncError(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        return message.contains("duplicate outputs")
            || message.contains("already signed")            // "Blinded Message is already signed"
            || message.contains("outputs already signed")
    }
    
    // MARK: - Token Utilities
    
    /// Decode token string without redeeming
    func decodeToken(tokenString: String) throws -> Token {
        return try Token.decode(encodedToken: tokenString)
    }
    
    /// Calculate the fee for receiving a token
    func calculateReceiveFee(tokenString: String) async throws -> UInt64 {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }
        
        // Decode the token
        let token = try Token.decode(encodedToken: tokenString)
        let mintUrl = try token.mintUrl()
        let tokenUnit = token.unit() ?? .sat

        // Ensure the mint is added with the correct unit
        try await repo.createWallet(mintUrl: mintUrl, unit: tokenUnit, targetProofCount: nil)

        // Get the wallet for this mint
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: tokenUnit)

        // Resolve proofs with their FULL keyset ids: proofsSimple() can carry a
        // short/legacy IDv2 keyset id that getKeysetFeesById below can't look
        // up, which used to fail the whole preview to 0 — the confirm screen
        // then showed the token's gross value as if the redeem were free. Same
        // trap checkTokenSpendable documents for checkProofsSpent.
        let proofs: [Proof]
        do {
            let keysets = try await wallet.getMintKeysets(filter: .all)
            proofs = try token.proofs(mintKeysets: keysets)
        } catch {
            proofs = try token.proofsSimple()
        }

        guard !proofs.isEmpty else {
            return 0
        }

        // NUT-02 fee: sum each input's fee_ppk, then one ceil over the total.
        // Don't use wallet.calculateFee here — the 0.17.x FFI helper floor-
        // divides (ppk * count / 1000), reporting 0 where the mint charges 1.
        do {
            var ppkByKeyset: [String: UInt64] = [:]
            var totalPpk: UInt64 = 0
            for proof in proofs {
                if let ppk = ppkByKeyset[proof.keysetId] {
                    totalPpk += ppk
                } else {
                    let ppk = try await wallet.getKeysetFeesById(keysetId: proof.keysetId)
                    ppkByKeyset[proof.keysetId] = ppk
                    totalPpk += ppk
                }
            }
            return (totalPpk + 999) / 1000
        } catch {
            print("Failed to get keyset fee for calculation: \(error)")
            return 0
        }
    }
    
    // MARK: - Token Status
    
    /// Check if a token has been spent (claimed by recipient).
    ///
    /// Uses `proofs(mintKeysets:)` instead of `proofsSimple()` so the decoded
    /// `Proof` objects carry the correct (full) keyset ID.  Without this, proofs
    /// decoded from a token created under an IDv2 keyset may carry a short/legacy
    /// keyset ID and CDK's `checkProofsSpent` will throw:
    ///   "Short keyset id does not match any of the provided IDv2s"
    func checkTokenSpent(token: String, mintUrl: String) async throws -> Bool {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        let tokenObj = try Token.decode(encodedToken: token)
        let mintUrlObj = MintUrl(url: mintUrl)
        let tokenUnit = tokenObj.unit() ?? .sat

        let wallet = try await repo.getWallet(mintUrl: mintUrlObj, unit: tokenUnit)
        let keysets = try await wallet.getMintKeysets(filter: .all)
        let proofs = try tokenObj.proofs(mintKeysets: keysets)
        let spentStates = try await wallet.checkProofsSpent(proofs: proofs)

        // If any proofs are spent, the token has been redeemed.
        return spentStates.contains(true)
    }

    /// Passive checks keep their historical non-throwing contract. Interactive
    /// checks call `checkTokenSpent` so failures can be shown instead of being
    /// misreported as a definitive "not claimed" result.
    func checkTokenSpendable(token: String, mintUrl: String) async -> Bool {
        do {
            return try await checkTokenSpent(token: token, mintUrl: mintUrl)
        } catch {
            AppLogger.wallet.error("Error checking token spent status: \(error)")
            return false
        }
    }

    /// Normalize and validate a P2PK pubkey.
    ///
    /// `nil`/empty/whitespace → `nil` (no P2PK lock). A bare 64-char hex key is
    /// prefixed with `02`. Anything that isn't a 66-char `02`/`03` hex key throws
    /// `TokenServiceError.invalidP2PKPubkey`.
    ///
    /// Internal (not private) so it can be unit-tested directly without standing
    /// up a wallet repository — `sendTokens` reaches it only after the repository
    /// guard and `getWallet`, which need a live mint.
    func normalizedP2PKPubkey(_ pubkey: String?) throws -> String? {
        guard let pubkey else { return nil }
        let trimmed = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        let containsOnlyHex = trimmed.unicodeScalars.allSatisfy { hexCharacters.contains($0) }

        var normalized = trimmed
        if normalized.count == 64 && containsOnlyHex {
            normalized = "02\(normalized)"
        }

        guard normalized.count == 66,
              (normalized.hasPrefix("02") || normalized.hasPrefix("03")),
              normalized.unicodeScalars.allSatisfy({ hexCharacters.contains($0) }) else {
            throw TokenServiceError.invalidP2PKPubkey
        }

        return normalized
    }

    private func normalizedP2PKForComparison(_ pubkey: String) -> String {
        let normalized = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.count == 66, normalized.hasPrefix("02") || normalized.hasPrefix("03") {
            return String(normalized.dropFirst(2))
        }
        return normalized
    }
}

enum TokenServiceError: LocalizedError {
    case invalidP2PKPubkey
    case missingP2PKSigningKey

    var errorDescription: String? {
        switch self {
        case .invalidP2PKPubkey:
            return "That key isn't valid. Use a 66-character hex key (02/03 prefix)."
        case .missingP2PKSigningKey:
            return "This ecash is locked to a key you don't hold. Add the matching key in Settings → Locked Ecash to receive it."
        }
    }
}
