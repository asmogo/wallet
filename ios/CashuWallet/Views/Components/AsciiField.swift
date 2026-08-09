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

    /// The wallet's one deliberate divergence from the web terrain: more ₿.
    /// Cells in the top of the currency band are promoted to the peak glyph
    /// (roughly doubling the on-screen ₿, ≈1.6 → ≈3.2 on a phone band)
    /// without touching the $¥€ population below the boost line. `pickLevel`
    /// itself stays verbatim-web so the golden-vector fixture keeps pinning
    /// both ports; the boost is its own mirrored constant + function.
    static let peakBoostMin = 208

    /// The level the renderer draws: `pickLevel`, plus the ₿ boost.
    static func displayLevel(_ b: Int) -> Int {
        b >= peakBoostMin ? peakLevel : pickLevel(b)
    }

    // MARK: Erosion

    /// The handoff's exit dissolves the terrain by its own material rather
    /// than by geometry: the faint dotted plain thins out first, the contour
    /// ridgelines hold, and the ₿ peaks are the last glyphs standing. Nothing
    /// translates and no edge travels, so the field never reads as a slide or
    /// a wipe — it erodes, and the wallet comes up through it.
    ///
    /// Mirrored on Android and pinned by `AsciiFieldErosionTests` (same
    /// constants in both test files — if a port disagrees, fix the port).
    /// Only the handoff overlay ever passes a non-zero progress; the welcome
    /// band always renders at full strength.
    static let erosionStagger: Double = 0.13
    static let erosionWindow: Double = 0.48

    /// Opacity multiplier for `level` at erosion `e` (0 intact → 1 gone).
    /// Windows overlap, so the field thins continuously instead of clearing
    /// in five visible steps; each window is smoothstepped so no level pops.
    static func erosionAlpha(level: Int, progress e: Double) -> Double {
        let u = min(1, max(0, (e - Double(level) * erosionStagger) / erosionWindow))
        return 1 - u * u * (3 - 2 * u)
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

    /// Continuous-brightness variants for the vault morph: the terrain→vault
    /// lerp produces fractional brightness, and rounding it first would add a
    /// second platform-sensitive rounding step for no visual gain. Threshold
    /// semantics are identical to the `Int` originals.
    static func pickLevel(_ b: Double) -> Int {
        for i in stride(from: levelMin.count - 1, through: 0, by: -1) where b >= Double(levelMin[i]) {
            return i
        }
        return -1
    }

    static func displayLevel(_ b: Double) -> Int {
        b >= Double(peakBoostMin) ? peakLevel : pickLevel(b)
    }
}

// MARK: - Vault

/// The Restore Wallet screen's material: a procedural vault door rendered
/// through the same glyph ramp and thresholds as the terrain, its ink
/// modulated by the live terrain field itself — a brightness field, not an
/// image, and never a still one. Rings, spokes, and bolts are
/// distance functions; the central ₿ monogram is a tiny hand-authored stencil
/// (a shared fixture, like the warp vectors — never an asset). The step morph
/// lerps this field against the terrain per cell, so the landscape *deforms*
/// into the vault — dots condense first, ₿ bolts last — rather than
/// crossfading like a video edit.
///
/// This is the restyle brief's one sanctioned representational image (§4
/// exception): restoring is opening your vault, and the vault is built from
/// the field's own living material on a task screen — not an illustration
/// laid on top.
///
/// Mirrored on Android and pinned by `AsciiFieldVaultTests` (vectors generated
/// from the design mock's Python, pasted identically into both test files —
/// if a port disagrees, fix the port). All geometry in grid units (points
/// here, dp on Android), authored at fixed size: the vault does not scale
/// with the window, it only recenters.
enum AsciiFieldVault {
    /// Heavy outer door ring.
    static let outerRadius: Double = 146
    static let outerWidth: Double = 11
    static let outerBrightness: Double = 196
    /// Inner ring around the wheel.
    static let innerRadius: Double = 92
    static let innerWidth: Double = 9
    static let innerBrightness: Double = 168
    /// Faint dotted door face, out to just past the outer ring's center line.
    static let faceRadius: Double = 152
    static let faceBrightness: Double = 52
    /// Six wheel spokes, hub → inner ring, thinning with angular distance.
    static let spokeMinDistance: Double = 24
    static let spokeMaxDistance: Double = 96
    static let spokeBrightness: Double = 176
    static let spokeArcWidth: Double = 8
    /// Twelve rim studs between the rings — bright enough for the ₿ boost.
    static let boltRadius: Double = 121
    static let boltHalfWidth: Double = 8
    static let boltBrightness: Double = 212
    /// The monogram stencil's two ink strengths. 221, not a rounder number:
    /// at `liveGain` 0.28 the monogram shows ₿ ~83% of the time with ~8
    /// glyph trades/sec across its cells — one point lower reads $-heavy,
    /// one higher goes static (tuned against the terrain's own liveliness).
    static let stencilPeakBrightness: Double = 221
    static let stencilCurrencyBrightness: Double = 202
    /// The living ink: the vault's brightness is modulated by the *live
    /// terrain brightness at the same cell*, so the landing screen's
    /// ridgelines keep crawling through the door's structure. The terrain's
    /// motion is its contour cliffs (the mod-spacing discontinuity), which no
    /// amount of smooth noise shimmer reproduces — borrowing the terrain
    /// field wholesale is what makes the vault move exactly like welcome.
    static let liveGain: Double = 0.28
    static let livePivot: Double = 128
    /// Past this distance the field is the living ink alone, whose maximum
    /// 0.28·(255−128) = 35.6 sits under the first draw threshold — nothing
    /// ever draws, so the renderer may skip the cell outright when the morph
    /// is fully settled.
    static let extentRadius: Double = outerRadius + outerWidth

