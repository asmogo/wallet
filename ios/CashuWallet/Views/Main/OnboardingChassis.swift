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

/// Per-step content for the fixed bottom chassis.
struct OnboardingChassisModel {
    var headline: String
    var subhead: String?
    var primary: OnboardingChassisAction?
    var secondary: OnboardingChassisAction?
    var tertiary: OnboardingChassisAction?
    /// Staged-exit support (iCloud success): the chassis chrome recedes while
    /// the stage's balance hero holds through the handoff crossfade.
    var contentOpacity: Double = 1
}

// MARK: - Chassis View

/// The fixed bottom action chassis shared by every onboarding step
/// (docs/product/onboarding-restyle-brief.md §3).
///
/// Pinned via `.safeAreaInset(edge: .bottom)` on the onboarding root, the
/// chassis holds headline → subhead → primary → secondary → tertiary; the
/// stage above owns all vertical slack. The primary CTA's Y position is
/// identical on every step: every slot BELOW the primary is always reserved —
/// an absent action renders a hidden template button, so slot height tracks
/// Dynamic Type instead of a hardcoded constant. Content ABOVE the primary
/// (headline, subhead, accessory) grows upward into the stage and can never
/// move the button.
///
/// The container itself never animates on step change. Its text swaps in
/// place: headlines rise 10 pt while resolving from blur 3 → 0 (~260 ms
/// `.smooth`), the outgoing line just fades (~140 ms) — exits subtler than
/// entrances. CTA labels cross-fade in place. Reduce Motion drops the rise
/// and blur, keeping opacity only.
struct OnboardingChassisView<Accessory: View>: View {
    let model: OnboardingChassisModel
    @ViewBuilder var accessory: Accessory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Indicator slot — resolved as "no indicator" (brief §3): the flow
            // branches into paths of different lengths, so page dots would
            // imply a linear path that doesn't exist. The stage carries the
            // sense of place; the slot stays here for the record.

            ZStack(alignment: .topLeading) {
                Text(model.headline)
                    .font(.largeTitle.weight(.heavy))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(model.headline)
                    .transition(textSwapTransition)
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

            capsuleSlot(model.primary)
                .padding(.top, 24)

            capsuleSlot(model.secondary)
                .padding(.top, 12)

            textLinkSlot(model.tertiary)
                .padding(.top, 12)
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
        Group {
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
            } else {
                // Reserved slot: a hidden template keeps the slot's height (and
                // therefore the primary CTA's Y) constant across steps, tracking
                // Dynamic Type instead of hardcoding a height.
                Button(action: {}) { Text(verbatim: "Template") }
                    .glassButton()
                    .hidden()
                    .disabled(true)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func textLinkSlot(_ action: OnboardingChassisAction?) -> some View {
        HStack {
            Spacer(minLength: 0)
            if let action {
                Button(action: action.action) {
                    Text(action.label)
                        .contentTransition(.opacity)
                }
                .textLinkButton()
                .disabled(action.isDisabled)
                .animation(.easeInOut(duration: 0.2), value: action.label)
                .accessibilityIdentifier(action.accessibilityIdentifier ?? "")
            } else {
                Button(action: {}) { Text(verbatim: "Template") }
                    .textLinkButton()
                    .hidden()
                    .disabled(true)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }
}
