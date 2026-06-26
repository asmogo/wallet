import XCTest
@testable import CashuWallet

@MainActor
final class TokenServiceTests: XCTestCase {
    private var service: TokenService!

    override func setUp() {
        super.setUp()
        service = TokenService(
            walletRepository: { nil },
            getActiveMint: { nil }
        )
    }

    // MARK: - sendTokens / receiveTokens — wallet not initialised

    func testSendTokensThrowsWhenNoRepository() async {
        do {
            _ = try await service.sendTokens(amount: 10)
            XCTFail("Expected WalletError.notInitialized")
        } catch let err as WalletError {
            guard case .notInitialized = err else {
                XCTFail("Expected .notInitialized, got \(err)"); return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSendTokensThrowsWhenNoActiveMintAndNoRepository() async {
        do {
            _ = try await service.sendTokens(amount: 1, mintUrl: nil)
            XCTFail("Expected WalletError.notInitialized")
        } catch let err as WalletError {
            guard case .notInitialized = err else {
                XCTFail("Expected .notInitialized, got \(err)"); return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testReceiveTokensThrowsNotInitializedWhenNoRepository() async {
        // The repository guard runs before Token.decode, so the error must be
        // WalletError.notInitialized — not a CDK decode error.
        do {
            _ = try await service.receiveTokens(tokenString: "cashuAtest")
            XCTFail("Expected WalletError.notInitialized")
        } catch let err as WalletError {
            guard case .notInitialized = err else {
                XCTFail("Expected .notInitialized, got \(err)"); return
            }
        } catch {
            XCTFail("Expected WalletError.notInitialized, got \(error)")
        }
    }

    // MARK: - calculateReceiveFee — wallet not initialised

    func testCalculateReceiveFeeThrowsNotInitializedWhenNoRepository() async {
        do {
            _ = try await service.calculateReceiveFee(tokenString: "cashuAtest")
            XCTFail("Expected WalletError.notInitialized")
        } catch let err as WalletError {
            guard case .notInitialized = err else {
                XCTFail("Expected .notInitialized, got \(err)"); return
            }
        } catch {
            XCTFail("Expected WalletError.notInitialized, got \(error)")
        }
    }

    // MARK: - checkTokenSpendable — wallet not initialised

    func testCheckTokenSpendableReturnsFalseWhenNoRepository() async {
        let result = await service.checkTokenSpendable(
            token: "cashuAtest",
            mintUrl: "https://mint.example.com"
        )
        XCTAssertFalse(result)
    }

    // MARK: - isLoading state

    func testIsLoadingFalseInitially() {
        XCTAssertFalse(service.isLoading)
    }

    func testClearStateResetsLoading() {
        service.isLoading = true
        service.clearState()
        XCTAssertFalse(service.isLoading, "clearState must reset isLoading to false")
    }

    // MARK: - P2PK pubkey validation (normalizedP2PKPubkey)
    //
    // Tested directly: `sendTokens` only reaches this validator after the
    // repository guard and `getWallet`, both of which need a live mint, so
    // driving it through `sendTokens` with a nil repository never exercises
    // these branches — it always short-circuits with WalletError.notInitialized.

    func testNormalizedP2PKReturnsNilForNil() throws {
        XCTAssertNil(try service.normalizedP2PKPubkey(nil))
    }

    func testNormalizedP2PKReturnsNilForEmpty() throws {
        XCTAssertNil(try service.normalizedP2PKPubkey(""))
    }

    func testNormalizedP2PKReturnsNilForWhitespace() throws {
        XCTAssertNil(try service.normalizedP2PKPubkey("   "))
    }

    func testNormalizedP2PKPrefixesBare64HexKey() throws {
        let bare = String(repeating: "a", count: 64)
        XCTAssertEqual(try service.normalizedP2PKPubkey(bare), "02" + bare)
    }

    func testNormalizedP2PKAcceptsCompressed02Key() throws {
        let key = "02" + String(repeating: "b", count: 64)
        XCTAssertEqual(try service.normalizedP2PKPubkey(key), key)
    }

    func testNormalizedP2PKAcceptsCompressed03Key() throws {
        let key = "03" + String(repeating: "c", count: 64)
        XCTAssertEqual(try service.normalizedP2PKPubkey(key), key)
    }

    func testNormalizedP2PKLowercasesInput() throws {
        let key = "02" + String(repeating: "AB", count: 32)
        XCTAssertEqual(try service.normalizedP2PKPubkey(key), key.lowercased())
    }

    func testNormalizedP2PKThrowsOnNonHex() {
        XCTAssertThrowsError(try service.normalizedP2PKPubkey("not-a-pubkey")) { error in
            XCTAssertEqual(error as? TokenServiceError, .invalidP2PKPubkey)
        }
    }

    func testNormalizedP2PKThrowsOnTooShortHex() {
        XCTAssertThrowsError(try service.normalizedP2PKPubkey("02aabb")) { error in
            XCTAssertEqual(error as? TokenServiceError, .invalidP2PKPubkey)
        }
    }

    func testNormalizedP2PKThrowsOnWrongPrefix() {
        // 66 hex chars but an invalid SEC1 prefix (04 = uncompressed, not allowed).
        let key = "04" + String(repeating: "a", count: 64)
        XCTAssertThrowsError(try service.normalizedP2PKPubkey(key)) { error in
            XCTAssertEqual(error as? TokenServiceError, .invalidP2PKPubkey)
        }
    }

    func testNormalizedP2PKThrowsOnBare64NonHex() {
        // 64 chars but contains non-hex 'g' — must not be auto-prefixed.
        let key = String(repeating: "g", count: 64)
        XCTAssertThrowsError(try service.normalizedP2PKPubkey(key)) { error in
            XCTAssertEqual(error as? TokenServiceError, .invalidP2PKPubkey)
        }
    }

    // MARK: - TokenServiceError descriptions

    func testInvalidP2PKPubkeyErrorHasDescription() {
        let error = TokenServiceError.invalidP2PKPubkey
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    func testMissingP2PKSigningKeyErrorHasDescription() {
        let error = TokenServiceError.missingP2PKSigningKey
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }
}