    /// The central ₿ monogram, cell-aligned to the vault center: 2 = peak
    /// ink, 1 = currency-strength ink. Hand-authored against the real cell
    /// metrics (12×14) — edit only alongside the mock render and the parity
    /// vectors.
    static let stencilCols = 9
    static let stencilRows = 11
    private static let stencilArt: [String] = [
        "....2....",
        ".222222..",
        ".2....22.",
        ".2.....2.",
        ".2....22.",
        ".222222..",
        ".2....22.",
        ".2.....2.",
        ".2....22.",
        ".222222..",
        "....2....",
    ]
    private static let stencilBoost: [[Double]] = stencilArt.map { row in
        row.map { c in
            c == "2" ? stencilPeakBrightness : (c == "1" ? stencilCurrencyBrightness : 0)
        }
    }

    private static func ringProfile(_ d: Double, _ radius: Double, _ width: Double) -> Double {
        max(0, 1 - abs(d - radius) / width)
    }

    /// Brightness at grid point (px, py) for a vault centered at
    /// (centerX, centerY). Same output domain as the terrain's brightness, so
    /// the two lerp per cell and share one glyph ramp.
    static func brightness(px: Double, py: Double, centerX: Double, centerY: Double, t: Double) -> Double {
        let dx = px - centerX
        let dy = py - centerY
        let d = (dx * dx + dy * dy).squareRoot()
        var b = 0.0
        if d < faceRadius { b = faceBrightness }
        b = max(b, outerBrightness * ringProfile(d, outerRadius, outerWidth))
        b = max(b, innerBrightness * ringProfile(d, innerRadius, innerWidth))
        // `ang + π` is never negative (atan2 ∈ [−π, π]), so truncating
        // remainder matches Python/Kotlin `%` here.
        let ang = atan2(dy, dx)
        if d > spokeMinDistance && d < spokeMaxDistance {
            let a = (ang + .pi).truncatingRemainder(dividingBy: .pi / 3)
            let arc = min(a, .pi / 3 - a) * d
            b = max(b, spokeBrightness * max(0, 1 - arc / spokeArcWidth))
        }
        let a12 = (ang + .pi).truncatingRemainder(dividingBy: .pi / 6)
        let boltD = ((d - boltRadius) * (d - boltRadius)
            + (min(a12, .pi / 6 - a12) * boltRadius) * (min(a12, .pi / 6 - a12) * boltRadius)).squareRoot()
        if boltD < boltHalfWidth { b = max(b, boltBrightness) }
        // Stencil index rounds half toward +∞ (floor(v + 0.5)) — NOT Swift's
        // `.rounded()`, which rounds half away from zero and diverges from
        // Kotlin's `Math.round` on negative half-cell boundaries. The parity
        // vectors include both boundary signs to catch exactly that.
        let col = Int((dx / AsciiFieldTerrain.cellW + 0.5).rounded(.down)) + stencilCols / 2
        let row = Int((dy / AsciiFieldTerrain.cellH + 0.5).rounded(.down)) + stencilRows / 2
        if row >= 0, row < stencilRows, col >= 0, col < stencilCols {
            b = max(b, stencilBoost[row][col])
        }
        // Same cell→noise mapping the renderer uses for the terrain itself,
        // so a warped vault sample rides the identical warped terrain sample.
        let tb = Double(AsciiFieldTerrain.brightness(
            px / AsciiFieldTerrain.cellW * AsciiFieldTerrain.terrainScale,
            py / AsciiFieldTerrain.cellH * AsciiFieldTerrain.terrainScale,
            t
        ))
        return b + liveGain * (tb - livePivot)
    }
}

