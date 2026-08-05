import SwiftUI

// MARK: - Chassis Model

/// One action slot in the onboarding chassis.
///
/// Primary and secondary slots render as full-width capsules (`.glassButton()`),
/// the tertiary slot as a text link (`.textLinkButton()`) — the chassis reuses
/// the existing button vocabulary and introduces no new styles.
struct OnboardingChassisAction {
    var label: String
    var isLoading = false
    var isDisabled = false
    var accessibilityIdentifier: String?
    var action: () -> Void
}

/// Per-step content for the bottom action chassis.
///
/// Actions only: every step — welcome included — titles itself at the top of
/// its stage with `OnboardingStepHeader`, so the chassis holds nothing but the
/// buttons and they hug the bottom edge.
struct OnboardingChassisModel {
    var primary: OnboardingChassisAction?
    var secondary: OnboardingChassisAction?
    var tertiary: OnboardingChassisAction?
    /// Staged-exit support (iCloud success): the chassis chrome recedes while
    /// the stage's balance hero holds through the handoff crossfade.
    var contentOpacity: Double = 1
}

// MARK: - Chassis View

/// The bottom action chassis shared by every onboarding step.
///
/// Pinned via `.safeAreaInset(edge: .bottom)` on the onboarding root, it holds
/// the step's actions (plus an optional accessory like the seed-acknowledge
/// row) anchored to the bottom edge; every step's title lives at the top of its
/// stage in `OnboardingStepHeader`. The container itself never animates on step
/// change; its content swaps in place (label cross-fades).
struct OnboardingChassisView<Accessory: View>: View {
    let model: OnboardingChassisModel
    @ViewBuilder var accessory: Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Indicator slot — resolved as "no indicator" (brief §3): the flow
            // branches into paths of different lengths, so page dots would
            // imply a linear path that doesn't exist. The slot stays here for
            // the record.

            accessory
                .padding(.top, 16)
                .padding(.horizontal, 28)
                .transition(.opacity)

            VStack(spacing: 12) {
                capsuleSlot(model.primary)
                capsuleSlot(model.secondary)
                textLinkSlot(model.tertiary)
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(model.contentOpacity)
        // The staged exit is deliberate motion, not container motion.
        .animation(.easeOut(duration: 0.22), value: model.contentOpacity)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.background)
    }

    // MARK: Slots

    @ViewBuilder
    private func capsuleSlot(_ action: OnboardingChassisAction?) -> some View {
        if let action {
            let content = CapsuleContent(action)
            Button(action: action.action) {
                ZStack {
                    // Footprint reservation — the capsule must not resize as
                    // the spinner takes over from the label. Same device as
                    // PaymentStatusView's invisible disabled CTA
                    // (AuthorizingOverlay.swift).
                    Text(verbatim: " ")
                        .font(.body.weight(.semibold))
                        .opacity(0)
                        .accessibilityHidden(true)

                    Group {
                        switch content {
                        case .loading:
                            ProgressView().tint(.primary)
                        case .label(let text):
                            Text(text)
                        }
                    }
                    .id(content)
                    .transition(contentMorph(radius: 2))
                }
            }
            .glassButton()
            .disabled(action.isDisabled)
            // Pin the label. Mid-morph the Button briefly holds two Texts, and
            // the derived accessibility label would concatenate them — which
            // both garbles VoiceOver and breaks OnboardingChassisUITests, which
            // resolves buttons by label (`app.buttons["Restore Wallet"]`).
            .accessibilityLabel(action.label)
            // State feedback, not container motion — the content swap and the
            // enable/disable fade happen in place. Label and spinner are one
            // value, so a step that relabels *and* clears `isLoading` runs a
            // single transition instead of two racing ones.
            .animation(.easeOut(duration: 0.2), value: action.isDisabled)
            .animation(.easeInOut(duration: 0.26), value: content)
            .accessibilityIdentifier(action.accessibilityIdentifier ?? "")
            .padding(.horizontal, 24)
            .transition(slotMorph)
        }
    }

    @ViewBuilder
    private func textLinkSlot(_ action: OnboardingChassisAction?) -> some View {
        if let action {
            HStack {
                Spacer(minLength: 0)
                Button(action: action.action) {
                    Text(action.label)
                        .id(action.label)
                        .transition(contentMorph(radius: 1.5))
                }
                .textLinkButton()
                .disabled(action.isDisabled)
                // Same reason as the capsule slot above.
                .accessibilityLabel(action.label)
                .animation(.easeInOut(duration: 0.26), value: action.label)
                .accessibilityIdentifier(action.accessibilityIdentifier ?? "")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .transition(slotMorph)
        }
    }

    // MARK: Morphs

    /// Blur-masked cross-fade for a button's *content*.
    ///
    /// The blur rides **both** halves, which is the entire technique: without
    /// it the eye resolves the outgoing and incoming labels as two distinct
    /// objects overlapping, and the swap reads as a replacement. Blurred, they
    /// blend and it reads as one object transforming. Radii stay small — this
    /// is a mask, not a flourish. `.contentTransition(.opacity)` can't carry a
    /// blur, which is why the content is identity-keyed and given a real
    /// transition instead.
    ///
    /// The exit is shorter than the entrance and carries no scale (DESIGN.md §6
    /// "exits subtler than entrances"); it keeps its blur because a mask on one
    /// half only does nothing.
    private func contentMorph(radius: CGFloat) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: AnyTransition.materializeBlur(radius: radius)
                .combined(with: .opacity)
                .animation(.smooth(duration: 0.26)),
            removal: AnyTransition.materializeBlur(radius: radius)
                .combined(with: .opacity)
                .animation(.easeOut(duration: 0.16))
        )
    }

    /// Occupancy change for a whole slot — a button arriving or leaving as the
    /// step's action set changes.
    ///
    /// These are Liquid Glass surfaces, so the entrance *materializes* (blur and
    /// scale together) rather than plainly fading: the surface should read as a
    /// real material arriving. The removal is opacity alone, per the same
    /// "exits subtler" carve-out.
    ///
    /// Deliberately carries no `.animation(...)`: `advance(to:)` / `retreat(to:)`
    /// in `OnboardingView` already mutate `currentStep` inside
    /// `withAnimation(.easeInOut(duration: 0.28))`, and `chassisModel` is derived
    /// from it — inheriting that transaction is what makes the stack's height
    /// reflow and the button's materialize move as one thing rather than two.
    private var slotMorph: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: AnyTransition.scale(scale: 0.96)
                .combined(with: .materializeBlur(radius: 4))
                .combined(with: .opacity),
            removal: .opacity
        )
    }
}

