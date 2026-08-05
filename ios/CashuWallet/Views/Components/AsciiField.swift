import SwiftUI
import UIKit

// MARK: - Ascii Field
/// The onboarding terrain band, ported from the cashu.space hero
/// (`ascii-field.tsx`). A grid of monospaced glyphs driven by layered
/// sinusoidal noise: three fractal octaves produce a heightfield, and cells
/// near contour lines (height mod spacing) intensify, so drifting topographic
/// ridgelines emerge from a quiet dotted plain. The ramp runs faint → strong:
/// `·` and `/` fill the open field, `,` marks crests, $, ¥, and € mark high
/// contours, and ₿ caps the strongest peaks.
///
/// The web implementation is the reference — same coefficients, same order of
/// operations, same magic numbers. `docs/product/ascii-field-vectors.json`
/// (generated from the web TypeScript, not from either port) pins this port
/// and the Android one to identical terrain via `AsciiFieldTerrainTests`.
/// The glyph *shapes* are each platform's own mono face; only the math is
/// shared.

// MARK: - Terrain math

/// The pure terrain functions, verbatim from the web source. Kept free of any
/// view state so the golden-vector parity test can drive them directly.
enum AsciiFieldTerrain {
    /// Grid cell size in points. The terrain is texture, not text — the grid
    /// must not scale with Dynamic Type, or the composition itself would
    /// change with the user's font size.
    static let cellW: Double = 12
    static let cellH: Double = 14
    static let fontSize: CGFloat = 12
    static let terrainScale: Double = 0.13
    static let contourSpacing: Double = 0.08
    /// Half the web's 0.9. A marketing hero is scrolled past in seconds; this
    /// screen is stared at while someone decides whether to trust the app
    /// with their money. The field must be ambient texture noticed once, not
    /// something that pulls the eye while the headline is being read.
    static let speed: Double = 0.45

    /// Brightness thresholds ascend toward the stronger glyph; cells below the
    /// first threshold stay empty.
    static let levelMin: [Int] = [40, 90, 140, 200, 216]
    static let levelGlyph: [String] = ["·", "/", ","]
    static let currencyGlyphs: [String] = ["$", "¥", "€"]
    static let currencyLevel = 3
    static let peakLevel = 4

    static func noise(_ x: Double, _ y: Double, _ t: Double) -> Double {
        sin(0.8 * x + 0.3 * t) * cos(0.6 * y + 0.2 * t) * 0.5
            + 0.25 * sin(1.6 * x + 1.2 * y + 0.15 * t)
            + sin(0.3 * x - 0.4 * t) * cos(0.4 * y + 0.25 * t) * 0.6
            + 0.3 * sin(0.5 * (x + y) + 0.35 * t)
            + sin(2.5 * x + 0.1 * t) * cos(2.8 * y - 0.12 * t) * 0.15
    }

    static func fractal(_ x: Double, _ y: Double, _ t: Double) -> Double {
        noise(x, y, t)
            + 0.4 * noise(2.2 * x, 2.2 * y, 0.7 * t)
            + 0.15 * noise(4.5 * x, 4.5 * y, 0.4 * t)
    }

    static func brightness(_ x: Double, _ y: Double, _ t: Double) -> Int {
        let r = min(1, max(0, (fractal(x, y, t) + 1.8) / 3.6))
        let s = r.truncatingRemainder(dividingBy: contourSpacing) / contourSpacing
        let onContour = s < 0.12 || s > 0.88
        // Values are non-negative, so `.rounded()` (half away from zero)
        // matches JS `Math.round` (half toward +∞) exactly.
        var b = onContour ? Int((200 * r + 55).rounded()) : Int((140 * r).rounded())
        if onContour {
            // Steeper terrain sharpens its contour line.
            let gx = noise(x + 0.01, y, t) - noise(x - 0.01, y, t)
            let gy = noise(x, y + 0.01, t) - noise(x, y - 0.01, t)
            let d = 12 * (gx * gx + gy * gy).squareRoot()
            if d > 0.5 { b = min(255, b + Int((40 * d).rounded())) }
        }
        return b
    }

