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

    /// The ₿ boost — the wallet's one deliberate divergence from the web
    /// terrain (mirrors Android `displayLevelBoostsPeaks`). `pickLevel` stays
    /// pinned by the fixture; only the renderer's `displayLevel` promotes the
    /// top of the currency band to the peak glyph.
    func testDisplayLevelBoostsPeaks() {
        XCTAssertEqual(AsciiFieldTerrain.peakBoostMin, 208)
        XCTAssertEqual(AsciiFieldTerrain.displayLevel(207), 3)
        XCTAssertEqual(AsciiFieldTerrain.displayLevel(208), 4)
        XCTAssertEqual(AsciiFieldTerrain.displayLevel(216), 4)
        XCTAssertEqual(AsciiFieldTerrain.displayLevel(199), 2)
        XCTAssertEqual(AsciiFieldTerrain.displayLevel(39), -1)
    }
}

/// Parity vectors for the lens warp (mirrors Android `AsciiFieldWarpTest`).
///
/// Unlike the terrain, the warp has no web original: the vectors are
/// hand-derived from the agreed formula and pasted identically into both
/// platforms' tests. If a port disagrees, fix the port — never the vector.
final class AsciiFieldWarpTests: XCTestCase {
    func testDisplacementMatchesParityVectors() {
        // Bump peak at full envelope (radius fully bloomed): s = 0.5 → 36.
        XCTAssertEqual(AsciiFieldWarp.displacement(60, 1), 36.0, accuracy: 1e-9)
        // Half envelope blooms the radius to 105; peak sits at 52.5.
        XCTAssertEqual(AsciiFieldWarp.displacement(52.5, 0.5), 18.0, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.displacement(50, 0.5), 17.91845990096719, accuracy: 1e-9)
        // Zero at the touch point, at/beyond the bloomed rim, and at zero
        // envelope.
        XCTAssertEqual(AsciiFieldWarp.displacement(0, 1), 0)
        XCTAssertEqual(AsciiFieldWarp.displacement(120, 1), 0)
        XCTAssertEqual(AsciiFieldWarp.displacement(105, 0.5), 0)
        XCTAssertEqual(AsciiFieldWarp.displacement(150, 1), 0)
        XCTAssertEqual(AsciiFieldWarp.displacement(60, 0), 0)
    }

    func testBloomedRadiusMatchesParityVectors() {
        XCTAssertEqual(AsciiFieldWarp.bloomedRadius(0), 90.0, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.bloomedRadius(0.5), 105.0, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.bloomedRadius(1), 120.0, accuracy: 1e-9)
        // Overshoot never grows the lens past full.
        XCTAssertEqual(AsciiFieldWarp.bloomedRadius(2), 120.0, accuracy: 1e-9)
    }

    func testEnvelopesMatchParityVectors() {
        XCTAssertEqual(AsciiFieldWarp.pressEnvelope(elapsed: 0.28, from: 0), 1.0, accuracy: 1e-9)
        // Mid-press is already past 1 — the easeOutBack bloom.
        XCTAssertEqual(AsciiFieldWarp.pressEnvelope(elapsed: 0.14, from: 0), 1.025, accuracy: 1e-9)
        // Re-press mid-decay ramps from the current envelope, not from zero.
        XCTAssertEqual(AsciiFieldWarp.pressEnvelope(elapsed: 0.07, from: 0.4), 0.848125, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.releaseEnvelope(elapsed: 0.3, from: 1), 0.125, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.releaseEnvelope(elapsed: 0.15, from: 0.8), 0.3375, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.releaseEnvelope(elapsed: 0.7, from: 1), 0.0, accuracy: 1e-9)
        // The overshoot stays within its designed bound.
        for step in 0...200 {
            let k = AsciiFieldWarp.pressEnvelope(elapsed: Double(step) / 200 * 0.28, from: 0)
            XCTAssertLessThanOrEqual(k, 1.0529, "overshoot bound at step \(step)")
            XCTAssertGreaterThanOrEqual(k, 0, "negative envelope at step \(step)")
        }
    }

