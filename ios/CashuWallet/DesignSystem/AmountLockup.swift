import SwiftUI

/// The gap between the numerals and a unit word, as a fraction of the value's
/// size. Carried by tracking on a near-zero-size carrier rather than by a space
/// character, so the gap is an exact measurement instead of whatever advance the
/// face happens to give a space.
private let unitGapEm: CGFloat = 0.15

/// A currency *symbol* is not a unit *word* and does not want the same handling.
/// `sat` is a label and recedes; the `$` in `$18.42` is part of reading the
/// number, and a greyed, half-size `$` reads as a rendering defect. So a symbol
/// keeps full ink and weight, drops only slightly in size, and tucks tight.
private let symbolScale: CGFloat = 0.85

/// Shared vertical rhythm for a primary amount and its supporting conversion.
/// Interactive secondary values keep a full tap target below the visible line,
/// so the optical gap remains identical to a static receipt amount pair.
enum AmountPairMetrics {
    static let spacing: CGFloat = 4
    static let minimumTapTarget: CGFloat = 44
}

/// The one hero numeral.
///
/// Owns the value/unit lockup, tabular figures, the digit transition, the line
/// box and the autoscale floor, so no caller can get any of them individually
/// wrong — which is how the balance and the amount being typed one screen later
/// ended up in two different typefaces at two different weights.
///
/// **One `Text`, several runs, deliberately.** An `HStack` of two `Text`s would
/// let `minimumScaleFactor` shrink the value and the unit independently, so the
/// size relationship between them would drift exactly when it matters most — on
/// the long amounts that trigger scaling. Runs concatenated into one `Text`
/// scale together.
struct AmountLockup: View {
    let parts: AmountParts
    var role: CashuTextRole = .amountHero
    /// Drives the digit transition. Pass the underlying numeric value.
    var value: Double?
    var isDimmed: Bool = false
    var accessibilityPrefix: String?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.cashuFonts) private var fonts

    var body: some View {
        composed
            .cashuAmount(role, value: value)
            .foregroundStyle(isDimmed ? .secondary : .primary)
            // Reserve exactly one line box at the current text size: constant
            // for a given size, so a unit swap never reflows; growing with it,
            // so large-text users are not cropped.
            .frame(maxWidth: .infinity, minHeight: role.lineHeight(at: typeSize, fonts: fonts))
            .accessibilityLabel(
                accessibilityPrefix.map { "\($0): \(parts.spoken)" } ?? parts.spoken
            )
    }

    /// The value and its unit as runs of a single `Text`.
    ///
    /// A unit word is demoted on three independent axes — size, weight and ink —
    /// so the digits are unmistakably the subject. At parity the unit occupies
    /// roughly a third of the lockup while carrying none of the information.
    ///
    /// The unit sits on the digits' **baseline**, not their cap line. Cap
    /// alignment was tried and reads wrong: a unit word is lowercase, so its
    /// visual mass is at x-height, and lifting it to the cap line leaves it
    /// floating like a superscript rather than belonging to the same amount.
    private var composed: Text {
        let pointSize = role.pointSize(at: typeSize)
        let unitSize = pointSize * CashuTextRole.unitScale

        func unitRun(_ word: String) -> Text {
            Text(word)
                .font(fonts.font(.sans, size: unitSize, weight: role.weight.oneStepDown))
                .foregroundStyle(.secondary)
        }

        // A 1pt carrier whose tracking supplies the whole optical gap.
        let gap = Text(" ")
            .font(.system(size: 1))
            .tracking(pointSize * unitGapEm)

        switch parts.affix {
        case .none:
            return Text(parts.value)
        case .suffix(let word):
            return Text(parts.value) + gap + unitRun(word)
        case .prefix(let symbol):
            // The Bitcoin sign is the unit's primary mark, not a subordinate
            // currency prefix. At the symbol scale it reads visibly smaller
            // than the numeral lockup, so retain the full point size for ₿.
            let symbolSize = symbol == "₿" ? pointSize : pointSize * symbolScale
            return Text(symbol).font(
                fonts.font(.sans, size: symbolSize, weight: role.weight)
            ) + Text(parts.value)
        }
    }
}

extension CashuTextRole {
    /// The unit's size as a fraction of the value's.
    ///
    /// 0.5 is two rungs of the ladder, and combines with a weight step and a
    /// drop to secondary ink for three independent axes of subordination.
    static let unitScale: CGFloat = 0.5
}

extension Font.Weight {
    /// One step down the weight ramp, for the subordinated unit.
    var oneStepDown: Font.Weight {
        switch self {
        case .black: .heavy
        case .heavy: .bold
        case .bold: .semibold
        case .semibold: .medium
        case .medium: .regular
        default: .regular
        }
    }
}

/// The one section overline.
///
/// Replaces six hand-rolled copies, five of which froze tracking at 1.2pt —
/// 0.1em at 12pt, nearly double the documented 0.06em, and correct at exactly
/// one text size because a point value cannot scale. Casing lives in the role,
/// so no call site has to remember it.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .cashuText(.overline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