    /// Highest level whose threshold `b` clears; -1 draws nothing.
    static func pickLevel(_ b: Int) -> Int {
        for i in stride(from: levelMin.count - 1, through: 0, by: -1) where b >= levelMin[i] {
            return i
        }
        return -1
    }

    /// Stable spatial hash: a cell always keeps the same currency, so motion
    /// comes from the terrain crossing thresholds rather than random shimmer.
    /// Reproduces JS `Math.imul` (32-bit signed multiply with wraparound) and
    /// `>>>` (unsigned shift) exactly — get this wrong and the currency
    /// distribution silently diverges from Android; the parity fixture is what
    /// catches it.
    static func currencyGlyphIndex(px: Double, py: Double) -> Int {
        let col = Int32(truncatingIfNeeded: Int((px / cellW).rounded(.down)))
        let row = Int32(truncatingIfNeeded: Int((py / cellH).rounded(.down)))
        let hash = (col &* 31) ^ (row &* 17)
        let shifted = Int32(bitPattern: UInt32(bitPattern: hash) >> 13)
        let mixed = (hash ^ shifted) &* 1274126177
        return Int(UInt32(bitPattern: mixed) % 3)
    }
}

// MARK: - Layout

/// Band geometry as a pure function, so the layout-invariant test can assert
/// it without composing views.
///
/// The field pins to the *window* bottom and runs under the chassis; the
/// chassis' opaque background is what terminates it, so there is no visible
/// bottom edge and the terrain reads as continuing behind the buttons. The
/// on-screen glyph positions are a function of window size and the (constant
/// across the welcome/restore pair) chassis inset — never of header height,
/// stage content, or current step — which is what lets the terrain hold
/// perfectly still across the Welcome ↔ Restore Wallet swap.
enum AsciiFieldLayout {
    /// Web is `clamp(180px, 26vh, 320px)`; scaled slightly for phone-sized
    /// viewports.
    static let minBand: CGFloat = 160
    static let maxBand: CGFloat = 300
    static let bandFraction: CGFloat = 0.26
    /// Below this the band would be a squashed few-row smear behind
    /// accessibility-size copy (or a landscape phone) — draw nothing instead.
    static let suppressionThreshold: CGFloat = 120
    /// The mask ramps transparent → opaque over this fraction of the visible
    /// band (the web masks the top 30% of its fully-visible band; ours also
    /// extends under the chassis, so the fraction applies to the visible part).
    static let maskFade: CGFloat = 0.30

    struct Resolution: Equatable {
        /// Height of the band above the chassis — the part the user sees.
        var visibleBand: CGFloat
        /// Full layer height: visible band + chassis underlap.
        var layerHeight: CGFloat
        /// Where the mask becomes fully opaque, as a fraction of layerHeight.
        var maskOpaqueFraction: CGFloat
    }

    /// `headerClearance` is the vertical room the pair's tallest header
    /// (welcome's two-line title + subhead, at the live Dynamic Type size)
    /// needs. Using the same clearance for both steps of the pair keeps the
    /// resolved frame identical across them — the layout-invariant contract.
    static func resolve(
        windowHeight: CGFloat,
        topInset: CGFloat,
        chassisInset: CGFloat,
        headerClearance: CGFloat
    ) -> Resolution? {
        let band = min(max(minBand, bandFraction * windowHeight), maxBand)
        // The empty region between the header block and the chassis. When the
        // heavy largeTitle wraps at accessibility sizes (or the window is a
        // landscape phone), this collapses and the band is suppressed rather
        // than squashed — the band never shrinks to fit.
        let available = windowHeight - topInset - headerClearance - chassisInset
        guard min(band, available) >= suppressionThreshold else { return nil }
        let layerHeight = band + chassisInset
        return Resolution(
            visibleBand: band,
            layerHeight: layerHeight,
            maskOpaqueFraction: (band * maskFade) / layerHeight
        )
    }

