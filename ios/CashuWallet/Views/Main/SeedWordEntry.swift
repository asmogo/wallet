import SwiftUI
import UIKit

// MARK: - Copy

/// The seed-entry message set, in one place because both hosts (onboarding and
/// Settings → Restore) render it and the strings had already drifted once on
/// the old screen. Android twin: the `RestoreSeed*` constants in
/// `RestoreWalletFlow.kt`.
enum SeedEntryCopy {
    static let subhead = "Enter your 12 words, one at a time."
    static let helper = "Press space after each word."
    static let complete = "All 12 words check out."
    static let rejected = "Not a seed word. Check the spelling."
    static let checksumTitle = "That's not a valid seed phrase."
    static let checksumBody = "One of the words is probably mistyped. Tap any word below to fix it."
    static let pasteLink = "Paste seed phrase"
    static let pasteUnusable = "Nothing in the clipboard looked like a seed phrase."

    static func pastePartial(_ count: Int) -> String {
        "Pasted \(count) \(count == 1 ? "word" : "words"). Enter the rest."
    }

    static func pasteInvalid(at index: Int) -> String {
        "Pasted 12 words, but word \(index + 1) isn't in the list."
    }
}

/// A message the host wants shown in place of the default helper line — a paste
/// result or a checksum failure. Per-word rejection is owned by the field.
struct SeedEntryNotice: Equatable {
    let message: String
    var title: String? = nil
    var severity: ErrorSeverity
}

// MARK: - Metrics

private enum SeedEntryMetrics {
    /// Twelve slots at a 10pt stride. Fixed: the rail is a ruler, so it must not
    /// grow with Dynamic Type or the card would drift off its own scale.
    static let railSlot: CGFloat = 10
    static let railWidth: CGFloat = 2
    static let tickCurrent: CGFloat = 10
    static let tickResting: CGFloat = 3
    /// Tap target width around the 2pt rail. Still under 44pt — the adjustable
    /// accessibility action and the review grid are the compliant paths.
    static let railHitWidth: CGFloat = 24
    /// How far beyond the rail's frame the gesture surface reaches on every
    /// side, so a thumb doesn't need to land on a 24pt strip to engage.
    static let railCaptureInset: CGFloat = 10

    static let railToCard: CGFloat = 20
    static let cardRadius: CGFloat = 14
    static let cardPadding: CGFloat = 20
    static let ordinalWidth: CGFloat = 22
    static let ordinalGap: CGFloat = 12

    /// Ghost cards imply the words still to come. Alpha and scale only — a
    /// static blur can never match across screenshot-golden hosts, and the
    /// Android twin has to draw the identical thing.
    static let ghostScales: [CGFloat] = [0.96, 0.92]
    static let ghostOffsets: [CGFloat] = [-8, -16]
    static let ghostAlphas: [Double] = [0.55, 0.30]

    static let chipRadius: CGFloat = 12
    static let chipPaddingH: CGFloat = 12
    static let chipPaddingV: CGFloat = 8
    static let chipGap: CGFloat = 8
}

// MARK: - The field

/// Word-by-word seed entry: a progress rail, a card holding one word, ghost
/// cards for the words still to come, and up to three wordlist completions.
///
/// The text field is a *single persistent* `UITextField` that never unmounts —
/// advancing changes the ordinal and the ghosts around it, so the keyboard
/// never dismisses and re-presents between words. Everything that animates is
/// therefore a sibling of the field, never an ancestor.
struct SeedWordEntryField: View {
    @Binding var entry: SeedPhraseEntry
    @Binding var isFocused: Bool
    var notice: SeedEntryNotice?
    /// Fired after every commit so the host can run the checksum and set copy.
    var onOutcome: (SeedCommitOutcome) -> Void
    /// Whole-phrase paste, offered as a chip while nothing is entered. The
    /// clipboard/checksum logic stays with the host.
    var onPaste: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rejected = false