// MARK: - Touch warp

/// The lens warp under a pressed finger, as pure functions mirrored on
/// Android and pinned by `AsciiFieldWarpTests` (hand-authored vectors, same
/// constants in both test files — if a port disagrees, fix the port).
///
/// All distances are in grid units (points here, dp on Android): the space
/// where a cell is 12×14, so the lens is circular on screen and both ports
/// feed the functions numerically identical inputs.
enum AsciiFieldWarp {
    /// Full-bloom lens radius: 10 columns / ~8.6 rows of the band grid.
    static let radius: Double = 120
    /// The lens materializes at this fraction of its radius and blooms to
    /// full as the envelope rises — it grows out of the touch point rather
    /// than appearing at final size.
    static let radiusBloomFloor: Double = 0.75
    /// Peak sample displacement: 3 cells ≈ 0.39 noise-x units.
    static let maxDisplacement: Double = 36
    /// Envelope durations in wall-clock seconds — not terrain `t`, which is
    /// speed-scaled and freezes with the clock.
    static let pressDuration: Double = 0.28
    static let releaseDuration: Double = 0.6
    /// easeOutBack shape parameter: ~5% overshoot (envelope peaks at
    /// 1.0529), so the lens blooms slightly past full and relaxes. Positive
    /// overshoot is safe — only a *negative* envelope would flip the lens
    /// into attraction — and the no-fold margin holds at the peak
    /// (max slope 3.079·A·k/R = 0.973 < 1).
    static let backOvershoot: Double = 1.2
    /// Swirl at full displacement, radians. The displacement direction is
    /// rotated in proportion to local strength, so terrain flows *around*
    /// the finger instead of only fleeing it — and un-twists as the release
    /// envelope decays.
    static let swirlMax: Double = 0.35
    /// Position-glide time constant: the lens eases toward the finger with
    /// `1 - exp(-dt/τ)` per frame, so a drag reads as fluid pursuit rather
    /// than per-frame teleports.
    static let followTau: Double = 0.07

    /// Lens radius at envelope `k` — the bloom.
    static func bloomedRadius(_ k: Double) -> Double {
        radius * (radiusBloomFloor + (1 - radiusBloomFloor) * min(1, k))
    }

    /// Sample displacement at distance `d` from the finger, envelope `k`.
    /// The bump `16·(s(1-s))²` is zero in value *and* slope at the touch
    /// point and at the rim, so contours never kink at the lens boundary,
    /// and its max slope stays below 1 even at the overshoot peak, so the
    /// warped sampling never folds over itself.
    static func displacement(_ d: Double, _ k: Double) -> Double {
        guard k > 0, d > 0 else { return 0 }
        let r = bloomedRadius(k)
        guard d < r else { return 0 }
        let s = d / r
        let e = s * (1 - s)
        return maxDisplacement * k * 16 * e * e
    }

    /// easeOutBack: fast rise, small overshoot, soft settle. Clamped at
    /// zero — the polynomial dips to −2e-16 at u = 0 in floating point, and
    /// even that microscopically negative envelope is the attraction flip
    /// the design forbids (the parity tests assert k ≥ 0 throughout).
    private static func backOut(_ u: Double) -> Double {
        let c = min(1, max(0, u))
        let q = c - 1
        return max(0, 1 + (backOvershoot + 1) * q * q * q + backOvershoot * q * q)
    }

    /// Ease-in from `k0` (non-zero when a finger lands mid-decay).
    static func pressEnvelope(elapsed: Double, from k0: Double) -> Double {
        k0 + (1 - k0) * backOut(elapsed / pressDuration)
    }

    /// `k0·(1-v)³` — a settle, deliberately not a spring: overshoot *here*
    /// would swing `k` negative and flip the lens into attraction.
    static func releaseEnvelope(elapsed: Double, from k0: Double) -> Double {
        let v = 1 - min(1, max(0, elapsed / releaseDuration))
        return k0 * v * v * v
    }

