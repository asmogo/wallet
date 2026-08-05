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
/// `headline`/`subhead` are the *welcome* treatment only (design review
/// 2026-08-05): every other step titles itself at the top of the stage with
/// `OnboardingStepHeader` and leaves these nil, so its actions hug the bottom.
struct OnboardingChassisModel {
    var headline: String?
    var subhead: String?
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
/// row) anchored to the bottom edge. The welcome step additionally carries its
/// headline and subhead here; other steps render `OnboardingStepHeader` at the
/// top of their stage instead. The container itself never animates on step
/// change; its content swaps in place (text rise-and-fade, label cross-fades).
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

            ZStack(alignment: .topLeading) {
                if let headline = model.headline {
                    Text(headline)
                        .font(.largeTitle.weight(.heavy))
                        .tracking(-0.5)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(headline)
                        .transition(textSwapTransition)
                }
            }
            .animation(.smooth(duration: 0.26), value: model.headline)
            .padding(.horizontal, 28)

            ZStack(alignment: .topLeading) {
                if let subhead = model.subhead {
                    Text(subhead)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .id(subhead)
                        .transition(textSwapTransition)
                }
            }
            .animation(.smooth(duration: 0.26), value: model.subhead)
            .padding(.horizontal, 28)

            accessory
                .padding(.top, 16)
                .padding(.horizontal, 28)
                .transition(.opacity)

            VStack(spacing: 12) {
                capsuleSlot(model.primary)
                capsuleSlot(model.secondary)
                textLinkSlot(model.tertiary)
            }
            .padding(.top, model.headline != nil ? 24 : 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(model.contentOpacity)
        // The staged exit is deliberate motion, not container motion.
        .animation(.easeOut(duration: 0.22), value: model.contentOpacity)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.background)
    }

    /// In-place text swap: enter with a 10 pt rise resolving from blur 3 → 0,
    /// leave with opacity alone (DESIGN.md's subtler-exits carve-out). Reduce
    /// Motion is opacity both ways.
    private var textSwapTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: AnyTransition.offset(y: 10)
                .combined(with: .materializeBlur(radius: 3))
                .combined(with: .opacity)
                .animation(.smooth(duration: 0.26)),
            removal: AnyTransition.opacity.animation(.easeOut(duration: 0.14))
        )
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

/// Top-of-step title + supporting copy — every step except welcome, which
/// keeps its text in the bottom action block (design review 2026-08-05).
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
        .padding(.horizontal, 28)
    }
}

/// Circular Liquid Glass back button — onboarding's nav chrome (`.quaternary`
/// circle below iOS 26). Press feedback rides the shared PressableButtonStyle.
struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .liquidGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Back")
        .accessibilityIdentifier("onboarding-back")
    }
}