    var body: some View {
        Group {
            if entry.isReviewing {
                VStack(alignment: .leading, spacing: 12) {
                    SeedWordReviewGrid(words: entry.words) { slot in
                        HapticFeedback.selection()
                        entry.jump(to: slot)
                        isFocused = true
                    }
                    helperLine
                }
            } else {
                // The rail sizes this row, but chips and helper belong to the
                // card's own column — hung below the rail's extent they landed
                // inside the scroll fade and read as clipped (device review
                // 2026-08-08).
                HStack(alignment: .center, spacing: SeedEntryMetrics.railToCard) {
                    SeedWordProgressRail(entry: entry) { slot in
                        HapticFeedback.selection()
                        entry.jump(to: slot)
                        isFocused = true
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        card
                        SeedWordChipRow(
                            words: entry.completions,
                            onPaste: entry.enteredCount == 0 ? onPaste : nil,
                            onSelect: { word in commit(replacingDraftWith: word) }
                        )
                        helperLine
                    }
                }
            }
        }
        .padding(.horizontal, OnboardingMetrics.gutter)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: entry.completions)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: rejected)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: entry.isReviewing)
    }

    // MARK: Card

    private var card: some View {
        ZStack(alignment: .bottom) {
            ghosts
            liveCard
        }
    }

    /// One empty surface per word still to come, capped at two. They carry no
    /// content — they are the shape of what is left, not a container for it.
    @ViewBuilder
    private var ghosts: some View {
        let remaining = SeedPhraseEntry.wordCount - (entry.index + 1)
        ForEach(Array(SeedEntryMetrics.ghostScales.indices), id: \.self) { depth in
            if remaining > depth {
                RoundedRectangle(cornerRadius: SeedEntryMetrics.cardRadius)
                    .fill(.clear)
                    .liquidGlassInput(in: RoundedRectangle(cornerRadius: SeedEntryMetrics.cardRadius))
                    .frame(height: cardHeight)
                    .scaleEffect(SeedEntryMetrics.ghostScales[depth], anchor: .bottom)
                    .offset(y: SeedEntryMetrics.ghostOffsets[depth])
                    .opacity(SeedEntryMetrics.ghostAlphas[depth])
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var liveCard: some View {
        HStack(spacing: SeedEntryMetrics.ordinalGap) {
            // The ordinal is the only thing that morphs on advance — the field
            // beside it must keep its identity or the keyboard drops.
            Text("\(entry.index + 1)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: SeedEntryMetrics.ordinalWidth, alignment: .trailing)
                .id(entry.index)
                .transition(ordinalMorph)

            SeedWordTextField(
                text: draftBinding,
                placeholder: "word \(entry.index + 1)",
                isLastWord: entry.index == SeedPhraseEntry.wordCount - 1,
                isFocused: $isFocused,
                onCommit: { commit() },
                onBackspaceOnEmpty: stepBack
            )
        }
        .padding(SeedEntryMetrics.cardPadding)
        .frame(height: cardHeight)
        .liquidGlassInput(in: RoundedRectangle(cornerRadius: SeedEntryMetrics.cardRadius))
        .overlay {
            if rejected {
                RoundedRectangle(cornerRadius: SeedEntryMetrics.cardRadius)
                    .stroke(ErrorSeverity.error.foreground, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Word \(entry.index + 1) of \(SeedPhraseEntry.wordCount)")
        .accessibilityValue(entry.draft.isEmpty ? "empty" : entry.draft)
        .accessibilityHint("Type the word, then press space.")
    }

    /// Derived from the type role's line box rather than a constant, so the card
    /// grows with Dynamic Type instead of clipping.
    private var cardHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: .title3).lineHeight + SeedEntryMetrics.cardPadding * 2
    }

    private var ordinalMorph: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .materializeBlur(radius: 2).combined(with: .opacity),
            removal: .opacity
        )
    }

    // MARK: Helper line

    @ViewBuilder
    private var helperLine: some View {
        if let notice {
            InlineNotice(message: notice.message, title: notice.title, severity: notice.severity)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if rejected {
            InlineNotice(message: SeedEntryCopy.rejected, severity: .caution)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(entry.isComplete ? SeedEntryCopy.complete : SeedEntryCopy.helper)
                .cashuText(.metadata)
                .foregroundStyle(entry.isComplete ? Color(.systemGreen) : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Editing

    private var draftBinding: Binding<String> {
        Binding(
            get: { entry.draft },
            set: { newValue in apply(entry.typed(newValue)) }
        )
    }

    private func commit() {
        apply(entry.commit())
    }

    private func commit(replacingDraftWith word: String) {
        // Writing the whole word first means a chip tap goes through exactly the
        // same commit path as typing it, rather than a second way to advance.
        entry.typed(word)
        apply(entry.commit())
    }

    private func stepBack() {
        guard entry.stepBack() else { return }
        rejected = false
        HapticFeedback.selection()
    }

    private func apply(_ outcome: SeedCommitOutcome) {
        switch outcome {
        case .advanced:
            rejected = false
            HapticFeedback.selection()
        case .completed:
            rejected = false
            HapticFeedback.notification(.success)
        case .rejected:
            rejected = true
            HapticFeedback.notification(.error)
        case .none:
            rejected = false
        case .ignored:
            break
        }
        onOutcome(outcome)
    }
}

// MARK: - Progress rail

/// Twelve ticks, one per word. Length carries the emphasis, never colour —
/// green appears only when the whole phrase is in.
private struct SeedWordProgressRail: View {
    let entry: SeedPhraseEntry
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Ticks are presentation only — every touch goes through the
            // gesture surface below, the same shape as the Android rail.
            ForEach(0..<SeedPhraseEntry.wordCount, id: \.self) { slot in
                Capsule()
                    .fill(tint(for: slot))
                    .frame(
                        width: SeedEntryMetrics.railWidth,
                        height: slot == entry.index
                            ? SeedEntryMetrics.tickCurrent
                            : SeedEntryMetrics.tickResting
                    )
                    .frame(
                        width: SeedEntryMetrics.railHitWidth,
                        height: SeedEntryMetrics.railSlot
                    )
            }
        }
        .animation(.snappy(duration: 0.25), value: entry.index)
        .animation(.smooth(duration: 0.3), value: entry.isComplete)
        // Tap jumps; press-and-hold then drag scrubs through the words, the
        // focused word tracking the finger live, releasing wherever it is
        // (jumps are live, so release needs no handler). UIKit recognizers
        // rather than SwiftUI's LongPress→Drag sequence: inside a ScrollView
        // the sequence loses its drag half to the scroll pan on a real device,
        // which shipped this interaction broken once. A UILongPressGesture-
        // Recognizer is hold-then-track as ONE recognizer, and UIScrollView
        // arbitration does the right thing with it — holding still engages the
        // scrub and cancels the scroll; moving early scrolls as normal. The
        // negative padding widens capture beyond the 2pt rail without moving
        // the card; slotAt clamps, so coordinates in the margin still land.
        .overlay {
            RailGestureSurface(
                onTap: { y in
                    onSelect(slot(at: y - SeedEntryMetrics.railCaptureInset))
                },
                onScrubBegan: { y in beginScrub(at: y - SeedEntryMetrics.railCaptureInset) },
                onScrubMoved: { y in continueScrub(at: y - SeedEntryMetrics.railCaptureInset) }
            )
            .padding(-SeedEntryMetrics.railCaptureInset)
        }
        // One element with an adjustable action: twelve 10pt ticks can never be
        // 44pt targets, so assistive navigation goes through the value instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seed word progress")
        .accessibilityValue("Word \(entry.index + 1) of \(SeedPhraseEntry.wordCount)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSelect(min(entry.index + 1, SeedPhraseEntry.wordCount - 1))
            case .decrement: onSelect(max(entry.index - 1, 0))
            @unknown default: break
            }
        }
    }

    private func slot(at y: CGFloat) -> Int {
        min(max(Int(y / SeedEntryMetrics.railSlot), 0), SeedPhraseEntry.wordCount - 1)
    }

    /// Engagement must always be felt: if the hold starts on the focused word
    /// there is nothing to jump to, so the tick comes from here instead of
    /// `onSelect`. Never both — that would double the haptic.
    private func beginScrub(at y: CGFloat) {
        let target = slot(at: y)
        if target == entry.index {
            HapticFeedback.selection()
        } else {
            onSelect(target)
        }
    }

    /// One `onSelect` per *word change*, not per drag sample — the parent fires
    /// a selection haptic on each call, and that is the per-word tick.
    private func continueScrub(at y: CGFloat) {
        let target = slot(at: y)
        guard target != entry.index else { return }
        onSelect(target)
    }

    private func tint(for slot: Int) -> Color {
        if entry.isComplete { return Color(.systemGreen) }
        if slot == entry.index { return .primary }
        // `.quaternary` is a ShapeStyle, not a Color; the semantic UIKit twin is
        // the same ink and adapts to appearance and Increase Contrast the same way.
        return entry.isSettled(slot) ? .secondary : Color(uiColor: .quaternaryLabel)
    }
}

// MARK: - Chip row

/// The row under the card, three-state: the paste chip while nothing is
/// entered, wordlist completions while typing, reserved space otherwise. One
/// row, one height — a hidden chip pins it in every state so the card never
/// reflows as the states swap.
private struct SeedWordChipRow: View {
    let words: [String]
    /// Non-nil only while the paste chip should show.
    let onPaste: (() -> Void)?
    let onSelect: (String) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            // Reserves the real row height without stating one as a constant.
            chipLabel("placeholder").opacity(0).accessibilityHidden(true)

            HStack(spacing: SeedEntryMetrics.chipGap) {
                if let onPaste {
                    // Pasting is the most common way in, so it takes the spot
                    // the eye is already on — directly under the card — rather
                    // than a text link under a disabled CTA. It yields this row
                    // to the suggestions the moment typing starts.
                    Button(action: onPaste) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.footnote.weight(.medium))
                            Text(SeedEntryCopy.pasteLink)
                                .cashuText(.textLink)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, SeedEntryMetrics.chipPaddingH)
                        .padding(.vertical, SeedEntryMetrics.chipPaddingV)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: SeedEntryMetrics.chipRadius))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("onboarding-seed-paste")
                } else {
                    ForEach(words, id: \.self) { word in
                        Button { onSelect(word) } label: { chipLabel(word) }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel(word)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func chipLabel(_ word: String) -> some View {
        Text(word)
            .cashuText(.monoBody)
            .foregroundStyle(.primary)
            .padding(.horizontal, SeedEntryMetrics.chipPaddingH)
            .padding(.vertical, SeedEntryMetrics.chipPaddingV)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: SeedEntryMetrics.chipRadius))
    }
}