    /// Rotation of the displacement direction at displacement `f` —
    /// proportional to local strength, so the swirl is strongest mid-lens
    /// and vanishes at both the touch point and the rim.
    static func swirlAngle(_ f: Double) -> Double {
        swirlMax * f / maxDisplacement
    }

    /// Per-frame glide fraction for elapsed `dt` — exponential smoothing,
    /// frame-rate independent.
    static func followFactor(_ dt: Double) -> Double {
        1 - exp(-dt / followTau)
    }
}

/// Mutable finger state, read by the frame loop. Deliberately not observed
/// state: the 30fps tick already repaints, so mutations here surface on the
/// next frame without invalidating the view per touch event.
final class AsciiFieldWarpTouch {
    enum Phase { case idle, pressed, released }
    private(set) var phase: Phase = .idle
    /// Where the lens *is*, in grid units — glides toward the finger via
    /// `advance` (see `AsciiFieldWarp.followTau`).
    private(set) var x: Double = 0
    private(set) var y: Double = 0
    /// Where the finger is — the glide target.
    private var targetX: Double = 0
    private var targetY: Double = 0
    private var phaseStart: Double = 0
    private var k0: Double = 0
    private var lastAdvance: Double = 0

    func pressOrMove(at point: CGPoint, now: Double) {
        targetX = point.x
        targetY = point.y
        guard phase != .pressed else { return }
        // A landing finger snaps the lens under it — the bloom starts where
        // the touch is, never gliding in from a stale spot.
        x = targetX
        y = targetY
        lastAdvance = now
        // Ramp from the current envelope, so re-pressing mid-decay doesn't
        // snap the lens shut and reopen it from zero.
        k0 = currentK(now: now)
        phaseStart = now
        phase = .pressed
    }

    func release(now: Double) {
        guard phase == .pressed else { return }
        k0 = currentK(now: now)
        phaseStart = now
        phase = .released
    }

    func reset() {
        phase = .idle
    }

    /// Advances the position glide; call once per frame before sampling.
    /// Keeps gliding through the release settle, so a flick's lens drifts
    /// to rest at the lift point instead of freezing mid-pursuit.
    func advance(now: Double) {
        guard phase != .idle else { return }
        // Clamp dt so a hitch or pause can't turn into a teleport.
        let dt = min(0.1, max(0, now - lastAdvance))
        lastAdvance = now
        let a = AsciiFieldWarp.followFactor(dt)
        x += (targetX - x) * a
        y += (targetY - y) * a
    }

    func currentK(now: Double) -> Double {
        switch phase {
        case .idle:
            return 0
        case .pressed:
            return AsciiFieldWarp.pressEnvelope(elapsed: now - phaseStart, from: k0)
        case .released:
            let k = AsciiFieldWarp.releaseEnvelope(elapsed: now - phaseStart, from: k0)
            if k <= 0 { phase = .idle }
            return k
        }
    }
}

// MARK: - Layout

/// Field geometry as a pure function, so the layout-invariant test can assert
/// it without composing views.
///
/// The drawn layer always spans the full window, on both steps of the pair:
/// glyph positions (and the currency hash keyed on them) are a function of
/// layer size, so a layer that resized between steps would make the whole
/// texture swim and re-hash mid-transition. What differs per step is the
/// field's *material* — welcome's tall terrain vs Restore Wallet's vault door
/// (see `AsciiFieldVault`) — plus the mask's opaque ramp, which shortens from
/// the long welcome fade to end at the vault's top edge; both ride a single
/// 0…1 morph on the step transaction. The clear line behind the header never
/// moves, and the glyph grid never moves and never re-hashes. (Band mode —
/// extent 0 — survives as pure math and its tests; no step rests on it
/// anymore.)
///
/// The field terminates through its mask, not through occlusion: the bottom
/// fade begins above the chassis edge and settles onto a faint floor a little
/// past it, so the terrain dissolves toward the buttons — with a sliver
/// continuing behind their glass — instead of ending on a hard cut.
enum AsciiFieldLayout {
    /// Web is `clamp(180px, 26vh, 320px)`; scaled slightly for phone-sized
    /// viewports.
    static let minBand: CGFloat = 160
    static let maxBand: CGFloat = 300
    static let bandFraction: CGFloat = 0.26
    /// Below this the band would be a squashed few-row smear behind
    /// accessibility-size copy (or a landscape phone) — draw nothing instead.
    static let suppressionThreshold: CGFloat = 120
    /// Band mode ramps transparent → opaque over this fraction of the visible
    /// band (the web masks the top 30% of its fully-visible band; ours also
    /// extends under the chassis, so the fraction applies to the visible part).
    static let maskFade: CGFloat = 0.30
    /// Full mode's ramp length as a fraction of the *window* — the same 0.30
    /// family as `maskFade` and the handoff's `sweepEdge`, stretched over the
    /// taller extent so the field materializes gradually below the header
    /// instead of arriving on a visible line.
    static let fullFade: CGFloat = 0.30
    /// The bottom fade starts this far above the chassis edge…
    static let bottomFadeReach: CGFloat = 48
    /// …and settles onto the floor opacity this far past it, so the dimming
    /// is complete by the time the terrain passes behind the buttons.
    static let bottomFadeUnderlap: CGFloat = 40
    /// The fade lands on this opacity — not zero — and holds it to the very
    /// bottom of the window: the terrain runs subtly behind the chassis
    /// buttons and the home indicator instead of cutting out above them.
    static let bottomFloorAlpha: CGFloat = 0.25

