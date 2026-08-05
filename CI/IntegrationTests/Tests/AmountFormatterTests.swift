import XCTest
@testable import CashuWallet

final class AmountFormatterTests: XCTestCase {

    // MARK: - sat unit

    func testSmallAmountSatUnit() {
        XCTAssertEqual(AmountFormatter.sats(1, useBitcoinSymbol: false), "1 sat")
    }

    func testRoundAmountSatUnit() {
        XCTAssertEqual(AmountFormatter.sats(100, useBitcoinSymbol: false), "100 sat")
    }

    func testGroupedThousandsSatUnit() {
        XCTAssertEqual(AmountFormatter.sats(1_000, useBitcoinSymbol: false), "1,000 sat")
    }

    func testMillionSatUnit() {
        XCTAssertEqual(AmountFormatter.sats(1_000_000, useBitcoinSymbol: false), "1,000,000 sat")
    }

    func testZeroSatUnit() {
        XCTAssertEqual(AmountFormatter.sats(0, useBitcoinSymbol: false), "0 sat")
    }

    // MARK: - Fiat conversion

    func testFiatConversionFormats() {
        XCTAssertEqual(AmountFormatter.fiat(sats: 300_000, btcPrice: 20_000, currencyCode: "USD"), "$60.00")
    }

    func testFiatConversionExactlyOneCent() {
        // 50 sats at $20k/BTC = $0.01 — the smallest displayable amount.
        XCTAssertEqual(AmountFormatter.fiat(sats: 50, btcPrice: 20_000, currencyCode: "USD"), "$0.01")
    }

    func testFiatConversionUnderOneCentHidden() {
        // 49 sats at $20k/BTC = $0.0098 — sub-cent conversions are never shown.
        XCTAssertNil(AmountFormatter.fiat(sats: 49, btcPrice: 20_000, currencyCode: "USD"))
    }

    func testFiatConversionMissingPriceHidden() {
        XCTAssertNil(AmountFormatter.fiat(sats: 1_000, btcPrice: nil, currencyCode: "USD"))
        XCTAssertNil(AmountFormatter.fiat(sats: 1_000, btcPrice: 0, currencyCode: "USD"))
    }

    // MARK: - Bitcoin symbol

    func testSmallAmountBitcoinSymbol() {
        XCTAssertEqual(AmountFormatter.sats(1, useBitcoinSymbol: true), "₿1")
    }

    func testGroupedThousandsBitcoinSymbol() {
        XCTAssertEqual(AmountFormatter.sats(1_000, useBitcoinSymbol: true), "₿1,000")
    }

    func testZeroBitcoinSymbol() {
        XCTAssertEqual(AmountFormatter.sats(0, useBitcoinSymbol: true), "₿0")
    }

    // MARK: - includeUnit: false

    func testNoUnitSatMode() {
        XCTAssertEqual(AmountFormatter.sats(1_000, useBitcoinSymbol: false, includeUnit: false), "1,000")
    }

    func testNoUnitBitcoinSymbolMode() {
        // Bitcoin symbol is the "unit", so it still omits the suffix.
        let result = AmountFormatter.sats(500, useBitcoinSymbol: true, includeUnit: false)
        XCTAssertEqual(result, "₿500")
    }

    func testZeroNoUnit() {
        XCTAssertEqual(AmountFormatter.sats(0, useBitcoinSymbol: false, includeUnit: false), "0")
    }

    // MARK: - Large amounts

    func testMaxSupplyAmount() {
        // 21 million BTC in sats
        let maxSats: UInt64 = 2_100_000_000_000_000
        let result = AmountFormatter.sats(maxSats, useBitcoinSymbol: false)
        XCTAssertTrue(result.hasSuffix(" sat"), "Large amount should still end with ' sat'")
        XCTAssertTrue(result.contains(","), "Large amount should have thousands separators")
    }

    // MARK: - AmountParts
    //
    // The typographic split. The unit must never be baked into the numeral
    // string, or the lockup cannot subordinate it. These tests pin the split
    // against the string API it was derived from, so the two cannot drift.

    func testSatsPartsSuffixMode() {
        let parts = AmountFormatter.satsParts(21_000, useBitcoinSymbol: false)
        XCTAssertEqual(parts.value, "21,000")
        XCTAssertEqual(parts.affix, .suffix("sat"))
        XCTAssertEqual(parts.joined, "21,000 sat")
    }

    func testSatsPartsSymbolMode() {
        let parts = AmountFormatter.satsParts(21_000, useBitcoinSymbol: true)
        XCTAssertEqual(parts.value, "21,000")
        XCTAssertEqual(parts.affix, .prefix("₿"))
        XCTAssertEqual(parts.joined, "₿21,000")
    }

    /// The numerals must be identical either way. If the symbol leaked into
    /// `value`, the two heroes would set different strings at different widths
    /// for the same amount.
    func testSatsPartsValueIsUnitAgnostic() {
        XCTAssertEqual(
            AmountFormatter.satsParts(1_234_567, useBitcoinSymbol: false).value,
            AmountFormatter.satsParts(1_234_567, useBitcoinSymbol: true).value
        )
    }

    /// The split must reproduce the string API exactly, for every amount shape
    /// and both unit modes.
    func testSatsPartsJoinMatchesSatsString() {
        for amount: UInt64 in [0, 1, 100, 1_000, 1_000_000, 2_100_000_000_000_000] {
            for symbol in [false, true] {
                XCTAssertEqual(
                    AmountFormatter.satsParts(amount, useBitcoinSymbol: symbol).joined,
                    AmountFormatter.sats(amount, useBitcoinSymbol: symbol),
                    "split diverged from sats(\(amount), useBitcoinSymbol: \(symbol))"
                )
            }
        }
    }

    /// Guards the one place the two conventions could diverge: a unit *word*
    /// joins with a space, a trailing currency *symbol* joins without one. Every
    /// currency the app offers is prefix-positioned under the pinned POSIX
    /// locale, so this holds today — and fails loudly if that ever changes.
    func testFiatPartsJoinMatchesFiat() {
        for code in SettingsManager.supportedFiatCurrencies {
            for amount in [0.0, 0.01, 60.0, 1_234.56] {
                XCTAssertEqual(
                    AmountFormatter.fiatParts(amount, currencyCode: code).joined,
                    AmountFormatter.fiat(amount, currencyCode: code),
                    "split diverged from fiat(\(amount), currencyCode: \(code))"
                )
            }
        }
    }

    func testFiatPartsSeparatesSymbolFromNumerals() {
        let parts = AmountFormatter.fiatParts(60, currencyCode: "USD")
        XCTAssertEqual(parts.value, "60.00")
        XCTAssertEqual(parts.affix, .prefix("$"))
    }

    /// VoiceOver reads the word, never the glyph — "₿" announces as nothing
    /// useful on its own.
    func testSpokenFormExpandsBitcoinSymbol() {
        XCTAssertEqual(
            AmountFormatter.satsParts(500, useBitcoinSymbol: true).spoken,
            "500 sats"
        )
        XCTAssertEqual(
            AmountFormatter.satsParts(500, useBitcoinSymbol: false).spoken,
            "500 sat"
        )
    }
}
