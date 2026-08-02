import SwiftUI

/// Full-screen payment status shared by every "Pay" flow (Lightning/BOLT11/BOLT12,
/// on-chain, and Cashu requests). Processing / success / failure are ONE layout: a
/// fixed 72pt icon slot morphs `spinner → green check → red X` in place, with the
/// preserved payment facts (amount / mint / method / fee) shown once beneath and a
/// pinned Liquid Glass CTA. The caller owns the toolbar header ("Pay Lightning" …).
struct PaymentStatusView: View {
    enum Phase: Equatable {
        case processing
        case success
        /// `isCaution` renders an amber warning (e.g. MintSettling) instead of a red X.
        /// `isTerminal` marks a permanent outcome (already paid / issued) so the CTA
        /// becomes "Done" instead of a futile "Try Again".
        case failure(message: String, isCaution: Bool = false, isTerminal: Bool = false)
    }

    /// A custom primary CTA for the failure state (e.g. "Choose another mint"). When
    /// nil, failure falls back to "Done" (terminal) or "Try Again" (retryable).
    struct FailureCTA {
        let title: String
        let action: () -> Void
    }

    /// A preserved payment fact rendered as one detail row (Amount / Mint / Method / Max fee).
    struct DetailRow: Identifiable {
        let icon: String
        let label: String
        let value: String
        /// When true the value slot shows a mini spinner instead of `value`, so a row
        /// whose datum is still resolving keeps its slot reserved (no pop-in / reflow).
        var isPending: Bool = false
        var id: String { label }
    }

    let details: [DetailRow]
    let phase: Phase

    var processingTitle: String = "Processing…"
    var successTitle: String = "Payment Sent!"
    var failureTitle: String = "Payment Failed"

    /// Optional custom failure CTA (overrides the default Done / Try Again button).
    var failureCTA: FailureCTA? = nil

    /// Success → dismiss/complete (Done tap). Failure → back to confirm (Try Again).
    let onDone: () -> Void
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phaseKey: Int {
        switch phase {
        case .processing: return 0
        case .success:    return 1
        case .failure:    return 2
        }
    }

    private var statusTitle: String {
        switch phase {
        case .processing: return processingTitle
        case .success:    return successTitle
        case .failure:    return failureTitle
        }
    }

    private var failureMessage: String? {
        if case .failure(let message, _, _) = phase, !message.isEmpty { return message }
        return nil
    }

    var body: some View {
        // Same vertical scaffold as the confirm screens (`PayFlowScaffold`), so the
        // details block sits at the SAME Y across confirm → processing → success and
        // never jumps as the state changes. The morphing icon + title occupy the hero
        // band where the amount hero sits on the confirm screen.
        PayFlowScaffold {
            VStack(spacing: 16) {
                iconSlot

                VStack(spacing: 8) {
                    Text(statusTitle)
                        .font(.title2.weight(.semibold))
                        .contentTransition(.opacity)
                        .multilineTextAlignment(.center)

                    // Reserved slot so success ↔ failure never nudges the icon above it.
                    Text(failureMessage ?? " ")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .opacity(failureMessage == nil ? 0 : 1)
                        .padding(.horizontal, 32)
                        .frame(minHeight: 44)
                }
            }
        } details: {
            // Payment facts are terminal-only: processing shows just the spinner
            // and title, matching the claiming screen.
            if !details.isEmpty, phase != .processing {
                VStack(spacing: 0) {
                    ForEach(Array(details.enumerated()), id: \.element.id) { index, row in
                        detailRow(row)
                        if index < details.count - 1 { divider }
                    }
                }
                .padding(.horizontal)
            }
        } footer: {
            actionButton
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: phaseKey)
        .onChange(of: phase) { _, newPhase in handlePhase(newPhase) }
        .onAppear { handlePhase(phase) }
    }

    // MARK: Morphing icon slot (fixed footprint — never moves or resizes)

    @ViewBuilder
    private var iconSlot: some View {
        ZStack {
            switch phase {
            case .processing:
                SpinnerRing()
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
            case .success:
                // Blur-to-sharp materialize (DESIGN.md §6 carve-out): the check comes
                // *into focus* as it scales in, riding the same `.smooth(0.3)`. Reduce
                // Motion drops both blur and scale to a plain fade.
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : phaseKey)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity).combined(with: .materializeBlur))
            case .failure(_, let isCaution, _):
                // No `.symbolEffect(.bounce)` here — bounce is the payment-received
                // celebration beat (DESIGN.md §6); a failure/caution glyph must not
                // borrow it. It still scales + fades in, just without the delight.
                Image(systemName: isCaution ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(isCaution ? .orange : .red)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(width: 72, height: 72)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .processing:
            // Reserve the CTA footprint so Done/Try Again don't shift layout in.
            Button(action: {}) { Text(verbatim: " ") }
                .glassButton()
                .disabled(true)
                .opacity(0)
                .accessibilityHidden(true)
        case .success:
            Button(action: onDone) { Text("Done") }
                .glassButton()
        case .failure(_, _, let isTerminal):
            if let failureCTA {
                Button(action: failureCTA.action) { Text(failureCTA.title) }
                    .glassButton()
            } else if isTerminal {
                Button(action: onDone) { Text("Done") }
                    .glassButton()
            } else {
                Button(action: onRetry) { Text("Try Again") }
                    .glassButton()
            }
        }
    }

    private func detailRow(_ row: DetailRow) -> some View {
        HStack {
            Label(row.label, systemImage: row.icon)
                .foregroundStyle(.secondary)
            Spacer()
            if row.isPending {
                // Value not resolved yet — hold the slot with a mini spinner (matches
                // the confirm screen's loading-fee treatment) rather than dropping the
                // row, so nothing below it shifts when the value arrives.
                ProgressView().controlSize(.mini)
            } else {
                Text(row.value)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    /// Hairline separator matching the pay screens' detail rows (no boxed background).
    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.horizontal, 4)
    }

    private func handlePhase(_ newPhase: Phase) {
        switch newPhase {
        case .success:
            HapticFeedback.notification(.success)
        case .failure(_, let isCaution, _):
            HapticFeedback.notification(isCaution ? .warning : .error)
        case .processing:
            break
        }
    }
}

