import XCTest
@testable import CashuWallet

final class CrashReportSanitizerTests: XCTestCase {
    func testMessageRedactsWalletSecretsUrlsAndPaths() {
        let message = CrashReportSanitizer.message(
            "nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq " +
                "nostr+walletconnect://service?relay=wss%3A%2F%2Frelay.example&secret=client " +
                "cashuAabcdefghijklmnopqrstuvwxyz0123456789 at https://mint.example.com " +
                "/private/var/mobile/wallet.db"
        )

        XCTAssertEqual(
            message,
            "<redacted-nsec> <redacted-nwc-uri> <redacted-cashu-token> at <redacted-url> " +
                "<redacted-path>"
        )
    }

    func testMessageRedactsPaymentPayloadsAndContactDetails() {
        let message = CrashReportSanitizer.message(
            "request creqAabcdefghijklmnopqrstuvwxyz0123456789 " +
                "invoice lnbc1abcdefghijklmnopqrstuvwxyz0123456789 " +
                "offer lno1abcdefghijklmnopqrstuvwxyz0123456789 " +
                "bitcoin:bc1qexamplewalletaddress0123456789 and alice@example.com"
        )

        XCTAssertEqual(
            message,
            "request <redacted-cashu-request> invoice <redacted-lightning-payload> " +
                "offer <redacted-lightning-payload> <redacted-bitcoin-uri> and <redacted-email>"
        )
    }

    func testSanitizedErrorDropsUserInfoAndKeepsOnlySafeDescriptionAndCode() {
        let original = NSError(
            domain: "RemoteWalletError",
            code: 42,
            userInfo: [
                NSLocalizedDescriptionKey: "failed cashuAabcdefghijklmnopqrstuvwxyz0123456789",
                "rawResponse": "secret=correct horse battery staple",
            ]
        )

        let safe = CrashReportSanitizer.error(original)

        XCTAssertEqual(safe.domain, "CashuWallet.SanitizedError")
        XCTAssertEqual(safe.code, 42)
        XCTAssertEqual(
            safe.localizedDescription,
            "NSError: failed <redacted-cashu-token>"
        )
        XCTAssertNil(safe.userInfo["rawResponse"])
    }
}