/// The capsule slot's animated content as a single value, so label→label and
/// label→spinner are the same transition rather than two mechanisms.
private enum CapsuleContent: Equatable, Hashable {
    case loading
    case label(String)

    init(_ action: OnboardingChassisAction) {
        self = action.isLoading ? .loading : .label(action.label)
    }
}

// MARK: - Step chrome

/// Shared step-layout metrics. Onboarding draws no navigation bar, so these
/// reproduce the system's large-title geometry by hand: a 44 pt bar band that
/// holds the back button where a step has one, with the title on the line
/// below it. Every step resolves to the same `titleTopInset`, so the title
/// stays put across the stage swap instead of jumping per screen.
enum OnboardingMetrics {
    /// Page gutter — `spacing.page` in the design system.
    static let gutter: CGFloat = 28
    /// Margin above the bar band.
    static let barTopInset: CGFloat = 8
    /// Bar band height — a standard 44 pt navigation bar / hit target.
    static let barHeight: CGFloat = 44
    /// Band-to-title gap.
    static let titleGap: CGFloat = 8
    /// Where the title starts on a stage that draws no back button, so it
    /// lands on the same line as the stages that do.
    static let titleTopInset: CGFloat = barTopInset + barHeight + titleGap
}

/// Top-of-step title + supporting copy — every step, welcome included, so the
/// title sits in the same place from the first screen onward.
struct OnboardingStepHeader: View {
    var title: String
    var subhead: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.heavy))
                .tracking(-0.5)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let subhead {
                Text(subhead)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OnboardingMetrics.gutter)
    }
}

/// Circular Liquid Glass back button — onboarding's nav chrome (`.quaternary`
/// circle below iOS 26). Press feedback rides the shared PressableButtonStyle.
struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        OnboardingBarButton(
            systemImage: "chevron.backward",
            accessibilityLabel: "Back",
            accessibilityIdentifier: "onboarding-back",
            action: action
        )
    }
}

/// Help affordance for a step that has no back button. It takes the bar band's
/// *trailing* slot (`OnboardingView.swift`, `alignment: .trailing`) — opposite
/// the leading slot every other step gives Back — so the band is occupied on
/// every step rather than a text link appearing and disappearing from the
/// chassis. Android states the same rule in its own measure
/// (`OnboardingChassis.kt`, `Alignment.End`). Welcome is the only user today.
///
/// Note this is *not* a shared-geometry glyph swap, and never was: back and help
/// are mounted inside their own stage views, so they unmount with the stage and
/// ride `OnboardingView.stepTransition` like everything else on screen. There is
/// nothing persistent for a symbol-replace transition to attach to. Making it a
/// true morph would mean hoisting the bar band out of all eight stages into the
/// onboarding root.
struct OnboardingInfoButton: View {
    let action: () -> Void

    var body: some View {
        OnboardingBarButton(
            systemImage: "questionmark",
            accessibilityLabel: "What is ecash?",
            accessibilityIdentifier: "onboarding-info",
            action: action
        )
    }
}

/// The shared bar-band affordance both of the above are made of: one 44 pt
/// glass circle in the leading slot. Keeping it in one place is what makes the
/// back/help swap land on identical geometry.
private struct OnboardingBarButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .liquidGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