// MARK: - Review grid

/// Where a checksum failure lands. The checksum says one of the twelve is
/// wrong but never which, so the only honest recovery is to show all of them.
/// Mirrors `mnemonicWordsGrid`'s geometry so the two seed surfaces read alike.
private struct SeedWordReviewGrid: View {
    let words: [String]
    let onSelect: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Button { onSelect(index) } label: {
                    HStack(spacing: 6) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: SeedEntryMetrics.ordinalWidth, alignment: .trailing)

                        Text(word)
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Word \(index + 1), \(word)")
                .accessibilityHint("Double-tap to edit.")
            }
        }
        .padding(SeedEntryMetrics.cardPadding)
        .liquidGlassInput(in: RoundedRectangle(cornerRadius: SeedEntryMetrics.cardRadius))
    }
}

// MARK: - Rail gesture surface

/// The rail's touch handling, in UIKit because the interaction demands it:
/// `UILongPressGestureRecognizer` is press-and-hold *then track movement* as a
/// single recognizer, and it arbitrates correctly against the enclosing
/// `UIScrollView` — recognizers see touches regardless of the scroll view's
/// content-touch delays, and once the hold recognizes, the scroll pan is
/// locked out for the rest of the touch. SwiftUI's sequenced equivalent loses
/// its drag half to the scroll pan on a real device.
private struct RailGestureSurface: UIViewRepresentable {
    /// All three report a y-position in this surface's own coordinates.
    let onTap: (CGFloat) -> Void
    let onScrubBegan: (CGFloat) -> Void
    let onScrubMoved: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        // Invisible to accessibility on purpose — the rail's merged SwiftUI
        // element (label, value, adjustable action) is the assistive surface.
        view.isAccessibilityElement = false

        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tapped(_:))
        )
        let hold = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.held(_:))
        )
        hold.minimumPressDuration = 0.25
        // A resting thumb wobbles; the default 10pt fails the hold for drift
        // that the user never perceives as movement.
        hold.allowableMovement = 24
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(hold)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: RailGestureSurface

        init(parent: RailGestureSurface) { self.parent = parent }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            parent.onTap(recognizer.location(in: recognizer.view).y)
        }

        @objc func held(_ recognizer: UILongPressGestureRecognizer) {
            let y = recognizer.location(in: recognizer.view).y
            switch recognizer.state {
            case .began: parent.onScrubBegan(y)
            case .changed: parent.onScrubMoved(y)
            default: break
            }
        }
    }
}