    struct Resolution: Equatable {
        /// Height of the band above the chassis — what Restore Wallet shows.
        var visibleBand: CGFloat
        /// Full layer height — always the window height, on both steps.
        var layerHeight: CGFloat
        /// Band mode (extent 0), as fractions of layerHeight: fully clear
        /// above `bandClearEnd`, ramping to fully opaque at `bandOpaqueEnd`.
        /// Geometrically today's band mask expressed in window coordinates.
        var bandClearEnd: CGFloat
        var bandOpaqueEnd: CGFloat
        /// Full mode (extent 1): clear behind the whole header block — the
        /// boundary sits at the header-clearance line — then the long ramp.
        var fullClearEnd: CGFloat
        var fullOpaqueEnd: CGFloat
        /// The bottom fade never moves with extent — above the chassis edge,
        /// so the dissolve is already underway when the terrain meets the
        /// buttons…
        var bottomFadeStart: CGFloat
        /// …completing slightly past the chassis edge, behind the buttons.
        var bottomFadeEnd: CGFloat
        /// Vault mode (Restore Wallet): the ramp completes by the vault's top
        /// edge so nothing of the door is dimmed — a shorter ramp than full
        /// mode's, same clear line behind the header.
        var vaultOpaqueEnd: CGFloat
        /// The vault's center, points from the layer top: the middle of the
        /// empty region between the header block and the chassis.
        var vaultCenterY: CGFloat

        /// The two extent-dependent stops, lerped. Clamped because the
        /// Animatable driver can overshoot transiently on a bouncy curve.
        func maskStops(extent: CGFloat) -> (clearEnd: CGFloat, opaqueEnd: CGFloat) {
            let e = min(max(extent, 0), 1)
            return (
                clearEnd: bandClearEnd + (fullClearEnd - bandClearEnd) * e,
                opaqueEnd: bandOpaqueEnd + (fullOpaqueEnd - bandOpaqueEnd) * e
            )
        }

        /// The stops the live pair actually renders: full mode (welcome's
        /// tall terrain) lerped toward vault mode by the morph. The clear
        /// line never moves — both modes are transparent through the header
        /// block — so the cull is constant across the whole morph.
        func morphedMaskStops(vaultMix: CGFloat) -> (clearEnd: CGFloat, opaqueEnd: CGFloat) {
            let m = min(max(vaultMix, 0), 1)
            let full = maskStops(extent: 1)
            return (
                clearEnd: full.clearEnd,
                opaqueEnd: full.opaqueEnd + (vaultOpaqueEnd - full.opaqueEnd) * m
            )
        }

        /// Points from the layer top to the current fully-transparent
        /// boundary — everything above it is masked to nothing and cullable.
        func transparentStart(extent: CGFloat) -> CGFloat {
            maskStops(extent: extent).clearEnd * layerHeight
        }
    }

    /// `headerClearance` is the vertical room the pair's tallest header
    /// (welcome's two-line title + subhead, at the live Dynamic Type size)
    /// needs. Using the same clearance for both steps of the pair keeps the
    /// resolved geometry identical across them — the layout-invariant
    /// contract, now carried by the constant full-window layer.
    static func resolve(
        windowHeight: CGFloat,
        topInset: CGFloat,
        chassisInset: CGFloat,
        headerClearance: CGFloat
    ) -> Resolution? {
        let band = min(max(minBand, bandFraction * windowHeight), maxBand)
        // The empty region between the header block and the chassis. When the
        // heavy largeTitle wraps at accessibility sizes (or the window is a
        // landscape phone), this collapses and the field is suppressed rather
        // than squashed — the band never shrinks to fit.
        let available = windowHeight - topInset - headerClearance - chassisInset
        guard min(band, available) >= suppressionThreshold else { return nil }
        return resolution(
            band: band, windowHeight: windowHeight,
            topInset: topInset, chassisInset: chassisInset,
            headerClearance: headerClearance
        )
    }

