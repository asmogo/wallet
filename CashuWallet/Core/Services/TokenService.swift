import Foundation
import CashuDevKit

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
    
    // MARK: - Send Operations
    
    /// Send tokens (create ecash token string)
    /// - Parameters:
    ///   - amount: Amount to send in satoshis
    ///   - memo: Optional memo to include
    /// - Returns: Result containing token string and fee paid
    func sendTokens(amount: UInt64, memo: String? = nil, p2pkPubkey: String? = nil) async throws -> SendTokenResult {
        guard let repo = walletRepository(), let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let mintUrl = try MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        
        let sendMemo = memo.map { SendMemo(memo: $0, includeMemo: true) }
        let normalizedP2PKPubkey = try normalizedP2PKPubkey(p2pkPubkey)
        let spendingConditions = normalizedP2PKPubkey.map {
            SpendingConditions.p2pk(pubkey: $0, conditions: nil)
        }
        
        // Create SendOptions
        // Note: includeFee: false matches cashu.me default behavior
        let sendOptions = SendOptions(
            memo: sendMemo,
            conditions: spendingConditions,
            amountSplitTarget: SplitTarget.none,
            sendKind: SendKind.onlineExact,
            includeFee: false,
            maxProofs: nil,
            metadata: [:]
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
        let tokenString = try token.encode()

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
        
        // Ensure the mint is added with the correct unit
        try await repo.createWallet(mintUrl: tokenMintUrl, unit: .sat, targetProofCount: nil)
        
        // Get the wallet for this mint
        let wallet = try await repo.getWallet(mintUrl: tokenMintUrl, unit: .sat)
        
        let availableP2PKKeys = SettingsManager.shared.p2pkKeys
        let localP2PKSigningKeys = availableP2PKKeys.map { SecretKey(hex: $0.privateKey) }
        let tokenP2PKPubkeys = token.p2pkPubkeys()
        let matchingLocalP2PKKey = availableP2PKKeys.first {
            let localKey = normalizedP2PKForComparison($0.publicKey)
            return tokenP2PKPubkeys.contains { normalizedP2PKForComparison($0) == localKey }
        }

        if !tokenP2PKPubkeys.isEmpty && matchingLocalP2PKKey == nil {
            throw TokenServiceError.missingP2PKSigningKey
        }

        // Create ReceiveOptions
        let receiveOptions = ReceiveOptions(
            amountSplitTarget: SplitTarget.none,
            p2pkSigningKeys: localP2PKSigningKeys,
            preimages: [],
            metadata: [:]
        )
        
        let amount = try await wallet.receive(
            token: token,
            options: receiveOptions
        )

        if let matchingLocalP2PKKey {
            SettingsManager.shared.markP2PKKeyUsed(publicKey: matchingLocalP2PKKey.publicKey)
        }
        
        return amount.value
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
        let proofs = try token.proofsSimple()
        
        // Ensure the mint is added with the correct unit
        try await repo.createWallet(mintUrl: mintUrl, unit: .sat, targetProofCount: nil)
        
        // Get the wallet for this mint
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        
        guard let firstProof = proofs.first else {
            return 0
        }
        
        // Calculate fee using the wallet's calculateFee method
        do {
            let fee = try await wallet.calculateFee(
                proofCount: UInt32(proofs.count),
                keysetId: firstProof.keysetId
            )
            return fee.value
        } catch {
            // Fallback: calculate manually using keyset fee
            do {
                let feePerProof = try await wallet.getKeysetFeesById(keysetId: firstProof.keysetId)
                return feePerProof * UInt64(proofs.count)
            } catch {
                print("Failed to get keyset fee for calculation: \(error)")
            }
            return 0
        }
    }
    
    // MARK: - Token Status
    
    /// Check if a token has been spent (claimed by recipient)
    func checkTokenSpendable(token: String, mintUrl: String) async -> Bool {
        guard let repo = walletRepository() else { return false }
        
        do {
            let tokenObj = try Token.decode(encodedToken: token)
            let mintUrlObj = try MintUrl(url: mintUrl)
            
            let wallet = try await repo.getWallet(mintUrl: mintUrlObj, unit: .sat)
            
            let proofs = try tokenObj.proofsSimple()
            let spentStates = try await wallet.checkProofsSpent(proofs: proofs)
            
            // If any proofs are spent, the token has been redeemed
            return spentStates.contains(true)
        } catch {
            print("Error checking token spendable: \(error)")
            return false
        }
    }

    private func normalizedP2PKPubkey(_ pubkey: String?) throws -> String? {
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
            return "Invalid P2PK pubkey. Use a 66-character hex key (02/03 prefix)."
        case .missingP2PKSigningKey:
            return "Token is P2PK locked and no matching key is available in Settings > P2PK Features."
        }
    }
}