    func testSwirlAndFollowMatchParityVectors() {
        XCTAssertEqual(AsciiFieldWarp.swirlAngle(36), 0.35, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.swirlAngle(18), 0.175, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.swirlAngle(0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.followFactor(1.0 / 30.0), 0.3788548423845485, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.followFactor(1.0 / 60.0), 0.21187237225468902, accuracy: 1e-9)
        XCTAssertEqual(AsciiFieldWarp.followFactor(0), 0.0, accuracy: 1e-9)
    }

    /// The constants both ports share; retuning is a keep-in-lockstep edit of
    /// both platform files plus these vectors.
    func testWarpConstantsShape() {
        XCTAssertEqual(AsciiFieldWarp.radius, 120)
        XCTAssertEqual(AsciiFieldWarp.radiusBloomFloor, 0.75)
        XCTAssertEqual(AsciiFieldWarp.maxDisplacement, 36)
        XCTAssertEqual(AsciiFieldWarp.pressDuration, 0.28)
        XCTAssertEqual(AsciiFieldWarp.releaseDuration, 0.6)
        XCTAssertEqual(AsciiFieldWarp.backOvershoot, 1.2)
        XCTAssertEqual(AsciiFieldWarp.swirlMax, 0.35)
        XCTAssertEqual(AsciiFieldWarp.followTau, 0.07)
    }

    /// Warped sampling must never fold: `d - displacement(d)` non-decreasing
    /// across the lens — checked at the overshoot peak (k = 1.053), the
    /// worst case, or terrain would mirror inside the ring.
    func testDisplacementNeverFoldsSampling() {
        var previous = -Double.infinity
        for step in 0...1200 {
            let d = Double(step) / 10
            let warped = d - AsciiFieldWarp.displacement(d, 1.053)
            XCTAssertGreaterThanOrEqual(warped, previous - 1e-12, "fold at d=\(d)")
            previous = warped
        }
    }
}

/// CPU cost of one frame's terrain pass through brightness → pickLevel →
/// bucket. The draw side is 5 batched fills on Metal; this math is the only
/// per-frame CPU work, and it must stay far under the 33ms frame budget at
/// 30fps. Two sizes are pinned: 34 × 29 cells is the culled Restore band on
/// a 6.1" phone (chassis underlap included), and 34 × 68 is welcome's
/// full-window field on a 6.7" phone — the largest pass the mask extent can
/// ask for.
final class AsciiFieldFrameBudgetTests: XCTestCase {
    private func plainPassMs(cols: Int, rows: Int) -> Double {
        var buckets = [[Double]](repeating: [], count: 5)
        let start = CACurrentMediaTime()
        let frames = 100
        for frame in 0..<frames {
            let t = Double(frame) / 30.0 * AsciiFieldTerrain.speed
            for level in 0..<5 { buckets[level].removeAll(keepingCapacity: true) }
            for row in 0..<rows {
                let sy = (Double(row) + 0.5) * AsciiFieldTerrain.terrainScale
                for col in 0..<cols {
                    let level = AsciiFieldTerrain.displayLevel(
                        AsciiFieldTerrain.brightness((Double(col) + 0.5) * AsciiFieldTerrain.terrainScale, sy, t)
                    )
                    if level < 0 { continue }
                    buckets[level].append(Double(col) * 12 + 6)
                    buckets[level].append(Double(row) * 14 + 7)
                }
            }
        }
        return (CACurrentMediaTime() - start) / Double(frames) * 1000
    }