    /// The suppressed case still needs a stable frame (the view hides rather
    /// than unmounts, to keep its wall clock), so it lays out the floor band
    /// against the same full-window layer.
    static func fallback(
        windowHeight: CGFloat,
        topInset: CGFloat,
        chassisInset: CGFloat,
        headerClearance: CGFloat
    ) -> Resolution {
        resolution(
            band: minBand, windowHeight: windowHeight,
            topInset: topInset, chassisInset: chassisInset,
            headerClearance: headerClearance
        )
    }

    private static func resolution(
        band: CGFloat,
        windowHeight: CGFloat,
        topInset: CGFloat,
        chassisInset: CGFloat,
        headerClearance: CGFloat
    ) -> Resolution {
        // A transient zero-size layout pass must not divide by zero; the
        // degenerate frame is invisible (suppressed → opacity 0) either way.
        let height = max(windowHeight, band + chassisInset)
        let bandTop = height - chassisInset - band
        let bandClearEnd = bandTop / height
        let bandOpaqueEnd = (bandTop + maskFade * band) / height
        // Both full-mode stops clamp against their band counterparts: in a
        // cramped-but-not-suppressed window the header block can reach below
        // the band top, and full mode must degrade to band mode — the settle
        // becomes a no-op rather than inverting direction.
        let fullClearEnd = min((topInset + headerClearance) / height, bandClearEnd)
        let fullOpaqueEnd = min(fullClearEnd + fullFade, bandOpaqueEnd)
        // The vault floats in the middle of the free region. Its mask ramp
        // must be done by the door's top edge; on cramped windows the door
        // reaches the header clearance line and the ramp degrades to a hard
        // edge there rather than dimming the ring.
        let vaultCenterY = (topInset + headerClearance + height - chassisInset) / 2
        let vaultTop = (vaultCenterY - CGFloat(AsciiFieldVault.extentRadius)) / height
        return Resolution(
            visibleBand: band,
            layerHeight: height,
            bandClearEnd: bandClearEnd,
            bandOpaqueEnd: bandOpaqueEnd,
            fullClearEnd: fullClearEnd,
            fullOpaqueEnd: fullOpaqueEnd,
            bottomFadeStart: (height - chassisInset - bottomFadeReach) / height,
            bottomFadeEnd: (height - chassisInset + min(bottomFadeUnderlap, chassisInset)) / height,
            vaultOpaqueEnd: max(fullClearEnd, min(vaultTop, fullOpaqueEnd)),
            vaultCenterY: vaultCenterY
        )
    }

