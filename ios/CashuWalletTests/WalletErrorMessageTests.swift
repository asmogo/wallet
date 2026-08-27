import XCTest
@testable import CashuWallet

/// A CDK/mint failure as it reaches the classifier: an opaque error whose only
/// signal is the message text. `WalletErrorMessage.classified(for:)` routes any
/// unrecognised error through `String(describing:)`, so this stands in for a
/// real `Cdk.FfiError` without needing the FFI types in the test target.
private struct RawMintError: Error, CustomStringConvertible {
    let description: String
}

final class WalletErrorMessageTests: XCTestCase {

    /// A NUT-04/05 amount rejection must never reach the UI as CDK's own text.
    /// The mint returns code 11006 with the real bounds in `detail`, but decoding
    /// that response back into an Error rebuilds the variant with three
    /// `Amount::default()` — so CDK renders "Amount must be between `0` and `0`
    /// is `0`" for every mint at every amount. Regression guard for the copy the
    /// user saw shipped verbatim.
    func testCDKAmountLimitWordingMapsToMintLimitsCopy() {
        let message = RawMintError(
            description: "Amount must be between `0` and `0` is `0`"
        ).walletMessage

        XCTAssertEqual(
            message.text,
            "This amount is outside the mint's limits. Try a different amount."
        )
        XCTAssertEqual(message.severity, .caution)
    }

    /// The same rule still has to catch the phrasings it was originally written
    /// for, so adding CDK's wording can't quietly narrow it.
    func testLegacyAmountLimitWordingsStillMapToMintLimitsCopy() {
        let expected = "This amount is outside the mint's limits. Try a different amount."

        for raw in [
            "Amount out of range",
            "Amount is outside of allowed range",
            "amount is outside the allowed limits",
        ] {
            XCTAssertEqual(
                RawMintError(description: raw).userFacingWalletMessage,
                expected,
                "raw: \(raw)"
            )
        }
    }

    /// `TransactionUnbalanced` is rebuilt as `(0, 0, 0)` by the same decoder, so it
    /// reaches us as "Inputs: `0`, Outputs: `0`, Expected Fee: `0`" — three more
    /// meaningless numbers that must not be shown.
    func testCDKUnbalancedWordingMapsToFeeDisagreementCopy() {
        let message = RawMintError(
            description: "Inputs: `0`, Outputs: `0`, Expected Fee: `0`"
        ).walletMessage

        XCTAssertEqual(
            message.text,
            "The wallet and mint disagreed on the fee. Try again or use another mint."
        )
        XCTAssertFalse(message.text.contains("`0`"))
    }

    /// The zeroed CDK string must not survive anywhere in the resolved copy —
    /// the whole point of the mapping is that those numbers are meaningless.
    func testResolvedCopyNeverLeaksTheZeroedBounds() {
        let text = RawMintError(
            description: "Amount must be between `0` and `0` is `0`"
        ).userFacingWalletMessage

        XCTAssertFalse(text.contains("`0`"))
        XCTAssertFalse(text.lowercased().contains("must be between"))
    }
}