    /// The same pass with the lens fully open (k = 1): the warp adds a square
    /// root and a few multiplies per cell against the baseline's 45 trig
    /// calls — pinned so the interactive path can't regress the budget.
    private func warpedPassMs(cols: Int, rows: Int) -> Double {
        var buckets = [[Double]](repeating: [], count: 5)
        // A mid-band finger, in the grid units the renderer uses.
        let tx = 204.0
        let ty = 203.0
        let start = CACurrentMediaTime()
        let frames = 100
        for frame in 0..<frames {
            let t = Double(frame) / 30.0 * AsciiFieldTerrain.speed
            for level in 0..<5 { buckets[level].removeAll(keepingCapacity: true) }
            for row in 0..<rows {
                let py = Double(row) * 14 + 7
                let sy = (Double(row) + 0.5) * AsciiFieldTerrain.terrainScale
                for col in 0..<cols {
                    let px = Double(col) * 12 + 6
                    var sampleX = (Double(col) + 0.5) * AsciiFieldTerrain.terrainScale
                    var sampleY = sy
                    let dx = px - tx
                    let dy = py - ty
                    let d = (dx * dx + dy * dy).squareRoot()
                    let f = AsciiFieldWarp.displacement(d, 1)
                    if f > 0 {
                        let theta = AsciiFieldWarp.swirlAngle(f)
                        let cosT = cos(theta)
                        let sinT = sin(theta)
                        let inv = f / d
                        sampleX = (px - (dx * cosT - dy * sinT) * inv) / 12 * AsciiFieldTerrain.terrainScale
                        sampleY = (py - (dx * sinT + dy * cosT) * inv) / 14 * AsciiFieldTerrain.terrainScale
                    }
                    let level = AsciiFieldTerrain.displayLevel(
                        AsciiFieldTerrain.brightness(sampleX, sampleY, t)
                    )
                    if level < 0 { continue }
                    buckets[level].append(px)
                    buckets[level].append(py)
                }
            }
        }
        return (CACurrentMediaTime() - start) / Double(frames) * 1000
    }

    func testFrameComputationWellUnderFrameBudget() {
        let perFrameMs = plainPassMs(cols: 34, rows: 29)
        // Debug, unoptimized, still expected ~1ms; the ceiling is generous so
        // CI noise can't flake it while a real regression (e.g. accidental
        // per-cell allocation) still trips.
        XCTAssertLessThan(perFrameMs, 15, "terrain pass took \(perFrameMs)ms per frame")
        print("AsciiField terrain pass: \(String(format: "%.3f", perFrameMs))ms per frame (34×29 cells)")
    }

    func testWarpedFrameComputationWellUnderFrameBudget() {
        let perFrameMs = warpedPassMs(cols: 34, rows: 29)
        XCTAssertLessThan(perFrameMs, 15, "warped terrain pass took \(perFrameMs)ms per frame")
        print("AsciiField warped terrain pass: \(String(format: "%.3f", perFrameMs))ms per frame (34×29 cells)")
    }

    func testFullWindowFrameComputationWellUnderFrameBudget() {
        let perFrameMs = plainPassMs(cols: 34, rows: 68)
        XCTAssertLessThan(perFrameMs, 15, "full-window terrain pass took \(perFrameMs)ms per frame")
        print("AsciiField full-window terrain pass: \(String(format: "%.3f", perFrameMs))ms per frame (34×68 cells)")
    }

    func testFullWindowWarpedFrameComputationWellUnderFrameBudget() {
        let perFrameMs = warpedPassMs(cols: 34, rows: 68)
        XCTAssertLessThan(perFrameMs, 15, "full-window warped terrain pass took \(perFrameMs)ms per frame")
        print("AsciiField full-window warped terrain pass: \(String(format: "%.3f", perFrameMs))ms per frame (34×68 cells)")
    }
}

/// The field geometry contract (mirrors Android `AsciiFieldLayoutTest`): the
/// resolved geometry is a pure function of window geometry — it takes no
/// step, no header measurement, no stage content, which is what guarantees
/// the terrain's full-window layer is identical on Welcome and Restore
/// Wallet; the mask extent is the *only* per-step input — plus the
/// tight-space suppression rule below the 120pt threshold.
final class AsciiFieldLayoutTests: XCTestCase {
    /// Fixed stand-in for `AsciiFieldLayout.headerClearance()` so assertions
    /// don't float with the test host's Dynamic Type setting.
    private let clearance: CGFloat = 171
    private let chassis: CGFloat = 176
    private let topInset: CGFloat = 47