    /// Welcome's header at the live type size: bar band + two title lines +
    /// gap + one subhead line. `preferredFont` metrics track Dynamic Type, so
    /// the suppression rule reacts to accessibility sizes without measuring
    /// live views (which would differ between the two steps).
    static func headerClearance() -> CGFloat {
        let title = UIFont.preferredFont(forTextStyle: .largeTitle).lineHeight
        let subhead = UIFont.preferredFont(forTextStyle: .callout).lineHeight
        return OnboardingMetrics.titleTopInset + title * 2 + 8 + subhead
    }
}

// MARK: - Peak glyph (the ₿ problem)

/// SF Mono is probed for a real U+20BF once at init. If it carries one, ₿ is
/// drawn directly; if not, the web's synthesis is reproduced: the font's own
/// `B` plus the official symbol's two vertical strokes as rects, anchored to
/// the B's measured ink bounds. Unlike the web's advance-width heuristic this
/// uses the real coverage API (`CTFontGetGlyphsForCharacters`).
struct AsciiFieldPeakGlyph {
    let isNative: Bool
    let glyph: String
    /// Ink-top / ink-bottom offsets from the glyph's draw center (synth only).
    let inkTopOffset: CGFloat
    let inkBottomOffset: CGFloat

    static let strokeWidth: CGFloat = 1
    static let strokeLength: CGFloat = 2
    static let strokeDX: CGFloat = 1.25

    static func probe(forceSynthesized: Bool = false) -> AsciiFieldPeakGlyph {
        let font = UIFont.monospacedSystemFont(ofSize: AsciiFieldTerrain.fontSize, weight: .regular)
        let ct = font as CTFont

        var btc: [UniChar] = [0x20BF]
        var btcGlyph: [CGGlyph] = [0]
        let native = !forceSynthesized && CTFontGetGlyphsForCharacters(ct, &btc, &btcGlyph, 1)
        if native {
            return AsciiFieldPeakGlyph(isNative: true, glyph: "₿", inkTopOffset: 0, inkBottomOffset: 0)
        }

        // Stroke anchors from the B's real ink bounds. CoreText boxes are
        // y-up relative to the baseline; the draw center sits lineHeight/2
        // above the glyph's top edge with the baseline `ascender` below that
        // edge, so both offsets convert into center-relative y-down points.
        var bChar: [UniChar] = [0x42] // "B"
        var bGlyph: [CGGlyph] = [0]
        CTFontGetGlyphsForCharacters(ct, &bChar, &bGlyph, 1)
        let box = CTFontGetBoundingRectsForGlyphs(ct, .default, &bGlyph, nil, 1)
        let baselineFromCenter = font.ascender - font.lineHeight / 2
        return AsciiFieldPeakGlyph(
            isNative: false,
            glyph: "B",
            inkTopOffset: baselineFromCenter - box.maxY,
            inkBottomOffset: baselineFromCenter - box.minY
        )
    }
}

// MARK: - Renderer

/// The Canvas renderer. Mounted once at the onboarding root (never per
/// stage): Welcome and Restore Wallet are adjacent steps, and a per-stage
/// mount would restart or re-fade the terrain on that swap — hoisted, the
/// terrain keeps drifting and only the text above it changes, one continuous
/// space. The parent drives visibility with opacity only.
struct AsciiFieldView: View {
    /// Freezes the renderer at a chosen moment — deterministic goldens and
    /// the evidence strips. In post-`speed` time units, like the web's prop.
    var staticTime: Double?
    /// The onboarding-side gate inputs: current step shows the field, and no
    /// concept sheet is presented over it.
    var active: Bool = true
    /// Test/preview hook so the synthesized-₿ path can be exercised on a
    /// platform whose mono face carries a native ₿.
    var forceSynthesizedPeak: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Wall-clock zero. Time is always derived from `CACurrentMediaTime()` —
    /// never a frame counter — so a pause/resume never rewinds or replays;
    /// the terrain simply is where the clock says it is.
    @State private var startTime = CACurrentMediaTime()
    /// Set while the clock is stopped so repaints (theme change, resize)
    /// reuse the frozen moment instead of silently drifting.
    @State private var frozenT: Double?
    @State private var cache = RenderCache()