// MARK: - The text field

/// A `UITextField` wrapper, for three things SwiftUI's `TextField` cannot do:
///
/// 1. **Backspace on an empty field.** `deleteBackward()` is the only reliable
///    hook; `onKeyPress` is hardware-keyboard only.
/// 2. **Suppressing inline predictions.** Not cosmetic — the predictive bar
///    changes the keyboard's height, which would move the chassis CTA mid-step.
/// 3. **Keeping first responder across value changes**, so advancing a word
///    never dismisses and re-presents the keyboard.
private struct SeedWordTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isLastWord: Bool
    @Binding var isFocused: Bool
    let onCommit: () -> Void
    let onBackspaceOnEmpty: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeUIView(context: Context) -> BackspaceReportingTextField {
        let field = BackspaceReportingTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.onBackspaceOnEmpty = onBackspaceOnEmpty

        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.autocapitalizationType = .none
        field.keyboardType = .asciiCapable
        // Explicitly no content type: a seed phrase must never be offered to a
        // password manager or to AutoFill.
        field.textContentType = nil
        if #available(iOS 17.0, *) { field.inlinePredictionType = .no }

        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: BackspaceReportingTextField, context: Context) {
        context.coordinator.parent = self
        field.onBackspaceOnEmpty = onBackspaceOnEmpty

        // Recomputed here rather than captured once, so Dynamic Type changes
        // land without stating a point size anywhere.
        let size = UIFont.preferredFont(forTextStyle: .title3).pointSize
        field.font = UIFont.monospacedSystemFont(ofSize: size, weight: .medium)

        if field.text != text { field.text = text }
        field.returnKeyType = isLastWord ? .done : .next
        field.placeholder = placeholder

        // Focus has two possible orders and both have to work: the field may
        // already be in a window (ask now), or it may still be joining one
        // because the stage is arriving inside a transition (ask from
        // `didMoveToWindow`). A becomeFirstResponder with no window is silently
        // dropped, and relying on a later `updateUIView` to retry is a race.
        field.wantsFocus = isFocused
        if isFocused, field.window != nil, !field.isFirstResponder {
            field.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SeedWordTextField

        init(parent: SeedWordTextField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onCommit()
            return false
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.isFocused = true
        }
    }
}

/// `deleteBackward()` is the only place UIKit reports a backspace that deletes
/// nothing, which is what "go back a word" has to hang off.
private final class BackspaceReportingTextField: UITextField {
    var onBackspaceOnEmpty: (() -> Void)?
    /// Set while the step wants the keyboard up, so focus can be claimed at the
    /// moment the field joins a window rather than only when SwiftUI happens to
    /// re-run `updateUIView`.
    var wantsFocus = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard wantsFocus, window != nil, !isFirstResponder else { return }
        becomeFirstResponder()
    }

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            onBackspaceOnEmpty?()
            return
        }
        super.deleteBackward()
    }
}