    private func phoneLayout() -> AsciiFieldLayout.Resolution {
        AsciiFieldLayout.resolve(
            windowHeight: 844, topInset: topInset, chassisInset: chassis, headerClearance: clearance
        )!
    }

    func testBandClampsAgainstWindowHeightAndLayerSpansTheWindow() {
        // Portrait phone: 26% of the window, inside the clamp; the drawn
        // layer is the whole window — the glyph grid must not depend on the
        // band so the mask extent can settle without the texture re-hashing.
        let phone = phoneLayout()
        XCTAssertEqual(phone.visibleBand, 0.26 * 844, accuracy: 0.01)
        XCTAssertEqual(phone.layerHeight, 844, accuracy: 0.01)

        // Small window: the 160pt floor holds.
        let small = AsciiFieldLayout.resolve(
            windowHeight: 590, topInset: 20, chassisInset: 120, headerClearance: clearance
        )
        XCTAssertEqual(small?.visibleBand, 160)
        XCTAssertEqual(small?.layerHeight, 590)

        // Tall window: the 300pt ceiling holds.
        let tall = AsciiFieldLayout.resolve(
            windowHeight: 1400, topInset: topInset, chassisInset: chassis, headerClearance: clearance
        )
        XCTAssertEqual(tall?.visibleBand, 300)
    }