    /// The single decision point for every play/pause input, mirroring the
    /// web's `sync()`: Reduce Motion / Low Power / `staticTime` paint one
    /// still frame; backgrounding, leaving the step pair, and the concept
    /// sheet stop the clockwork.
    private var clockRuns: Bool {
        staticTime == nil
            && !reduceMotion
            && !lowPower
            && active
            && scenePhase == .active
    }

    private func currentT() -> Double {
        (CACurrentMediaTime() - startTime) * AsciiFieldTerrain.speed
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !clockRuns)) { _ in
            Canvas { context, size in
                draw(in: &context, size: size, t: staticTime ?? frozenT ?? currentT())
            }
        }
        .onAppear { if !clockRuns { frozenT = currentT() } }
        .onChange(of: clockRuns) { _, runs in
            frozenT = runs ? nil : currentT()
        }
        // The power-state notification arrives off the main thread.
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        // Decoration only — never reaches VoiceOver, never intercepts touches.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: Frame

    private func draw(in context: inout GraphicsContext, size: CGSize, t: Double) {
        cache.rebuildIfNeeded(
            context: context,
            scheme: colorScheme,
            forceSynthesizedPeak: forceSynthesizedPeak
        )

        let cellW = AsciiFieldTerrain.cellW
        let cellH = AsciiFieldTerrain.cellH
        let scale = AsciiFieldTerrain.terrainScale
        let cols = Int(ceil(size.width / cellW)) + 1
        let rows = Int(ceil(size.height / cellH)) + 1

        // Bucket cells by level, then draw one level at a time — the fill is
        // effectively set 5 times per frame instead of ~700. The trig is not
        // the bottleneck; unbatched draw-state changes would be. Buckets are
        // reused across frames (zero per-frame allocation once warm).
        for level in 0..<5 { cache.buckets[level].removeAll(keepingCapacity: true) }
        for row in 0..<rows {
            let sy = (Double(row) + 0.5) * scale
            let py = Double(row) * cellH + cellH / 2
            for col in 0..<cols {
                let level = AsciiFieldTerrain.pickLevel(
                    AsciiFieldTerrain.brightness((Double(col) + 0.5) * scale, sy, t)
                )
                if level < 0 { continue }
                cache.buckets[level].append(Double(col) * cellW + cellW / 2)
                cache.buckets[level].append(py)
            }
        }

        for level in 0..<5 {
            let points = cache.buckets[level]
            if points.isEmpty { continue }
            let isPeak = level >= AsciiFieldTerrain.peakLevel
            let isCurrency = level == AsciiFieldTerrain.currencyLevel
            var i = 0
            while i < points.count {
                let px = points[i]
                let py = points[i + 1]
                i += 2
                let resolved: GraphicsContext.ResolvedText
                if isCurrency {
                    resolved = cache.currency[AsciiFieldTerrain.currencyGlyphIndex(px: px, py: py)]
                } else if isPeak {
                    resolved = cache.peakText
                } else {
                    resolved = cache.base[level]
                }
                context.draw(resolved, at: CGPoint(x: px, y: py))
                if isPeak && !cache.peak.isNative {
                    drawPeakStrokes(in: &context, px: px, py: py)
                }
            }
        }
    }

    /// The synthesized ₿'s four stroke stubs: two verticals piercing the B,
    /// ±DX from center, LEN points beyond its measured ink top and bottom.
    private func drawPeakStrokes(in context: inout GraphicsContext, px: Double, py: Double) {
        let w = AsciiFieldPeakGlyph.strokeWidth
        let len = AsciiFieldPeakGlyph.strokeLength
        let dx = AsciiFieldPeakGlyph.strokeDX
        let xl = px - dx - w / 2
        let xr = px + dx - w / 2
        let topY = py + cache.peak.inkTopOffset - len
        let bottomY = py + cache.peak.inkBottomOffset
        let shading = GraphicsContext.Shading.color(cache.peakStrokeColor)
        context.fill(Path(CGRect(x: xl, y: topY, width: w, height: len)), with: shading)
        context.fill(Path(CGRect(x: xr, y: topY, width: w, height: len)), with: shading)
        context.fill(Path(CGRect(x: xl, y: bottomY, width: w, height: len)), with: shading)
        context.fill(Path(CGRect(x: xr, y: bottomY, width: w, height: len)), with: shading)
    }

    // MARK: Cache

    /// Per-scheme resolved glyphs and reusable buckets. Text is resolved once
    /// per (glyph × level) — never inside the frame loop.
    private final class RenderCache {
        var scheme: ColorScheme?
        var forceSynthesizedPeak = false
        /// Levels 0–2, one glyph each.
        var base: [GraphicsContext.ResolvedText] = []
        /// Level 3's three currency glyphs.
        var currency: [GraphicsContext.ResolvedText] = []
        var peakText: GraphicsContext.ResolvedText!
        var peak = AsciiFieldPeakGlyph.probe()
        var peakStrokeColor = Color.primary
        /// Interleaved (px, py) per level, reused every frame.
        var buckets: [[Double]] = Array(repeating: [], count: 5)

        /// The zinc ramp converted to opacities on semantic ink (the design
        /// system allows no custom colors). Deliberately asymmetric between
        /// schemes: the site mirrors its hex array, which lands on different
        /// perceived alphas against black paper vs white paper — using one
        /// column for both would flatten dark mode's peaks and overweight its
        /// dots.
        private static let ramp: [ColorScheme: [Double]] = [
            .light: [0.17, 0.37, 0.56, 0.68, 0.75],
            .dark: [0.25, 0.32, 0.44, 0.63, 0.83],
        ]

        func rebuildIfNeeded(context: GraphicsContext, scheme: ColorScheme, forceSynthesizedPeak: Bool) {
            if self.scheme == scheme && self.forceSynthesizedPeak == forceSynthesizedPeak { return }
            self.scheme = scheme
            if self.forceSynthesizedPeak != forceSynthesizedPeak {
                self.forceSynthesizedPeak = forceSynthesizedPeak
                peak = AsciiFieldPeakGlyph.probe(forceSynthesized: forceSynthesizedPeak)
            }
            let alphas = Self.ramp[scheme] ?? Self.ramp[.light]!
            let font = Font.system(size: AsciiFieldTerrain.fontSize, design: .monospaced)
            func resolve(_ glyph: String, _ level: Int) -> GraphicsContext.ResolvedText {
                context.resolve(
                    Text(verbatim: glyph)
                        .font(font)
                        .foregroundStyle(Color.primary.opacity(alphas[level]))
                )
            }
            base = AsciiFieldTerrain.levelGlyph.enumerated().map { resolve($1, $0) }
            currency = AsciiFieldTerrain.currencyGlyphs.map {
                resolve($0, AsciiFieldTerrain.currencyLevel)
            }
            peakText = resolve(peak.glyph, AsciiFieldTerrain.peakLevel)
            peakStrokeColor = Color.primary.opacity(alphas[AsciiFieldTerrain.peakLevel])
        }
    }
}

#Preview("Field — animating") {
    AsciiFieldView()
        .frame(height: 240)
}

#Preview("Field — static, synthesized ₿") {
    AsciiFieldView(staticTime: 2.5, forceSynthesizedPeak: true)
        .frame(height: 240)
}
