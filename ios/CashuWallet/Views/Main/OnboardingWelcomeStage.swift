import SwiftUI

/// The welcome stage's "note becomes cash" piece (onboarding-restyle-brief §4).
///
/// A minimal geometric construction in pure ink: a thin-stroke banknote
/// outline slowly closes into an ecash-token circle, and two
/// `MintAvatarView`-sized companion circles resolve beside it — a note
/// becoming digital cash. No gradient, no illustration, no fill, no shadow;
/// system-semantic strokes only, so it reads as restrained after the tenth
/// launch.
///
/// Self-playing via one autoreversing SwiftUI animation (~3.2 s each way) —
/// animation-driven, never timer-driven, so `UITEST_DISABLE_ANIMATIONS`
/// freezes it deterministically. Reduce Motion (and the `.quiet` variant on
/// the restore-method chooser) renders the composed token-cluster end state,
/// static but intentional. Decorative only — hidden from accessibility.
struct OnboardingWelcomeStage: View {
    enum Variant {
        /// The welcome step: full size, self-playing.
        case full
        /// The restore-method chooser: static, receded — a quiet mark.
        case quiet
    }

    var variant: Variant = .full
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tokenized = false

    // The note is a ~1.6:1 banknote outline; the token keeps its height as
    // diameter. Companions echo MintAvatarView's 36 pt circle geometry.
    private let noteSize = CGSize(width: 180, height: 112)
    private let tokenDiameter: CGFloat = 112
    private let companionDiameter: CGFloat = 36
    private let strokeWidth: CGFloat = 1.5

    private var animates: Bool { variant == .full && !reduceMotion }

    var body: some View {
        // Non-animating presentations hold the resolved end state.
        let morphed = animates ? tokenized : true

        ZStack {
            companion(offset: CGSize(width: -86, height: 46), visible: morphed)
            companion(offset: CGSize(width: 88, height: -52), visible: morphed)

            RoundedRectangle(cornerRadius: morphed ? tokenDiameter / 2 : 14)
                .strokeBorder(.secondary, lineWidth: strokeWidth)
                .frame(
                    width: morphed ? tokenDiameter : noteSize.width,
                    height: morphed ? tokenDiameter : noteSize.height
                )
        }
        .opacity(variant == .quiet ? 0.5 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .onAppear {
            guard animates else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                tokenized = true
            }
        }
    }

    private func companion(offset: CGSize, visible: Bool) -> some View {
        Circle()
            .strokeBorder(.tertiary, lineWidth: strokeWidth)
            .frame(width: companionDiameter, height: companionDiameter)
            .scaleEffect(visible ? 1 : 0.92)
            .opacity(visible ? 1 : 0)
            .offset(offset)
    }
}

#Preview("Welcome") {
    OnboardingWelcomeStage()
}

#Preview("Quiet") {
    OnboardingWelcomeStage(variant: .quiet)
}
