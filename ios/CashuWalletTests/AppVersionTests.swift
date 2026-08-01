import XCTest
@testable import CashuWallet

final class AppVersionTests: XCTestCase {
    func testDisplayStringComesFromMainBundleMetadata() {
        let expected = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertNotNil(expected)
        XCTAssertEqual(AppVersion.displayString(), expected)
    }

    func testDisplayStringMatchesMarketingVersionBuildSetting() {
        // The hosted test bundle's main bundle is CashuWallet.app, whose
        // CFBundleShortVersionString is generated from MARKETING_VERSION.
        XCTAssertEqual(AppVersion.displayString(), "1.0")
    }

    func testDisplayStringFallsBackToNilWhenVersionMissing() {
        XCTAssertNil(AppVersion.displayString(version: nil))
        XCTAssertNil(AppVersion.displayString(version: ""))
    }
}
