// IntegrationTestBase.swift
//
// Base class for Cashu integration tests against real mints (Nutshell & CDK).
// Requires a running mint via `CI/setup-nutshell.sh` and `CI/setup-cdk.sh`.

import XCTest
import Cdk

// MARK: - BIP39 Test Mnemonic
//
// "abandon x N + about" is the standard BIP39 test vector.
// This is the same mnemonic used across all test suites for deterministic key derivation.
let testMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

/// Base class for CDK-Swift integration tests against live Cashu mints.
///
/// Each concrete subclass overrides `mintURL` to point at either Nutshell or the CDK mint.
/// The base class handles Wallet & WalletRepository lifecycle per test.
///
/// Required environment:
///   NUTSHELL_MINT_URL - URL for the Nutshell mint (default: http://localhost:3338)
///   CDK_MINT_URL      - URL for the CDK mint      (default: http://localhost:3339)
class IntegrationTestBase: XCTestCase {

    var repository: WalletRepository!
    var wallet: Wallet!
    var mintUrlStr: String { "http://localhost:3338" }  // overridden by subclasses
    var dbNamePrefix: String { "test" }

    override func setUp() async throws {
        try await super.setUp()

        // One-time CDK logging initialisation (safe to call multiple times)
        initLogging(level: "debug")

        // A fresh random mnemonic per test keeps blinded-message secrets unique
        // across tests; the mint persists signed messages for its lifetime, so a
        // shared seed would collide ("Blinded Message is already signed").
        let tmpPath = NSTemporaryDirectory().appending("\(dbNamePrefix)_\(UUID().uuidString).sqlite")
        repository = try WalletRepository(
            mnemonic: try generateMnemonic(),
            store: .sqlite(path: tmpPath)
        )

        let mintUrl = MintUrl(url: mintUrlStr)
        try await repository.createWallet(
            mintUrl: mintUrl,
            unit: .sat,
            targetProofCount: nil
        )
        wallet = try await repository.getWallet(mintUrl: mintUrl, unit: .sat)
    }

    override func tearDown() async throws {
        wallet = nil
        repository = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a mint quote and waits until it has `paid` state, then mints proofs.
    /// Uses the BOLT11 payment method (fake wallets auto-pay immediately).
    /// Returns the minted proofs.
    func mintSats(_ amount: UInt64, timeout: TimeInterval = 15.0, wallet targetWallet: Wallet? = nil) async throws -> [Proof] {
        let target = targetWallet ?? wallet!
        let quote = try await target.mintQuote(
            paymentMethod: .bolt11,
            amount: Amount(value: amount),
            description: "E2E integration test",
            extra: nil
        )

        // Poll until paid
        let start = Date()
        var currentState = quote.state
        while currentState != .paid, Date().timeIntervalSince(start) < timeout {
            try await Task.sleep(nanoseconds: 200_000_000)  // 200 ms
            let updated = try await target.checkMintQuote(quoteId: quote.id)
            currentState = updated.state
        }
        XCTAssertEqual(currentState, .paid, "Mint quote did not become paid within timeout")

        guard currentState == .paid else {
            throw NSError(domain: "IntegrationTest", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Mint quote did not reach paid state"
            ])
        }

        // Mint the proofs
        let proofs = try await target.mint(
            quoteId: quote.id,
            amountSplitTarget: .none,
            spendingConditions: nil
        )
        XCTAssertFalse(proofs.isEmpty, "Should have minted at least one proof")
        return proofs
    }
}
