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
            Button(action: action.action) {
                Group {
                    if action.isLoading {
                        ProgressView().tint(.primary)
                    } else {
                        Text(action.label)
                            .contentTransition(.opacity)
                    }
                }
            }
            .glassButton()
            .disabled(action.isDisabled)
            // State feedback, not container motion — label swaps and the
            // enable/disable fade happen in place.
            .animation(.easeOut(duration: 0.2), value: action.isDisabled)
            .animation(.easeInOut(duration: 0.2), value: action.label)
            .animation(.easeInOut(duration: 0.2), value: action.isLoading)
            .accessibilityIdentifier(action.accessibilityIdentifier ?? "")
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func textLinkSlot(_ action: OnboardingChassisAction?) -> some View {
        if let action {
            HStack {
                Spacer(minLength: 0)
                Button(action: action.action) {
                    Text(action.label)
                        .contentTransition(.opacity)
                }
                .textLinkButton()
                .disabled(action.isDisabled)
                .animation(.easeInOut(duration: 0.2), value: action.label)
                .accessibilityIdentifier(action.accessibilityIdentifier ?? "")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
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

/// Help affordance for a step that has no back button — it takes the *same*
/// bar-band leading slot, so the position is never empty and the glyph simply
/// swaps as you move between steps instead of a text link appearing and
/// disappearing from the chassis. Welcome is the only user today.
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