/// 64pt loading ring that shares the checkmark's diameter, so the processing →
/// success cross-fade reads as the ring "closing" into the check rather than a
/// small pill spinner jumping to a large glyph.
private struct SpinnerRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        Group {
            if reduceMotion {
                // Reduce Motion: hand off to the system indicator rather than a
                // hand-rolled infinite rotation. It still conveys indeterminate
                // progress without the custom repeatForever spin.
                ProgressView()
                    .controlSize(.large)
                    .tint(.accentColor)
            } else {
                Circle()
                    .trim(from: 0.1, to: 1.0)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
                    .onAppear { spinning = true }
            }
        }
        .frame(width: 64, height: 64)
        .accessibilityLabel("Processing")
    }
}

/// Shared vertical scaffold for every Pay flow's confirm + status screens, so the
/// payment-details block sits at the **same** vertical position across confirm →
/// processing → success (no jump as the state changes). Layout contract:
///
///     [ topAccessory ]   ← overlaid at the top (e.g. mint chip); does NOT shift the anchor
///     [ fixed top inset — upper-middle anchor ]
///     [ HERO BAND — fixed min-height, content centered ]   ← amount hero | spinner/check + title
///     [ DETAILS BLOCK — its top edge starts at one locked Y everywhere ]
///     [ flexible gap ]
///     [ FOOTER ]         ← Pay / Done, pinned at the bottom
///
/// The hero band is a fixed height, so both the hero **and** the details-block top
/// stay stationary regardless of how many detail rows a given phase shows. Content
/// scrolls if it exceeds the viewport (small devices / large Dynamic Type) rather
/// than clipping. The caller still owns the toolbar header.
struct PayFlowScaffold<TopAccessory: View, Hero: View, Details: View, Footer: View>: View {
    /// Fraction of the available height reserved above the hero band (upper-middle anchor).
    private static var topFraction: CGFloat { 0.16 }
    /// Hero-band height — sized to the tallest hero (Cashu mint-identity + amount).
    /// A floor, not a clamp: it grows for oversized Dynamic Type instead of clipping.
    private static var heroBandHeight: CGFloat { 220 }
    private static var heroDetailsGap: CGFloat { 8 }

    private let topAccessory: TopAccessory
    private let hero: Hero
    private let details: Details
    private let footer: Footer

    init(
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder details: () -> Details,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder topAccessory: () -> TopAccessory = { EmptyView() }
    ) {
        self.hero = hero()
        self.details = details()
        self.footer = footer()
        self.topAccessory = topAccessory()
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: geo.size.height * Self.topFraction)
                        hero
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Self.heroBandHeight)
                        details
                            .padding(.top, Self.heroDetailsGap)
                    }
                    .frame(maxWidth: .infinity)
                    // Resolve the anchored column's geometry as one rigid unit before it
                    // combines with the parent. Without this, when the GeometryReader's
                    // size goes 0 → real on first layout, the hero/details interpolate
                    // from the (0,0) origin under any live ancestor .animation scope
                    // (this screen's value: phase, or PaymentStatusView's value: phaseKey)
                    // — sliding the amount hero in from the top-left. Isolating geometry
                    // leaves opacity/scale transitions (the spinner→check morph) untouched.
                    .geometryGroup()
                }
                footer
            }
            // The top accessory floats above the anchored content so its presence
            // (confirm) or absence (status) never shifts the details-block Y.
            .overlay(alignment: .top) { topAccessory }
        }
    }
}

// MARK: - Materialize transition (DESIGN.md §6 carve-out)

fileprivate extension AnyTransition {
    /// Blur-to-sharp "materialize" for confirmation glyphs: the glyph resolves from
    /// blur radius 4 → 0 as it enters, riding whatever curve the caller animates with
    /// (here the `.smooth(duration: 0.3)` on `phaseKey`). It makes a success check
    /// come *into focus* rather than merely scaling in. DESIGN.md §6 carve-out —
    /// confirmation glyphs only, never money values; callers gate it behind
    /// `!reduceMotion` (this composes only onto the non-reduce-motion branch).
    static var materializeBlur: AnyTransition {
        .modifier(
            active: BlurMaterializeModifier(radius: 4),
            identity: BlurMaterializeModifier(radius: 0)
        )
    }
}

private struct BlurMaterializeModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
