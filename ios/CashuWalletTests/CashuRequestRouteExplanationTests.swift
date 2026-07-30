import XCTest
@testable import CashuWallet

final class CashuRequestRouteExplanationTests: XCTestCase {
    func testCompatibleMintRouteHasNoRedundantExplanation() {
        XCTAssertNil(CashuRequestRouteExplanation(state: .compatibleMint))
    }

    func testLightningFallbackNamesTheRailChange() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(state: .lightningFallback),
            .lightningFallback
        )
    }

    func testAddMintRecoveryNamesRequestedMintHost() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(
                state: .addRequestedMint(targetMintURL: "https://mint.example.com:3338/path")
            ),
            .addRequestedMint(target: "mint.example.com:3338")
        )
    }

    func testTopUpRecoveryNamesTargetMintHost() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(
                state: .topUpTargetMint(targetMintURL: "https://target.example.com/")
            ),
            .topUpTargetMint(target: "target.example.com")
        )
    }

    func testUnavailableRouteDoesNotInventAnExplanation() {
        XCTAssertNil(CashuRequestRouteExplanation(state: .unavailable))
    }

    func testMissingOrMalformedTargetKeepsGenericRecoveryExplanation() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(state: .addRequestedMint(targetMintURL: "  ")),
            .addRequestedMint(target: nil)
        )
        XCTAssertEqual(
            CashuRequestRouteExplanation(state: .topUpTargetMint(targetMintURL: "https://")),
            .topUpTargetMint(target: nil)
        )
    }
}

final class CashuRequestNostrReadinessTests: XCTestCase {
    private let publicKeyHex = String(repeating: "1", count: 64)
    private let privateKeyHex = String(repeating: "2", count: 64)

    func testReadyConfigurationKeepsOnlyNormalizedWebSocketRelays() {
        XCTAssertEqual(
            evaluate(
                relays: [
                    " https://not-a-relay.example ",
                    " wss://relay.example ",
                    "wss://relay.example",
                    "ws://localhost:7777",
                ]
            ),
            .ready(
                publicKeyHex: publicKeyHex,
                relays: ["wss://relay.example", "ws://localhost:7777"]
            )
        )
    }

    func testMissingKeyMaterialNamesExactNostrKeySetting() {
        XCTAssertEqual(
            CashuRequestNostrReadiness.evaluate(
                isIdentityInitialized: true,
                publicKeyHex: "not-a-key",
                privateKeyHex: nil,
                relays: ["wss://relay.example"],
                listenerEnabled: true
            ),
            .blocked(
                recoveryMessage:
                    "Your Nostr key isn't ready. Check Settings → Nostr → Nostr key, then try again."
            )
        )
    }

    func testNoUsableRelayNamesExactRelaySetting() {
        XCTAssertEqual(
            evaluate(relays: ["", "https://relay.example", "wss://"]),
            .blocked(
                recoveryMessage:
                    "No usable Nostr relay is configured. Add a ws:// or wss:// relay in Settings → Nostr → Relays, then try again."
            )
        )
    }

    func testDisabledListenerNamesExactPrivacySetting() {
        XCTAssertEqual(
            evaluate(listenerEnabled: false),
            .blocked(
                recoveryMessage:
                    "Cashu Request listening is off. Turn on Settings → Privacy → Listen for payment requests, then try again."
            )
        )
    }

    private func evaluate(
        relays: [String] = ["wss://relay.example"],
        listenerEnabled: Bool = true
    ) -> CashuRequestNostrReadiness {
        CashuRequestNostrReadiness.evaluate(
            isIdentityInitialized: true,
            publicKeyHex: publicKeyHex,
            privateKeyHex: privateKeyHex,
            relays: relays,
            listenerEnabled: listenerEnabled
        )
    }
}
