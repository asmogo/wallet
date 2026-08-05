import XCTest
@testable import CashuWallet

/// Golden-vector parity for the ASCII field terrain.
///
/// `docs/product/ascii-field-vectors.json` is generated from the cashu.space
/// website's TypeScript (`ascii-field.tsx`), never from either native port —
/// it is the only thing that proves two independently hand-written ports
/// compute identical terrain. A transposed coefficient produces terrain that
/// looks plausible and is silently wrong; these assertions are how it gets
/// caught. If a record here fails, fix the port — never the fixture.
final class AsciiFieldTerrainTests: XCTestCase {
    private struct TerrainRecord: Decodable {
        let x: Double
        let y: Double
        let t: Double
        let f: Double
        let b: Int
        let level: Int
    }

    private struct CurrencyRecord: Decodable {
        let px: Double
        let py: Double
        let glyph: String
    }

    private struct Fixture: Decodable {
        let terrain: [TerrainRecord]
        let currency: [CurrencyRecord]
    }

    private func loadFixture() throws -> Fixture {
        // Repo-relative from this source file; unit tests run with host file
        // system access, so no test-bundle resource registration is needed.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CashuWalletTests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("docs/product/ascii-field-vectors.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testTerrainMatchesWebVectors() throws {
        let fixture = try loadFixture()
        XCTAssertGreaterThanOrEqual(fixture.terrain.count, 40, "fixture unexpectedly thin")
        for record in fixture.terrain {
            let fractal = AsciiFieldTerrain.fractal(record.x, record.y, record.t)
            XCTAssertEqual(
                fractal, record.f, accuracy: 1e-4,
                "fractal(\(record.x), \(record.y), \(record.t))"
            )
            let brightness = AsciiFieldTerrain.brightness(record.x, record.y, record.t)
            XCTAssertEqual(
                Double(brightness), Double(record.b), accuracy: 1e-4,
                "brightness(\(record.x), \(record.y), \(record.t))"
            )
            XCTAssertEqual(
                AsciiFieldTerrain.pickLevel(brightness), record.level,
                "level(\(record.x), \(record.y), \(record.t))"
            )
        }
    }

    /// The currency hash relies on JS `Math.imul` (32-bit signed wraparound)
    /// and `>>>` (unsigned shift) semantics. The fixture includes coordinates
    /// large enough that a 64-bit multiply silently diverges.
    func testCurrencyGlyphsMatchWebVectors() throws {
        let fixture = try loadFixture()
        XCTAssertGreaterThanOrEqual(fixture.currency.count, 10, "fixture unexpectedly thin")
        for record in fixture.currency {
            let index = AsciiFieldTerrain.currencyGlyphIndex(px: record.px, py: record.py)
            XCTAssertEqual(
                AsciiFieldTerrain.currencyGlyphs[index], record.glyph,
                "currency(\(record.px), \(record.py))"
            )
        }
    }

    /// The level thresholds and glyph tables must stay in lockstep with the
    /// web constants the fixture was generated from.
    func testLevelTableShape() {
        XCTAssertEqual(AsciiFieldTerrain.levelMin, [40, 90, 140, 200, 216])
        XCTAssertEqual(AsciiFieldTerrain.levelGlyph, ["·", "/", ","])
        XCTAssertEqual(AsciiFieldTerrain.currencyGlyphs, ["$", "¥", "€"])
        XCTAssertEqual(AsciiFieldTerrain.pickLevel(39), -1)
        XCTAssertEqual(AsciiFieldTerrain.pickLevel(40), 0)
        XCTAssertEqual(AsciiFieldTerrain.pickLevel(255), 4)
    }
}

