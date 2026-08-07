import SwiftUI

/// A typographic role.
///
/// A role carries font, face, weight, tracking, casing, line limit and numeric
/// treatment **as one value**. That is the entire point: the drift this layer
/// exists to end came from those travelling separately, so that a call site
/// could take the size and forget the tracking, or take the tabular figures and
/// forget the digit transition. Here they cannot be separated.
struct CashuTextRole: Equatable {

    enum Size: Equatable {
        /// A named text style. Dynamic Type and the system's optical size
        /// curve both come for free.
        case style(Font.TextStyle)
        /// A display numeral at a fixed base size, scaled against `anchor` and
        /// clamped at `cap`.
        case hero(base: CGFloat, anchor: Font.TextStyle, cap: CGFloat)
    }

    var size: Size
    var face: CashuFonts.Face = .sans
    var weight: Font.Weight = .regular
    /// Selects this role's entry in the family's tracking table.
    var trackingKey: KeyPath<CashuTracking, CGFloat> = \.body
    /// Tabular figures **and** the numeric digit transition, together.
    var isNumeric: Bool = false
    var uppercase: Bool = false
    var lineLimit: Int? = nil
    var minimumScaleFactor: CGFloat = 1

    func pointSize(at typeSize: DynamicTypeSize) -> CGFloat {
        switch size {
        case .style(let style):
            CashuTypeScale.pointSize(style, at: typeSize)
        case .hero(let base, let anchor, let cap):
            CashuTypeScale.scaled(base, relativeTo: anchor, at: typeSize, cap: cap)
        }
    }

    /// The line box this role occupies at the current text size.
    ///
    /// Containers that must reserve space for a hero use this instead of a
    /// constant, which is what keeps the reservation stable within a text size
    /// (so a unit swap never reflows) while still growing with it (so large
    /// text is never cropped).
    func lineHeight(at typeSize: DynamicTypeSize, fonts: CashuFonts) -> CGFloat {
        switch size {
        case .style(let style):
            ceil(CashuTypeScale.lineHeight(style, at: typeSize))
        case .hero:
            ceil(CashuTypeScale.lineHeight(
                forPointSize: pointSize(at: typeSize),
                weight: weight,
                face: face,
                fonts: fonts
            ))
        }
    }

    func font(at typeSize: DynamicTypeSize, fonts: CashuFonts) -> Font {
        resolvedFont(pointSize: pointSize(at: typeSize), fonts: fonts)
    }

    func resolvedFont(pointSize: CGFloat, fonts: CashuFonts) -> Font {
        let base: Font = switch size {
        case .style(let style):
            .system(style, design: face == .mono ? .monospaced : .default, weight: weight)
        case .hero:
            fonts.font(face, size: pointSize, weight: weight)
        }
        return isNumeric ? base.monospacedDigit() : base
    }
}

// MARK: - The vocabulary
//
// Adding a role means updating `TypographyGuardTests.roleInventory`. Growing
// the vocabulary should be a deliberate, reviewed act — an unbounded set of
// roles is just the old drift wearing a nicer API.

extension CashuTextRole {

    // MARK: Money
    //
    // Four sizes, and no others. Amounts are typed by role, never by point
    // size: six sizes serving this one role is how the balance and the amount
    // being typed one screen later ended up in two different typefaces.
    //
    // No `design: .rounded` anywhere. The balance and the entry hero are the
    // same object and now say so.

    /// 52 rather than 56, matching Android. The ladder was re-based once Geist
    /// went in there and proved ~7% wider than Roboto; holding both platforms
    /// to one number is worth more than 4pt on iOS, where SF Pro would have
    /// carried either.
    static let amountHero = CashuTextRole(
        size: .hero(base: 52, anchor: .largeTitle, cap: 70),
        weight: .semibold,
        trackingKey: \.amountHero,
        isNumeric: true,
        lineLimit: 1,
        minimumScaleFactor: 0.5
    )

    static let amountConfirm = CashuTextRole(
        size: .hero(base: 40, anchor: .title, cap: 56),
        weight: .semibold,
        trackingKey: \.amountConfirm,
        isNumeric: true,
        lineLimit: 1,
        minimumScaleFactor: 0.5
    )

    static let amountCompact = CashuTextRole(
        size: .hero(base: 28, anchor: .title2, cap: 40),
        weight: .semibold,
        trackingKey: \.amountCompact,
        isNumeric: true,
        lineLimit: 1,
        minimumScaleFactor: 0.5
    )

