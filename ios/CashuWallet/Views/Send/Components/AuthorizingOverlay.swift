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
    /// Label-only, matching the receipt rows in TransactionDetailView — no leading glyph.
    struct DetailRow: Identifiable {
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

    /// The mint accepted the payment for asynchronous settlement (NUT-05) and
    /// pays out in the background. The success face then must not claim
    /// completion: the glyph becomes a pending clock instead of the green
    /// check (no celebration bounce), and the message slot explains what is
    /// still happening.
    var settlementPending: Bool = false

    /// Optional custom failure CTA (overrides the default Done / Try Again button).
    var failureCTA: FailureCTA? = nil

    /// Success → dismiss/complete (Done tap). Failure → back to confirm (Try Again).
    let onDone: () -> Void
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True when this instance was MOUNTED already at `.success` (a payment
    /// that landed while a waiting face was up — receive invoice, token claim,
    /// ecash claimed). Transitions and phase-keyed effects never fire on a
    /// fresh subtree's initial content, so DESIGN.md §6's celebration was
    /// structurally silent on those surfaces; this gate drives the staged
    /// entrance that restores it. Seeded once — a later phase flip (the morph
    /// path) never turns it on, and `@State` keeps the seed across re-inits.
    @State private var mountedCelebrating: Bool
    /// Flipped ~100ms after appear (celebration mounts only): beat 1 (glyph
    /// materialize + bounce + haptic), with the title and details bands riding
    /// delayed animations off the same flip.
    @State private var entered = false

    init(
        details: [DetailRow],
        phase: Phase,
        processingTitle: String = "Processing…",
        successTitle: String = "Payment Sent!",
        failureTitle: String = "Payment Failed",
        settlementPending: Bool = false,
        failureCTA: FailureCTA? = nil,
        onDone: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.details = details
        self.phase = phase
        self.processingTitle = processingTitle
        self.successTitle = successTitle
        self.failureTitle = failureTitle
        self.settlementPending = settlementPending
        self.failureCTA = failureCTA
        self.onDone = onDone
        self.onRetry = onRetry
        // Failure and settlement-pending mounts stay deliberately still — the
        // staged entrance is the celebration's, and only the celebration's.
        _mountedCelebrating = State(initialValue: {
            if case .success = phase { return !settlementPending }
            return false
        }())
    }

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

    private var statusMessage: String? {
        if case .failure(let message, _, _) = phase, !message.isEmpty { return message }
        if case .success = phase, settlementPending {
            return "The mint accepted this payment and is settling it. Your balance will update automatically."
        }
        return nil
    }

    /// The staged entrance is active for this instance. Reduce Motion keeps
    /// today's single flat fade instead.
    private var staged: Bool { mountedCelebrating && !reduceMotion }
    /// A band is visible when staging is off, or once beat 1 has fired (each
    /// band's own delayed animation supplies its cadence).
    private var bandVisible: Bool { !staged || entered }

    var body: some View {
        // Same vertical scaffold as the confirm screens (`PayFlowScaffold`), so the
        // details block sits at the SAME Y across confirm → processing → success and
        // never jumps as the state changes. The morphing icon + title occupy the hero
        // band where the amount hero sits on the confirm screen.
        PayFlowScaffold {
            VStack(spacing: 16) {
                iconSlot

                // Beat 2: the title band settles in after the check has
                // landed. Inert (opacity 1, offset 0) outside a celebration
                // mount, so the morph path renders byte-identically.
                VStack(spacing: 8) {
                    Text(statusTitle)
                        .font(.title2.weight(.semibold))
                        .contentTransition(.opacity)
                        .multilineTextAlignment(.center)

                    // Reserved slot so success ↔ failure never nudges the icon above it.
                    Text(statusMessage ?? " ")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .opacity(statusMessage == nil ? 0 : 1)
                        .padding(.horizontal, 32)
                        .frame(minHeight: 44)
                }
                .opacity(bandVisible ? 1 : 0)
                .offset(y: staged && !entered ? 8 : 0)
                .animation(.smooth(duration: 0.3).delay(0.12), value: entered)
            }
        } details: {
            // Payment facts are terminal-only: processing shows just the spinner
            // and title, matching the claiming screen.
            if !details.isEmpty, phase != .processing {
                VStack(spacing: 0) {
                    ForEach(Array(details.enumerated()), id: \.element.id) { index, row in
                        detailRow(row)
                    }
                }
                .padding(.horizontal)
                // Beat 3: the receipt settles in last. Opacity + a 6pt rise —
                // never blur; these rows are money values.
                .opacity(bandVisible ? 1 : 0)
                .offset(y: staged && !entered ? 6 : 0)
                .animation(.smooth(duration: 0.3).delay(0.2), value: entered)
            }
        } footer: {
            actionButton
                .padding(.horizontal)
                .padding(.bottom, 16)
                // Rides beat 3 as opacity only — the hit target never moves,
                // and opacity keeps hit-testing, so Done works from frame 1.
                .opacity(bandVisible ? 1 : 0)
                .animation(.smooth(duration: 0.3).delay(0.2), value: entered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.3), value: phaseKey)
        .onChange(of: phase) { _, newPhase in
            handlePhase(newPhase, announce: true)
        }
        .onAppear { handlePhase(phase, announce: false) }
        .task {
            // Beat 1, ~100ms after mount so the check materializes once the
            // parent swap's fade has mostly cleared — the haptic lands WITH
            // the check instead of before it.
            guard staged, !entered else { return }
            try? await Task.sleep(for: .milliseconds(100))
            entered = true
            HapticFeedback.notification(.success)
        }
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
                if settlementPending {
                    // Async settlement isn't the celebration beat: a pending
                    // clock in the app's pending orange, entering like the
                    // failure glyph — no bounce, no green check yet.
                    Image(systemName: "clock.fill")
                        .font(.statusGlyph)
                        .foregroundStyle(.orange)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                } else {
                    // Blur-to-sharp materialize (DESIGN.md §6 carve-out): the check comes
                    // *into focus* as it scales in, riding the same `.smooth(0.3)`. Reduce
                    // Motion drops both blur and scale to a plain fade.
                    //
                    // Two delivery paths for one recipe: the morph (mounted at
                    // processing) gets it via the transition + phaseKey bounce;
                    // a celebration MOUNT gets the state-driven twin below,
                    // because transitions and change-keyed effects never fire
                    // on a fresh subtree's initial content.
                    Image(systemName: "checkmark.circle.fill")
                        .font(.statusGlyph)
                        .foregroundStyle(.green)
                        .symbolEffect(
                            .bounce,
                            value: reduceMotion ? 0 : (mountedCelebrating ? (entered ? 1 : 0) : phaseKey)
                        )
                        .opacity(bandVisible ? 1 : 0)
                        .scaleEffect(staged && !entered ? 0.92 : 1)
                        .blur(radius: staged && !entered ? 4 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: entered)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity).combined(with: .materializeBlur))
                }
            case .failure(_, let isCaution, _):
                // No `.symbolEffect(.bounce)` here — bounce is the payment-received
                // celebration beat (DESIGN.md §6); a failure/caution glyph must not
                // borrow it. It still scales + fades in, just without the delight.
                Image(systemName: isCaution ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                    .font(.statusGlyph)
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
            // Quiet secondary, not the white primary: the payment already
            // happened, Done just closes the screen (matches Android's neutral
            // Done and the Key Imported success face).
            Button(action: onDone) { Text("Done") }
                .flatSheetSecondaryButton()
        case .failure(_, _, let isTerminal):
            if let failureCTA {
                Button(action: failureCTA.action) { Text(failureCTA.title) }
                    .glassButton()
            } else if isTerminal {
                // Same demotion as success — there is nothing left to do here.
                Button(action: onDone) { Text("Done") }
                    .flatSheetSecondaryButton()
            } else {
                Button(action: onRetry) { Text("Try Again") }
                    .glassButton()
            }
        }
    }

    private func detailRow(_ row: DetailRow) -> some View {
        HStack {
            Text(row.label)
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

    private func handlePhase(_ newPhase: Phase, announce: Bool) {
        switch newPhase {
        case .success:
            // On a staged celebration mount the haptic belongs to beat 1 (the
            // `.task` fires it with the check, ~100ms in) — not to onAppear.
            guard !staged else { break }
            HapticFeedback.notification(.success)
            if announce {
                AccessibilityNotification.Announcement(successTitle).post()
            }
        case .failure(_, let isCaution, _):
            HapticFeedback.notification(isCaution ? .warning : .error)
            if announce {
                AccessibilityNotification.Announcement(failureTitle).post()
            }
        case .processing:
            break
        }
    }
}

/// 64pt loading ring that shares the checkmark's diameter, so the processing →
/// success cross-fade reads as the ring "closing" into the check rather than a
/// small pill spinner jumping to a large glyph.
/// Shared indeterminate ring, sized to the status glyph slot. Internal so the
/// melt confirm can put the same spinner in its hero band while the quote is
/// in flight — one wait animation across the whole pay flow.
struct SpinnerRing: View {
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

enum PayFlowContentLayout {
    case anchoredScrollable
    case centered
}

/// Shared vertical scaffold for Pay flow screens. Its default anchored layout keeps the
/// payment-details block at the **same** vertical position across confirm →
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
/// than clipping. Amount entry can instead center its content in the space above a
/// fixed keypad by selecting `.centered`. The caller still owns the toolbar header.
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
    private let contentLayout: PayFlowContentLayout

    init(
        contentLayout: PayFlowContentLayout = .anchoredScrollable,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder details: () -> Details,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder topAccessory: () -> TopAccessory = { EmptyView() }
    ) {
        self.contentLayout = contentLayout
        self.hero = hero()
        self.details = details()
        self.footer = footer()
        self.topAccessory = topAccessory()
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if contentLayout == .anchoredScrollable {
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
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        hero
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1)
                        details
                            .padding(.top, Self.heroDetailsGap)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// The materialize transition this overlay's confirmation glyph rides
// (`AnyTransition.materializeBlur`) lives in LiquidGlassModifiers.swift —
// promoted there so the onboarding stage swaps can share it.