/// CPU cost of one frame's terrain pass — every cell of a 6.1" phone's band
/// (34 × 29 cells including the chassis underlap) through brightness →
/// pickLevel → bucket. The draw side is 5 batched fills on Metal; this math
/// is the only per-frame CPU work, and it must stay far under the 33ms frame
/// budget at 30fps.
final class AsciiFieldFrameBudgetTests: XCTestCase {
    func testFrameComputationWellUnderFrameBudget() {
        let cols = 34
        let rows = 29
        var buckets = [[Double]](repeating: [], count: 5)
        let start = CACurrentMediaTime()
        let frames = 100
        for frame in 0..<frames {
            let t = Double(frame) / 30.0 * AsciiFieldTerrain.speed
            for level in 0..<5 { buckets[level].removeAll(keepingCapacity: true) }
            for row in 0..<rows {
                let sy = (Double(row) + 0.5) * AsciiFieldTerrain.terrainScale
                for col in 0..<cols {
                    let level = AsciiFieldTerrain.pickLevel(
                        AsciiFieldTerrain.brightness((Double(col) + 0.5) * AsciiFieldTerrain.terrainScale, sy, t)
                    )
                    if level < 0 { continue }
                    buckets[level].append(Double(col) * 12 + 6)
                    buckets[level].append(Double(row) * 14 + 7)
                }
            }
        }
        let perFrameMs = (CACurrentMediaTime() - start) / Double(frames) * 1000
        // Debug, unoptimized, still expected ~1ms; the ceiling is generous so
        // CI noise can't flake it while a real regression (e.g. accidental
        // per-cell allocation) still trips.
        XCTAssertLessThan(perFrameMs, 15, "terrain pass took \(perFrameMs)ms per frame")
        print("AsciiField terrain pass: \(String(format: "%.3f", perFrameMs))ms per frame (\(cols)×\(rows) cells)")
    }
}

/// The band geometry contract (mirrors Android `AsciiFieldLayoutTest`): the
/// resolved frame is a pure function of window geometry — it takes no step,
/// no header measurement, no stage content, which is what guarantees the
/// terrain's frame is identical on Welcome and Restore Wallet (§7c) — plus
/// the tight-space suppression rule below the 120pt threshold (§8).
final class AsciiFieldLayoutTests: XCTestCase {
    /// Fixed stand-in for `AsciiFieldLayout.headerClearance()` so assertions
    /// don't float with the test host's Dynamic Type setting.
    private let clearance: CGFloat = 171
    private let chassis: CGFloat = 176
    private let topInset: CGFloat = 47

    func testBandClampsAgainstWindowHeight() {
        // Portrait phone: 26% of the window, inside the clamp.
        let phone = AsciiFieldLayout.resolve(
            windowHeight: 844, topInset: topInset, chassisInset: chassis, headerClearance: clearance
        )
        XCTAssertNotNil(phone)
        XCTAssertEqual(phone!.visibleBand, 0.26 * 844, accuracy: 0.01)
        XCTAssertEqual(phone!.layerHeight, phone!.visibleBand + chassis, accuracy: 0.01)

        // Small window: the 160pt floor holds.
        let small = AsciiFieldLayout.resolve(
            windowHeight: 590, topInset: 20, chassisInset: 120, headerClearance: clearance
        )
        XCTAssertEqual(small?.visibleBand, 160)

        // Tall window: the 300pt ceiling holds.
        let tall = AsciiFieldLayout.resolve(
            windowHeight: 1400, topInset: topInset, chassisInset: chassis, headerClearance: clearance
        )
        XCTAssertEqual(tall?.visibleBand, 300)
    }

    func testIdenticalInputsResolveIdentically() {
        // The welcome/restore pair share window and chassis geometry; the
        // resolver has no other inputs, so their frames cannot differ.
        let a = AsciiFieldLayout.resolve(
            windowHeight: 844, topInset: topInset, chassisInset: chassis, headerClearance: clearance
        )
        let b = AsciiFieldLayout.resolve(
            windowHeight: 844, topInset: topInset, chassisInset: chassis, headerClearance: clearance
        )
        XCTAssertEqual(a, b)
    }

    func testSuppressesLandscapePhone() {
        XCTAssertNil(
            AsciiFieldLayout.resolve(
                windowHeight: 390, topInset: 0, chassisInset: 150, headerClearance: clearance
            )
        )
    }

    func testSuppressionThresholdIsExact() {
        // available = window − top − clearance − chassis; the band draws at
        // exactly 120pt of room and not below.
        let atThreshold = 120 + topInset + clearance + chassis
        XCTAssertNotNil(
            AsciiFieldLayout.resolve(
                windowHeight: atThreshold, topInset: topInset,
                chassisInset: chassis, headerClearance: clearance
            )
        )
        XCTAssertNil(
            AsciiFieldLayout.resolve(
                windowHeight: atThreshold - 1, topInset: topInset,
                chassisInset: chassis, headerClearance: clearance
            )
        )
    }

    func testMaskFadeCoversTopOfVisibleBandOnly() {
        let layout = AsciiFieldLayout.resolve(
            windowHeight: 844, topInset: topInset, chassisInset: chassis, headerClearance: clearance
        )!
        XCTAssertEqual(
            layout.maskOpaqueFraction,
            layout.visibleBand * 0.30 / layout.layerHeight,
            accuracy: 1e-4
        )
        XCTAssertLessThan(layout.maskOpaqueFraction, 0.30)
    }
}