    func testIdenticalInputsResolveIdentically() {
        // The welcome/restore pair share window and chassis geometry; the
        // resolver has no other inputs, so their layers cannot differ. The
        // steps diverge only in the extent their masks are driven to.
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

    func testBandModeIsTheLegacyBandGeometryInWindowCoordinates() {
        // Extent 0 must reproduce the shipped band exactly: clear down to the
        // band top, the web's 30%-of-band ramp, and the same bottom fade —
        // the Restore screen is unchanged by the full-mode work.
        let layout = phoneLayout()
        let band = layout.visibleBand
        let bandTop = 844 - chassis - band
        XCTAssertEqual(layout.bandClearEnd, bandTop / 844, accuracy: 1e-4)
        XCTAssertEqual(layout.bandOpaqueEnd, (bandTop + 0.30 * band) / 844, accuracy: 1e-4)
        XCTAssertEqual(layout.bottomFadeStart, (844 - chassis - 48) / 844, accuracy: 1e-4)
        XCTAssertEqual(layout.bottomFadeEnd, (844 - chassis + 40) / 844, accuracy: 1e-4)
    }

    func testFullModeClearsTheHeaderBlock() {
        // Extent 1: fully transparent through the header clearance line, then
        // the long 0.30-window ramp. Uncramped geometry — no clamps engage.
        let layout = phoneLayout()
        XCTAssertEqual(layout.fullClearEnd, (topInset + clearance) / 844, accuracy: 1e-4)
        XCTAssertEqual(layout.fullOpaqueEnd, layout.fullClearEnd + 0.30, accuracy: 1e-4)
        // The settle has real travel on a phone — the whole point.
        XCTAssertLessThan(layout.fullClearEnd, layout.bandClearEnd - 0.2)
    }

    func testFullModeDegradesToBandModeWhenTheHeaderReachesTheBand() {
        // 120 ≤ available < band: not suppressed, but the header block ends
        // below the band top. Full mode must clamp to band mode so the settle
        // becomes a no-op instead of inverting direction.
        let layout = AsciiFieldLayout.resolve(
            windowHeight: 700, topInset: 20, chassisInset: 250, headerClearance: 280
        )!
        XCTAssertEqual(layout.fullClearEnd, layout.bandClearEnd, accuracy: 1e-6)
        XCTAssertEqual(layout.fullOpaqueEnd, layout.bandOpaqueEnd, accuracy: 1e-6)
        let full = layout.maskStops(extent: 1)
        let bandStops = layout.maskStops(extent: 0)
        XCTAssertEqual(full.clearEnd, bandStops.clearEnd, accuracy: 1e-6)
        XCTAssertEqual(full.opaqueEnd, bandStops.opaqueEnd, accuracy: 1e-6)
    }

    func testMaskStopsLerpEndpointsClampAndStayOrdered() {
        let layout = phoneLayout()
        let atBand = layout.maskStops(extent: 0)
        XCTAssertEqual(atBand.clearEnd, layout.bandClearEnd, accuracy: 1e-6)
        XCTAssertEqual(atBand.opaqueEnd, layout.bandOpaqueEnd, accuracy: 1e-6)
        let atFull = layout.maskStops(extent: 1)
        XCTAssertEqual(atFull.clearEnd, layout.fullClearEnd, accuracy: 1e-6)
        XCTAssertEqual(atFull.opaqueEnd, layout.fullOpaqueEnd, accuracy: 1e-6)
        // A bouncy animation curve can overshoot the 0…1 target range; the
        // stops must clamp, not extrapolate.
        XCTAssertEqual(layout.maskStops(extent: -0.2).clearEnd, atBand.clearEnd, accuracy: 1e-6)
        XCTAssertEqual(layout.maskStops(extent: 1.3).clearEnd, atFull.clearEnd, accuracy: 1e-6)
        // The gradient's stop order must survive every point of the settle.
        for e in stride(from: CGFloat(0), through: 1, by: 0.25) {
            let stops = layout.maskStops(extent: e)
            XCTAssertLessThan(stops.clearEnd, stops.opaqueEnd, "extent \(e)")
            XCTAssertLessThanOrEqual(stops.opaqueEnd, layout.bottomFadeStart, "extent \(e)")
            XCTAssertLessThan(layout.bottomFadeStart, layout.bottomFadeEnd, "extent \(e)")
            XCTAssertLessThanOrEqual(layout.bottomFadeEnd, 1, "extent \(e)")
        }
    }

    func testCullStartRowSkipsOnlyFullyMaskedRows() {
        // No cull at zero.
        XCTAssertEqual(AsciiFieldLayout.cullStartRow(transparentStart: 0), 0)
        // Less than a cell of transparency: the slack row keeps it at zero.
        XCTAssertEqual(AsciiFieldLayout.cullStartRow(transparentStart: 10), 0)
        let layout = phoneLayout()
        // Band mode on the phone fixture: the layer is 62 rows
        // (ceil(844/14)+1); the cull leaves ~31 — the shipped band's cost,
        // plus one slack row for ink overhang.
        let bandCull = AsciiFieldLayout.cullStartRow(
            transparentStart: layout.transparentStart(extent: 0)
        )
        XCTAssertEqual(bandCull, 31)
        // Full mode still culls the header block's rows.
        let fullCull = AsciiFieldLayout.cullStartRow(
            transparentStart: layout.transparentStart(extent: 1)
        )
        XCTAssertEqual(fullCull, 14)
    }

    func testFallbackKeepsTheFullWindowFrame() {
        // Suppression hides rather than unmounts, so the fallback frame must
        // match the resolved frame — a pass through a suppressed layout (a
        // rotation, a Dynamic Type change) must not move the layer.
        let fallback = AsciiFieldLayout.fallback(
            windowHeight: 844, topInset: topInset, chassisInset: chassis, headerClearance: clearance
        )
        XCTAssertEqual(fallback.layerHeight, phoneLayout().layerHeight)
        // A chassis shallower than the underlap clamps the fade inside it.
        let shallow = AsciiFieldLayout.fallback(
            windowHeight: 400, topInset: 0, chassisInset: 24, headerClearance: clearance
        )
        XCTAssertEqual(shallow.bottomFadeEnd, 1, accuracy: 1e-4)
        // The zero-size transient layout pass must stay finite.
        let degenerate = AsciiFieldLayout.fallback(
            windowHeight: 0, topInset: 0, chassisInset: 24, headerClearance: clearance
        )
        XCTAssertGreaterThan(degenerate.layerHeight, 0)
        XCTAssertGreaterThanOrEqual(degenerate.bandClearEnd, 0)
        XCTAssertLessThanOrEqual(degenerate.bottomFadeEnd, 1)
    }
}
