import XCTest
@testable import CashuWallet

/// Parity for the handoff's erosion curve.
///
/// Hand-authored vectors — there is no web counterpart to generate from, so
/// these values are mirrored verbatim in `AsciiFieldErosionTest.kt`. If a port
/// disagrees, fix the port. What the assertions defend is the *shape* the exit
/// depends on: the field must thin from its faintest matter upward, must never
/// brighten, and the ₿ peaks must still be standing when the dotted plain has
/// gone.
final class AsciiFieldErosionTests: XCTestCase {
    private let eps = 1e-9
    private var levels: Int { AsciiFieldTerrain.peakLevel + 1 }

    func testIntactFieldIsUntouched() {
        for level in 0..<levels {
            XCTAssertEqual(AsciiFieldTerrain.erosionAlpha(level: level, progress: 0), 1, accuracy: eps)
        }
    }

    func testEveryLevelIsGoneAtFullProgress() {
        for level in 0..<levels {
            XCTAssertEqual(AsciiFieldTerrain.erosionAlpha(level: level, progress: 1), 0, accuracy: eps)
        }
    }

    /// The last level's window must close exactly at 1.0, or the curtain would
    /// still be holding glyphs when the overlay unmounts and they would pop.
    func testPeakWindowClosesExactlyAtTheEnd() {
        let last = levels - 1
        let start = Double(last) * AsciiFieldTerrain.erosionStagger
        XCTAssertEqual(start + AsciiFieldTerrain.erosionWindow, 1, accuracy: eps)
        XCTAssertGreaterThan(AsciiFieldTerrain.erosionAlpha(level: last, progress: 0.999), 0)
    }

    /// The ordering the whole effect rests on: at any progress mid-dissolve, a
    /// stronger level is at least as present as a fainter one.
    func testStrongerLevelsAlwaysOutlastFainterOnes() {
        for step in 0...100 {
            let p = Double(step) / 100
            for level in 1..<levels {
                let faint = AsciiFieldTerrain.erosionAlpha(level: level - 1, progress: p)
                let strong = AsciiFieldTerrain.erosionAlpha(level: level, progress: p)
                XCTAssertGreaterThanOrEqual(
                    strong, faint - eps,
                    "level \(level) must outlast \(level - 1) at p=\(p)"
                )
            }
        }
    }

    /// Half-way through the exit the plain is gone and the peaks are barely
    /// touched — that gap is what makes the ₿ the last thing over the balance.
    func testMidDissolveLeavesPeaksStandingOverAClearedPlain() {
        XCTAssertEqual(AsciiFieldTerrain.erosionAlpha(level: 0, progress: 0.5), 0, accuracy: eps)
        XCTAssertGreaterThan(AsciiFieldTerrain.erosionAlpha(level: 4, progress: 0.5), 0.99)
    }

    func testAlphaNeverRisesAsTheDissolveAdvances() {
        for level in 0..<levels {
            var previous = 1.0
            for step in 0...200 {
                let p = Double(step) / 200
                let alpha = AsciiFieldTerrain.erosionAlpha(level: level, progress: p)
                XCTAssertLessThanOrEqual(alpha, previous + eps, "level \(level) rose at p=\(p)")
                XCTAssertTrue((0...1).contains(alpha), "level \(level) out of range at p=\(p)")
                previous = alpha
            }
        }
    }

    /// Pinned midpoints, so a retuned stagger or window is a deliberate edit to
    /// both ports rather than a silent drift in one.
    func testPinnedVectors() {
        XCTAssertEqual(AsciiFieldTerrain.erosionAlpha(level: 0, progress: 0.24), 0.5, accuracy: eps)
        XCTAssertEqual(AsciiFieldTerrain.erosionAlpha(level: 2, progress: 0.50), 0.5, accuracy: eps)
        XCTAssertEqual(AsciiFieldTerrain.erosionAlpha(level: 4, progress: 0.76), 0.5, accuracy: eps)
    }
}
