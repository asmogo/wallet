import SwiftUI
import UIKit
import XCTest
@testable import CashuWallet

/// The ratchet — iOS half.
///
/// Android has carried `TypographyGuardTest` since the type system landed;
/// iOS carried the larger drift and none of the enforcement, which is backwards.
/// These mirror the Android tests where the concept transfers (frozen role
/// inventory, tabular money, a line box no smaller than its type) and add the
/// checks that are specific to this platform's failure modes.
///
/// Two kinds of test live here, deliberately labelled:
///
/// - **Bans** are absolute and their allowlists are empty. Adding an entry means
///   consciously reintroducing the defect.
/// - **Ratchets** carry a ceiling that reflects today's known debt. They exist so
///   the debt cannot *grow* while it is being paid down. Lower them; never raise
///   them.
final class TypographyGuardTests: XCTestCase {

    // MARK: - Source scanning

    /// The app sources, minus the type layer itself — which necessarily names
    /// the primitives everything else is banned from touching.
    private func sources() throws -> [(path: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CashuWalletTests
            .deletingLastPathComponent()   // ios
            .appendingPathComponent("CashuWallet")

        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.path),
            "Source tree not readable from the test host — source-scanning guards skipped"
        )

        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ) else { return [] }

        return walker.compactMap { entry in
            guard let url = entry as? URL, url.pathExtension == "swift" else { return nil }
            let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
            guard !path.hasPrefix("DesignSystem/") else { return nil }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (path, text)
        }
    }

    private func occurrences(of pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(
            in: text, range: NSRange(text.startIndex..., in: text)
        )
    }

    // MARK: - Bans

    /// **Ban.** The app has one sans, and it is the system face.
    ///
    /// `design: .rounded` is a second family wearing the first one's API. It is
    /// how the balance and the amount being typed one screen later ended up in
    /// two different typefaces — and the split ran along an `if isSatUnit`
    /// branch, so whether a user saw it depended on their mint's unit.
    ///
    /// The allowlist is empty and must stay that way.
    func testNoRoundedFaceOutsideTheTypeLayer() throws {
        let offenders = try sources()
            .filter { occurrences(of: #"design:\s*\.rounded"#, in: $0.text) > 0 }
            .map(\.path)

        XCTAssertTrue(
            offenders.isEmpty,
            """
            `design: .rounded` is a second typeface. Amounts belong on the ladder \
            (.amountHero / .amountConfirm / .amountCompact / .amountRow) via \
            AmountLockup or .cashuAmount. Offenders: \(offenders.sorted())
            """
        )
    }

    // MARK: - Ratchets

    /// **Ratchet.** Hardcoded point sizes.
    ///
    /// Not a ban, because `.font(.system(size:))` is also how an `Image(systemName:)`
    /// is scaled, and an SF Symbol sized to its container is legitimate. The
    /// remaining occurrences are a mix of that and genuine un-migrated text, so
    /// the ceiling holds the line while they are separated.
    ///
    /// Lower this number. Never raise it.
    func testHardcodedPointSizesDoNotSpread() throws {
        let ceiling = 18
        let counts = try sources()
            .map { (path: $0.path, n: occurrences(of: #"\.font\(\.system\(size:"#, in: $0.text)) }
            .filter { $0.n > 0 }
        let total = counts.reduce(0) { $0 + $1.n }

        XCTAssertLessThanOrEqual(
            total, ceiling,
            """
            Hardcoded point sizes grew from \(ceiling) to \(total). Text takes a role \
            (.cashuText / .cashuAmount); only symbol sizing may name a point size. \
            Current: \(counts.sorted { $0.path < $1.path }.map { "\($0.path):\($0.n)" })
            """
        )
    }

    /// **Ratchet.** Raw tracking at call sites.
    ///
    /// A point value cannot scale: `.tracking(-0.5)` is correct at exactly one
    /// text size and wrong at every other. Tracking belongs in `CashuTracking`,
    /// expressed in em and resolved against the live point size.
    ///
    /// Shrink this list. Never add to it.
    func testRawTrackingDoesNotSpread() throws {
        let known: Set<String> = [
            "Views/Main/OnboardingView.swift",
            "Views/Send/Components/ClipboardPaymentChip.swift",
            "Views/Send/SendView.swift",
            "Views/Settings/P2PKSettingsSection.swift",
        ]
        let offenders = Set(
            try sources()
                .filter { occurrences(of: #"\.tracking\("#, in: $0.text) > 0 }
                .map(\.path)
        )

        XCTAssertTrue(
            offenders.subtracting(known).isEmpty,
            """
            New raw tracking. Add an em value to CashuTracking and reach it through \
            a role's trackingKey. New offenders: \(offenders.subtracting(known).sorted())
            """
        )
    }

    // MARK: - The vocabulary

    private static let roles: [(String, CashuTextRole)] = [
        ("amountHero", .amountHero), ("amountConfirm", .amountConfirm),
        ("amountCompact", .amountCompact), ("amountRow", .amountRow),
        ("numberPadKey", .numberPadKey), ("title", .title), ("title3", .title3),
        ("bodyEmphasis", .bodyEmphasis), ("body", .body), ("callout", .callout),
        ("textLink", .textLink), ("metadata", .metadata), ("caption", .caption),
        ("overline", .overline), ("monoBody", .monoBody), ("monoCaption", .monoCaption),
    ]

    /// The role budget, mirroring Android's. An unbounded vocabulary is the old
    /// drift wearing a nicer API, so growing it should be a reviewed act.
    func testRoleInventoryIsFrozen() {
        XCTAssertEqual(
            Self.roles.count, 16,
            "Adding or removing a role is a design decision — update this count deliberately"
        )
    }

    /// Every rung of the ladder carries tabular figures and a single line.
    func testMoneyRolesAreTabularAndSingleLine() {
        let ladder: [(String, CashuTextRole)] = [
            ("amountHero", .amountHero), ("amountConfirm", .amountConfirm),
            ("amountCompact", .amountCompact), ("amountRow", .amountRow),
        ]
        for (name, role) in ladder {
            XCTAssertTrue(role.isNumeric, "\(name) is not tabular")
            XCTAssertEqual(role.lineLimit, 1, "\(name) is not single-line")
        }
    }

    /// The ladder is four rungs and they are strictly ordered.
    ///
    /// Four sizes and no others is the whole rule; a ladder whose rungs overlap
    /// cannot express a hierarchy, and one that grows a fifth rung has stopped
    /// being a ladder.
    func testAmountLadderIsFourOrderedRungs() {
        let sizes = [CashuTextRole.amountHero, .amountConfirm, .amountCompact, .amountRow]
            .map { $0.pointSize(at: .large) }

        XCTAssertEqual(sizes.count, Set(sizes).count, "two rungs resolve to the same size")
        XCTAssertEqual(sizes, sizes.sorted(by: >), "the ladder is not descending: \(sizes)")
    }

    /// Every role gives its glyphs at least as much line as they occupy.
    /// Mirrors the Android assertion of the same name.
    func testEveryRoleHasALineBoxNoSmallerThanItsType() {
        for (name, role) in Self.roles {
            let pt = role.pointSize(at: .large)
            let line = role.lineHeight(at: .large, fonts: .system)
            XCTAssertGreaterThanOrEqual(
                line, pt,
                "\(name) sets \(pt)pt type in a \(line)pt line box"
            )
        }
    }

    /// A hero must be able to grow for large text, and must stop before it
    /// pushes the screen's actions out of reach.
    func testHeroRungsScaleAndClamp() {
        let heroes: [(String, CashuTextRole)] = [
            ("amountHero", .amountHero), ("amountConfirm", .amountConfirm),
            ("amountCompact", .amountCompact),
        ]
        for (name, role) in heroes {
            let base = role.pointSize(at: .large)
            let huge = role.pointSize(at: .accessibility5)
            XCTAssertGreaterThan(huge, base, "\(name) does not respond to Dynamic Type")

            guard case .hero(_, _, let cap) = role.size else {
                return XCTFail("\(name) is not a hero rung")
            }
            XCTAssertLessThanOrEqual(huge, cap, "\(name) exceeded its clamp at AX5")
        }
    }

    /// The overline is the documented 0.06em, uppercased by the role so no call
    /// site has to remember — the drift it replaced was six hand-rolled copies,
    /// five of them frozen at 0.1em.
    func testOverlineCarriesItsDocumentedTracking() {
        XCTAssertTrue(CashuTextRole.overline.uppercase, "the overline lost its casing")
        XCTAssertEqual(
            CashuFonts.system.tracking[keyPath: CashuTextRole.overline.trackingKey],
            0.060, accuracy: 0.0001,
            "the overline's tracking drifted from the documented 0.06em"
        )
    }

    /// Tracking is a fraction of the em, so it must resolve to a *different*
    /// point value at a different text size. This is the property a hardcoded
    /// `sp`/`pt` tracking value cannot have, and the reason the table is in em.
    func testTrackingScalesWithTextSize() {
        let role = CashuTextRole.overline
        let em = CashuFonts.system.tracking[keyPath: role.trackingKey]

        let small = role.pointSize(at: .large) * em
        let large = role.pointSize(at: .accessibility5) * em

        XCTAssertGreaterThan(
            large, small,
            "overline tracking did not grow with the text — it is frozen at one size"
        )
    }
}
