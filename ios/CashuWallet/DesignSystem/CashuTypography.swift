import SwiftUI
import UIKit

// MARK: - Family

/// The single point of indirection for the app's typefaces.
///
/// iOS resolves to the system faces permanently. DESIGN.md §7 forbids a bundled
/// face here, and the reason is worth recording: SF Symbols are drawn to SF
/// Pro's cap height and weight axis, so pairing them with any other family
/// desynchronises icon-and-label alignment on every `Label`, every settings
/// row, and the tab bar. On top of that, alerts, action sheets, the share sheet
/// and the keyboard render in SF Pro no matter what the app asks for, so a
/// bundled body face would leave the app permanently mixed-face.
///
/// The indirection exists anyway, because a family owns more than a name: it
/// owns the cap-height metric the amount lockup aligns against and the per-role
/// tracking table. Both are properties of the face, not of the role.
struct CashuFonts {
    enum Face { case sans, mono }

    /// Per-role tracking in **em**.
    let tracking: CashuTracking

    static let system = CashuFonts(tracking: .sfPro)

    func font(_ face: Face, size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: face == .mono ? .monospaced : .default)
    }

    func uiFont(_ face: Face, size: CGFloat, weight: Font.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        guard face == .mono else { return base }
        return UIFont.monospacedSystemFont(ofSize: size, weight: weight.uiWeight)
    }

    /// Cap height in points. The amount lockup sits a unit on the value's cap
    /// line rather than its baseline, so the two read as one object.
    func capHeight(_ face: Face, size: CGFloat, weight: Font.Weight) -> CGFloat {
        uiFont(face, size: size, weight: weight).capHeight
    }
}

// MARK: - Symbol sizes

/// Sanctioned SF Symbol sizes — glyph sizing, not text, which is why it lives
/// in the design layer rather than tripping the hardcoded-point-size ratchet
/// at five call sites.
extension Font {
    /// The status glyph on success/failure faces (payment settled, key
    /// imported, transaction detail). One size, so every outcome face carries
    /// the same visual weight.
    static let statusGlyph = Font.system(size: 64)
}

/// Per-role tracking, in **em**.
///
/// Em rather than points, deliberately. The five copy-pasted `.tracking(1.2)`
/// overlines are 0.1em frozen at 12pt: correct at exactly one text size and
/// wrong at every other, because a point value cannot scale. Expressing
/// tracking as a fraction of the em and resolving it against the live point
/// size fixes that by construction.
///
/// SF Pro applies its own optical tracking curve per text style, so these are
/// *deltas* on top of that and are mostly zero. The display numerals — which
/// run at fixed sizes rather than named styles, and so sit outside the system's
/// curve — the overline, and the onboarding title carry real values.
struct CashuTracking {
    var amountHero: CGFloat = 0
    var amountConfirm: CGFloat = 0
    var amountCompact: CGFloat = 0
    var amountRow: CGFloat = 0
    var overline: CGFloat = 0
    var onboardingTitle: CGFloat = 0
    var mono: CGFloat = 0
    var body: CGFloat = 0

    static let sfPro = CashuTracking(
        amountHero: -0.015,
        amountConfirm: -0.010,
        amountCompact: -0.005,
        amountRow: 0,
        // The documented value. 0.06em is 0.72pt at 12pt — half of what five of
        // the six hand-rolled section headers currently apply.
        overline: 0.060,
        // The one named style that carries a delta. SF Pro's curve is drawn for
        // the regular/semibold end of the range; at `.heavy` a largeTitle sets
        // visibly loose, which is why the onboarding headers were hand-rolling
        // `.tracking(-0.5)`. Same value, expressed so it scales: -0.015em is
        // -0.5pt at largeTitle's 34pt.
        onboardingTitle: -0.015,
        mono: 0,
        body: 0
    )
}

private struct CashuFontsKey: EnvironmentKey {
    static let defaultValue = CashuFonts.system
}

extension EnvironmentValues {
    var cashuFonts: CashuFonts {
        get { self[CashuFontsKey.self] }
        set { self[CashuFontsKey.self] = newValue }
    }
}

// MARK: - Dynamic Type resolution

/// Deterministic Dynamic Type maths.
///
/// Everything here is a pure function of a `DynamicTypeSize`, which matters for
/// two reasons. `@ScaledMetric` cannot be read from a computed property, and the
/// hero containers must reserve a height derived from the *same* scale as the
/// text inside them — that is the whole no-reflow fix. It also goes stale when
/// its base value is itself dynamic. `UIFontMetrics` performs the identical
/// calculation while staying callable from anywhere and honouring a
/// `.dynamicTypeSize(...)` override in previews and tests.
enum CashuTypeScale {

    static func traits(_ size: DynamicTypeSize) -> UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: size.contentSizeCategory)
    }

    /// Resolved point size of a named text style.
    static func pointSize(_ style: Font.TextStyle, at size: DynamicTypeSize) -> CGFloat {
        UIFont.preferredFont(forTextStyle: style.uiStyle, compatibleWith: traits(size)).pointSize
    }

    /// Full line box of a named text style — ascender, descender and leading.
    static func lineHeight(_ style: Font.TextStyle, at size: DynamicTypeSize) -> CGFloat {
        UIFont.preferredFont(forTextStyle: style.uiStyle, compatibleWith: traits(size)).lineHeight
    }

    /// Hero numerals: scale a fixed base against an anchor style, then clamp.
    ///
    /// The clamp is what lets a reserved-height hero survive AX5 without
    /// reintroducing reflow. Without it the balance would grow without bound and
    /// push the wallet's actions off screen.
    static func scaled(
        _ base: CGFloat,
        relativeTo anchor: Font.TextStyle,
        at size: DynamicTypeSize,
        cap: CGFloat
    ) -> CGFloat {
        min(
            UIFontMetrics(forTextStyle: anchor.uiStyle)
                .scaledValue(for: base, compatibleWith: traits(size)),
            cap
        )
    }

    /// Line box for an explicitly sized font.
    static func lineHeight(
        forPointSize pt: CGFloat,
        weight: Font.Weight,
        face: CashuFonts.Face,
        fonts: CashuFonts
    ) -> CGFloat {
        fonts.uiFont(face, size: pt, weight: weight).lineHeight
    }
}

// MARK: - Bridges

extension Font.TextStyle {
    var uiStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}

extension Font.Weight {
    var uiWeight: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