    /// No autoscale, deliberately — the one rung of the ladder that sets it to 1.
    ///
    /// `minimumScaleFactor` collides with `.numericText`: mid-transition the
    /// numeric renderer reports a tiny intermediate width, and the scale factor
    /// then shrinks even short amounts toward its floor. The two amount columns
    /// found this independently and each dropped autoscale in a comment rather
    /// than in the type system, which is precisely the drift this layer exists
    /// to end. Row amounts use compact grouped formatting and always fit, so
    /// autoscale buys nothing here and costs a visible mis-scale.
    ///
    /// The hero rungs keep theirs: a typed amount is genuinely unbounded, and on
    /// the focal element of the screen a clipped number is worse than a
    /// momentary mis-scale.
    static let amountRow = CashuTextRole(
        size: .style(.body),
        weight: .medium,
        trackingKey: \.amountRow,
        isNumeric: true,
        lineLimit: 1,
        minimumScaleFactor: 1
    )

    /// Keypad digits — same family and the same tabular treatment as the number
    /// they produce, so key labels don't shift width as digits change.
    static let numberPadKey = CashuTextRole(size: .style(.title), isNumeric: true)

    // MARK: Structure

    /// The onboarding step title. Every step wears it, welcome included, which
    /// is what puts them all on one line — so it is one role, not a font stack
    /// each header repeats. Heavy rather than bold, and the only named style
    /// carrying a tracking delta; see `CashuTracking.onboardingTitle`.
    static let onboardingTitle = CashuTextRole(
        size: .style(.largeTitle),
        weight: .heavy,
        trackingKey: \.onboardingTitle
    )

    static let title = CashuTextRole(size: .style(.title), weight: .semibold)
    static let title3 = CashuTextRole(size: .style(.title3), weight: .medium)
    static let bodyEmphasis = CashuTextRole(size: .style(.body), weight: .semibold)
    static let body = CashuTextRole(size: .style(.body))
    static let callout = CashuTextRole(size: .style(.callout))
    static let textLink = CashuTextRole(size: .style(.subheadline), weight: .medium)

    /// Timestamps and secondary row text. One step up from the 12pt floor:
    /// metadata is already demoted by secondary ink, and stacking 12pt on top
    /// of that is a double demotion that pushes it under the legibility line.
    static let metadata = CashuTextRole(size: .style(.footnote))

    /// Genuinely incidental chrome only. If it names a thing the user needs to
    /// read, it belongs in `metadata`.
    static let caption = CashuTextRole(size: .style(.caption))

    /// The one overline. Casing is applied here so no call site has to
    /// remember; tracking is the documented 0.06em, resolved against the live
    /// point size rather than frozen at 12pt.
    static let overline = CashuTextRole(
        size: .style(.caption),
        weight: .semibold,
        trackingKey: \.overline,
        uppercase: true
    )

    // MARK: Technical strings

    static let monoBody = CashuTextRole(
        size: .style(.subheadline), face: .mono, trackingKey: \.mono
    )
    static let monoCaption = CashuTextRole(
        size: .style(.caption2), face: .mono, trackingKey: \.mono
    )
}

// MARK: - Application

private struct CashuTextModifier: ViewModifier {
    let role: CashuTextRole
    let numericValue: Double?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.cashuFonts) private var fonts

    func body(content: Content) -> some View {
        let pointSize = role.pointSize(at: typeSize)
        return content
            .font(role.resolvedFont(pointSize: pointSize, fonts: fonts))
            // em → points at the *live* size, so tracking scales with the text.
            .tracking(fonts.tracking[keyPath: role.trackingKey] * pointSize)
            .textCase(role.uppercase ? .uppercase : nil)
            .lineLimit(role.lineLimit)
            .minimumScaleFactor(role.minimumScaleFactor)
            .modifier(NumericTransitionModifier(value: role.isNumeric ? numericValue : nil))
    }
}

/// The digit transition, applied only where a role is numeric and a value was
/// supplied. Pairing it with the animation here is what closes the gap between
/// the amounts that roll and the amounts that jump — DESIGN.md calls both
/// halves of the Tabular Figure Rule non-negotiable, but 22 money values were
/// getting the figures without the transition.
private struct NumericTransitionModifier: ViewModifier {
    let value: Double?

    func body(content: Content) -> some View {
        if let value {
            content
                .contentTransition(.numericText(value: value))
                .animation(.snappy, value: value)
        } else {
            content
        }
    }
}

extension View {
    /// Non-money text.
    func cashuText(_ role: CashuTextRole) -> some View {
        modifier(CashuTextModifier(role: role, numericValue: nil))
    }

    /// Money. Pass the underlying numeric value so the digits roll on change.
    func cashuAmount(_ role: CashuTextRole, value: Double?) -> some View {
        modifier(CashuTextModifier(role: role, numericValue: value))
    }
}