    /// First grid row worth evaluating under a mask whose fully-transparent
    /// region ends `transparentStart` points from the layer top. One row of
    /// slack for glyph ink overhanging its cell; everything above multiplies
    /// to zero through the mask anyway, so culling is purely a cost move —
    /// it changes which rows are computed, never where anything draws.
    static func cullStartRow(transparentStart: CGFloat) -> Int {
        max(0, Int((Double(transparentStart) / AsciiFieldTerrain.cellH).rounded(.down)) - 1)
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

/// SwiftUI cannot interpolate gradient stops (nor lerp the renderer's
/// brightness fields), so the Welcome ↔ Restore morph drives this Animatable
/// wrapper instead (the handoff's `ErosionDriver` pattern): the step
/// transaction animates `vaultMix`, and the content closure re-renders with
/// each interpolated value to rebuild the mask and the terrain→vault lerp.
struct AsciiFieldMorphDriver<Content: View>: View, Animatable {
    var vaultMix: CGFloat
    @ViewBuilder var content: (CGFloat) -> Content

    var animatableData: CGFloat {
        get { vaultMix }
        set { vaultMix = newValue }
    }

    var body: some View {
        content(vaultMix)
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
/// space. The parent drives visibility with opacity and shapes the visible
/// extent with its mask; the renderer's own frame never changes.
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
    /// Externally driven lens (the onboarding handoff's programmatic center
    /// bloom). When set, the field never listens to fingers — the owner is
    /// the only one pressing. Warp math and constants are untouched.
    var touchOverride: AsciiFieldWarpTouch? = nil
    /// The handoff's exit dissolve, 0 (intact) → 1 (gone). At 0 the draw is
    /// byte-identical to what it always was — the welcome band never sets it.
    var erosion: Double = 0
    /// Points from the layer top that are fully transparent under the owner's
    /// mask — rows above are skipped rather than computed-then-erased. The
    /// onboarding layer passes its mask's current transparent start; the
    /// handoff curtain leaves the default and draws every row.
    var topCull: CGFloat = 0
    /// The Welcome ↔ Restore morph, 0 (terrain) → 1 (vault): each cell's
    /// brightness lerps between the two fields, so the landscape deforms into
    /// the vault through the shared glyph ramp. At 0 the draw is
    /// byte-identical to the pure terrain — the handoff curtain and the
    /// welcome step never set it.
    var vaultMix: Double = 0
    /// The vault's center, points from the layer top (the layout's
    /// `vaultCenterY`); x is always the layer's midline.
    var vaultCenterY: Double = 0

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
    /// Stable reference; touch events mutate it without invalidating the view
    /// (the 30fps tick picks the changes up).
    @State private var touch = AsciiFieldWarpTouch()
    /// The lens the frame loop reads: the injected instance when present,
    /// else the finger-driven one.
    private var activeTouch: AsciiFieldWarpTouch { touchOverride ?? touch }
    /// Release detection: `@GestureState` resets even when the system
    /// *cancels* the drag — `.onEnded` doesn't fire then, and a missed
    /// release would pin the lens open.
    @GestureState private var touchDown = false

    /// The single decision point for every play/pause input, mirroring the
    /// web's `sync()`: Reduce Motion / Low Power / `staticTime` / UI tests
    /// paint one still frame; backgrounding, leaving the step pair, and the
    /// concept sheet stop the clockwork.
    ///
    /// UI tests belong on that list because this is a `TimelineView(.animation)`
    /// — a redraw every frame, forever, for as long as the step is on screen.
    /// XCUITest waits for the app to go idle before each interaction, so a
    /// clock that never stops means every tap on welcome and restoreMethod
    /// pays the full idle timeout. `UITEST_DISABLE_ANIMATIONS` was already
    /// being set by the harness for exactly this reason; nothing had read it.
    private var clockRuns: Bool {
        staticTime == nil
            && !reduceMotion
            && !lowPower
            && !IntegrationTestConfig.shouldDisableAnimations
            && active
            && scenePhase == .active
    }

    private func currentT() -> Double {
        (CACurrentMediaTime() - startTime) * AsciiFieldTerrain.speed
    }

    var body: some View {
        // 60fps while a finger is down — the lens pursuit reads steppy at
        // the ambient 30. `touchDown` is @GestureState, so the interval
        // change re-evaluates for free; the release settle runs at the
        // ambient rate (nothing tracks the finger anymore).
        TimelineView(.animation(minimumInterval: touchDown ? 1.0 / 60.0 : 1.0 / 30.0, paused: !clockRuns)) { _ in
            Canvas { context, size in
                draw(in: &context, size: size, t: staticTime ?? frozenT ?? currentT())
            }
        }
        .onAppear { if !clockRuns { frozenT = currentT() } }
        .onChange(of: clockRuns) { _, runs in
            frozenT = runs ? nil : currentT()
            // Never carry a stale lens across a pause — a resume must not
            // replay a half-finished decay.
            activeTouch.reset()
        }
        // The power-state notification arrives off the main thread.
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        // Decoration for VoiceOver always. Touch is the one exception: the
        // finger warps the terrain (lens warp), so the band accepts drags —
        // but only while the clock runs. The decay needs the frame loop to
        // render, Reduce Motion users shouldn't get a motion effect, and
        // Low Power / static evidence must stay inert. As the stage's
        // `.background` the band only receives touches that fell through the
        // foreground — buttons, banners, and the chassis still win.
        .accessibilityHidden(true)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($touchDown) { _, state, _ in state = true }
                .onChanged { touch.pressOrMove(at: $0.location, now: CACurrentMediaTime()) }
        )
        .onChange(of: touchDown) { _, down in
            if !down { touch.release(now: CACurrentMediaTime()) }
        }
        .allowsHitTesting(clockRuns && touchOverride == nil)
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

        // The lens envelope and position glide, advanced once per frame.
        // Zero envelope short-circuits every warp branch below, so an
        // untouched frame samples through the exact expressions it always
        // has — byte-identical stills.
        let now = CACurrentMediaTime()
        let touch = activeTouch
        touch.advance(now: now)
        let k = touch.currentK(now: now)
        let tx = touch.x
        let ty = touch.y

        // Bucket cells by level, then draw one level at a time — the fill is
        // effectively set 5 times per frame instead of ~700. The trig is not
        // the bottleneck; unbatched draw-state changes would be. Buckets are
        // reused across frames (zero per-frame allocation once warm).
        let startRow = min(rows, AsciiFieldLayout.cullStartRow(transparentStart: topCull))
        let vaultCenterX = Double(size.width) / 2
        let vaultReachSquared = AsciiFieldVault.extentRadius * AsciiFieldVault.extentRadius
        for level in 0..<5 { cache.buckets[level].removeAll(keepingCapacity: true) }
        for row in startRow..<rows {
            let sy = (Double(row) + 0.5) * scale
            let py = Double(row) * cellH + cellH / 2
            for col in 0..<cols {
                let px = Double(col) * cellW + cellW / 2
                var sampleX = (Double(col) + 0.5) * scale
                var sampleY = sy
                // The vault samples in grid points; the warp displaces its
                // sampling exactly as it displaces the terrain's.
                var warpedPx = px
                var warpedPy = py
                if k > 0 {
                    // Samples are displaced *toward* the finger: the inverse
                    // mapping moves the visible terrain away from it — a
                    // clearing with a compressed contour ring at the rim.
                    // Displacing away would read as a magnifier pulling
                    // contours in. The direction is rotated by the swirl, so
                    // the terrain flows around the finger as it flees. Only
                    // sampling warps; glyph positions (and the currency hash
                    // keyed on them) never move.
                    let dx = px - tx
                    let dy = py - ty
                    let d = (dx * dx + dy * dy).squareRoot()
                    let f = AsciiFieldWarp.displacement(d, k)
                    if f > 0 {
                        let theta = AsciiFieldWarp.swirlAngle(f)
                        let cosT = cos(theta)
                        let sinT = sin(theta)
                        let inv = f / d
                        warpedPx = px - (dx * cosT - dy * sinT) * inv
                        warpedPy = py - (dx * sinT + dy * cosT) * inv
                        sampleX = warpedPx / cellW * scale
                        sampleY = warpedPy / cellH * scale
                    }
                }
                let level: Int
                if vaultMix <= 0 {
                    level = AsciiFieldTerrain.displayLevel(
                        AsciiFieldTerrain.brightness(sampleX, sampleY, t)
                    )
                } else if vaultMix >= 1 {
                    // Settled vault: outside its reach the field is the
                    // living ink alone — always below the first threshold —
                    // so the cell is skipped before any trig runs. Restore's
                    // steady state costs roughly the door's bounding circle.
                    let dx = warpedPx - vaultCenterX
                    let dy = warpedPy - vaultCenterY
                    if dx * dx + dy * dy > vaultReachSquared { continue }
                    level = AsciiFieldTerrain.displayLevel(
                        AsciiFieldVault.brightness(
                            px: warpedPx, py: warpedPy,
                            centerX: vaultCenterX, centerY: vaultCenterY, t: t
                        )
                    )
                } else {
                    // Mid-morph: one brightness field lerping into the other,
                    // per cell — the glyphs never crossfade, the landscape
                    // deforms.
                    let terrain = Double(AsciiFieldTerrain.brightness(sampleX, sampleY, t))
                    let vault = AsciiFieldVault.brightness(
                        px: warpedPx, py: warpedPy,
                        centerX: vaultCenterX, centerY: vaultCenterY, t: t
                    )
                    level = AsciiFieldTerrain.displayLevel(terrain + (vault - terrain) * vaultMix)
                }
                if level < 0 { continue }
                cache.buckets[level].append(px)
                cache.buckets[level].append(py)
            }
        }

        for level in 0..<5 {
            let points = cache.buckets[level]
            if points.isEmpty { continue }
            // Per-level opacity is one draw-state change per bucket — the
            // batching that makes the field cheap is exactly what lets it
            // erode by material.
            var context = context
            if erosion > 0 {
                let alpha = AsciiFieldTerrain.erosionAlpha(level: level, progress: erosion)
                if alpha <= 0 { continue }
                context.opacity = alpha
            }
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
