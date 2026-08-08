import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var handoff: OnboardingHandoffCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var nostrBackupService = NostrMintBackupService.shared

    @State private var currentStep: OnboardingStep = .welcome
    @State private var seedEntry = SeedPhraseEntry()
    /// Host-owned copy for the seed field: paste results and checksum failure.
    /// Per-word rejection is the field's own business.
    @State private var seedNotice: SeedEntryNotice?
    @State private var seedFieldFocused = false
    @State private var isCreating = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    // Restore mints state
    @State private var mintUrlInput = ""
    @State private var mintsToRestore: [String] = []
    @State private var restoreMintError: String?
    @State private var mintBackupSearchCompleted = false
    @State private var showMintBackupSheet = false
    /// Measured height of `mintBackupSheet` — same content-fit pair as
    /// `conceptSheet`, so the sheet hugs its copy instead of sitting at `.medium`.
    @State private var mintBackupSheetHeight: CGFloat = 0
    @FocusState private var mintFieldFocused: Bool

    // Dedicated restore/results screen (forward-only): a snapshot of the staged
    // mints plus each one's phase, driving the progress rows + live total.
    @State private var restoringMints: [String] = []
    @State private var restorePhases: [String: MintRestorePhase] = [:]

    // Best-effort mint identity (name + logo) fetched the moment a URL is staged,
    // so rows show the mint's own profile pic instead of a monogram.
    @State private var stagedMintIconUrls: [String: String] = [:]
    @State private var stagedMintNames: [String: String] = [:]

    // Seed phrase reveal / acknowledge state
    @State private var seedRevealed = false
    @State private var seedAcknowledged = false
    @State private var seedCopied = false
    // Snapshot of the seed words taken when the seed step appears, so wallet
    // manager publishes during the step can't rebuild (and re-animate) the grid.
    @State private var mnemonicWords: [String] = []

    // First-mint state (create path)
    @State private var showConceptSheet = false
    /// Measured height of `conceptSheet`, so the sheet hugs its content instead
    /// of sitting at a fixed `.medium` detent.
    @State private var conceptSheetHeight: CGFloat = 0
    @State private var selectedMintUrls: Set<String> = []
    @State private var customMintUrls: [String] = []
    @State private var showCustomMintInput = false
    @State private var customMintInput = ""
    @State private var isAddingFirstMints = false
    @State private var currentAddingMint: String?
    @State private var firstMintError: String?
    @State private var firstMintSeverity: ErrorSeverity = .error
    @State private var restoreMintSeverity: ErrorSeverity = .info

    /// Add-first-mint field carries both validation advisories and connect failures.
    private func setFirstMintNotice(_ message: String?, severity: ErrorSeverity = .error) {
        firstMintError = message
        firstMintSeverity = severity
    }

    /// Paste-mint-list channel carries successes and advisories as well as errors.
    private func setRestoreMintNotice(_ message: String?, severity: ErrorSeverity = .info) {
        restoreMintError = message
        restoreMintSeverity = severity
    }

    // iCloud restore state
    @State private var detectedICloudBackup: ICloudBackupInfo? = nil
    @State private var isDetectingICloudBackup = true
    @State private var iCloudRestorePhase = ICloudRestorePhase.preview
    // Staged exit on the success screen: chrome recedes while the balance hero
    // holds, then the ASCII handoff curtain sweeps down over what remains.
    @State private var isCompleting = false

    // ASCII terrain band entrance (first launch of onboarding only): the title
    // y-rise settles at ~400ms, then this flips at 450ms under a 900ms easeOut
    // so the field comes up like light in a room — a slow plain fade, not a
    // materialize. It's a texture, not an object; a blur on already-soft 12pt
    // glyphs behind a gradient mask reads as nothing while costing a full
    // offscreen pass. Mirrors the web's `<Reveal immediate variant="fade" slow
    // delay={480}>`.
    @State private var asciiFieldEntered = false

    // Per-step entrance animation triggers
    @State private var welcomeAppeared = false
    @State private var mnemonicAppeared = false
    @State private var firstMintAppeared = false
    @State private var restoreMethodAppeared = false
    @State private var restoreInputAppeared = false
    /// Back was tapped on seed entry and the retreat is waiting for the
    /// keyboard to finish dismissing. See the back button for why.
    @State private var pendingSeedRetreat = false
    @State private var restoreMintsAppeared = false
    @State private var restoreProgressAppeared = false
    @State private var iCloudPreviewAppeared = false

    enum ICloudRestorePhase { case preview, restoring, success }

    enum OnboardingStep {
        case welcome
        case showMnemonic
        case firstMint
        case restoreMethod
        case restoreInput
        case restoreMints
        case restoreProgress
        case iCloudRestore
    }

    private let recommendedMints: [RecommendedMint] = RecommendedMint.suggested

    var body: some View {
        ZStack {
            switch currentStep {
            case .welcome:
                welcomeStage
                    .transition(stepTransition)
            case .showMnemonic:
                showMnemonicStage
                    .transition(stepTransition)
            case .firstMint:
                firstMintStage
                    .transition(stepTransition)
            case .restoreMethod:
                restoreMethodStage
                    .transition(stepTransition)
            case .restoreInput:
                restoreInputStage
                    .transition(stepTransition)
            case .restoreMints:
                restoreMintsStage
                    .transition(stepTransition)
            case .restoreProgress:
                restoreProgressStage
                    .transition(stepTransition)
            case .iCloudRestore:
                iCloudStage
                    .transition(stepTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Behind the stage switch, in front of the window ground — error
        // banners and stage content render over it.
        .background { asciiFieldLayer }
        .safeAreaInset(edge: .bottom) {
            // The chassis container never animates (brief §3) — only its text
            // and labels cross-fade in place, choreographed inside
            // OnboardingChassisView with value-scoped animations.
            OnboardingChassisView(model: chassisModel) {
                chassisAccessory
            }
            // The chassis ground: solid on scrolling steps (content must not
            // bleed under the CTAs), clear on the ASCII-field pair so the
            // terrain's bottom fade continues faintly behind the glass
            // buttons. Driven by opacity, not a style swap, so it dissolves
            // inside the same 0.28s transaction as the field itself when the
            // pair is entered or left.
            .background {
                Rectangle()
                    .fill(.background)
                    .opacity(stepShowsAsciiField ? 0 : 1)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showConceptSheet) {
            conceptSheet
        }
        // A second sibling sheet rather than an enum-driven one: the two belong
        // to different steps and are never both true.
        .sheet(isPresented: $showMintBackupSheet) {
            mintBackupSheet
        }
        .onAppear {
            startAsciiFieldEntrance()
            guard walletManager.hasIncompleteICloudRestore else { return }
            currentStep = .iCloudRestore
            iCloudRestorePhase = .preview
            detectedICloudBackup = nil
            isDetectingICloudBackup = true
        }
        // The moment the keyboard is actually gone — spring tail included —
        // which is when a pending seed-entry retreat may land. See the seed
        // stage's back button.
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)
        ) { _ in
            completePendingSeedRetreat()
        }
    }

    /// Runs the retreat a seed-entry back tap queued behind the keyboard
    /// dismissal. Idempotent: the didHide notification and the fallback timer
    /// can both arrive, and only the first may act.
    private func completePendingSeedRetreat() {
        guard pendingSeedRetreat else { return }
        pendingSeedRetreat = false
        guard currentStep == .restoreInput else { return }
        retreat(to: .restoreMethod)
    }

    // MARK: - Ascii Field Layer

    /// The two adjacent steps that share the terrain. Nothing else gets it —
    /// not seed, not first-mint, not the restore substeps.
    private var stepShowsAsciiField: Bool {
        currentStep == .welcome || currentStep == .restoreMethod
    }

    /// Deterministic-evidence hook: launching with
    /// `ASCII_FIELD_STATIC_TIME=2.5` freezes the band at that moment (the
    /// docs/screenshots strips). Absent in normal launches.
    private static let asciiFieldStaticTime: Double? =
        ProcessInfo.processInfo.environment["ASCII_FIELD_STATIC_TIME"].flatMap(Double.init)

    /// The terrain band, mounted once here at the root rather than inside the
    /// stages. Welcome and Restore Wallet are *adjacent* steps; mounted
    /// per-stage the field would unmount and materialize-blur on that swap,
    /// and the two screens would read as two separate wallpapers that happen
    /// to match. Hoisted, the terrain keeps drifting and only the text above
    /// it changes — one continuous space. Visibility is opacity only: leaving
    /// the pair fades over the existing 0.28s step transition (the clock
    /// pauses); returning fades back in and resumes from wall-clock.
    private var asciiFieldLayer: some View {
        GeometryReader { geo in
            // `safeAreaInset` extends the bottom safe area by the chassis
            // height, so the inset read here is chassis + home indicator —
            // exactly the underlap the layer needs to run beneath the
            // chassis' opaque background and terminate with no visible edge.
            let chassisInset = geo.safeAreaInsets.bottom
            let windowHeight = geo.size.height + geo.safeAreaInsets.top + chassisInset
            let resolved = AsciiFieldLayout.resolve(
                windowHeight: windowHeight,
                topInset: geo.safeAreaInsets.top,
                chassisInset: chassisInset,
                headerClearance: AsciiFieldLayout.headerClearance()
            )
            // Suppression (tight vertical space) hides rather than unmounts:
            // the view's identity — and with it the wall clock — must survive,
            // or a pass through a suppressed layout would replay from t=0.
            let layout = resolved ?? AsciiFieldLayout.fallback(chassisInset: chassisInset)
            let visible = resolved != nil && stepShowsAsciiField && asciiFieldEntered
            AsciiFieldView(
                staticTime: Self.asciiFieldStaticTime,
                active: stepShowsAsciiField && !showConceptSheet && resolved != nil
            )
                .frame(width: geo.size.width, height: layout.layerHeight)
                // Transparent → opaque over the visible band's top ~30%, like
                // the web band's mask-image; then opaque → floor across the
                // chassis edge, so the terrain dims toward the buttons and
                // keeps running — very subtle — behind their glass all the
                // way to the window bottom, instead of cutting out above
                // them. Continuous gradients, never stepped, so neither
                // fade bands.
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: layout.maskOpaqueFraction),
                            .init(color: .black, location: layout.bottomFadeStart),
                            .init(
                                color: .black.opacity(AsciiFieldLayout.bottomFloorAlpha),
                                location: layout.bottomFadeEnd
                            ),
                            .init(
                                color: .black.opacity(AsciiFieldLayout.bottomFloorAlpha),
                                location: 1
                            ),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                // Pinned to the *window* bottom (through the extended safe
                // area), so the terrain's on-screen position is a function of
                // window size and the pair's constant chassis height — never
                // of header height, stage content, or current step.
                .offset(y: geo.size.height + chassisInset - layout.layerHeight)
                .opacity(visible ? 1 : 0)
        }
    }

    /// First-launch entrance: title y-rise settles (~400ms), then a 450ms
    /// delay and a 900ms easeOut fade. Under Reduce Motion the field is
    /// simply present — full opacity, no fade.
    private func startAsciiFieldEntrance() {
        guard !asciiFieldEntered else { return }
        if reduceMotion || Self.asciiFieldStaticTime != nil {
            asciiFieldEntered = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.9)) {
                asciiFieldEntered = true
            }
        }
    }

    // Quiet materialize between steps — no lateral slide. A horizontal push
    // read as jarring here; the incoming stage scales 0.96 → 1 while resolving
    // from blur (onboarding-restyle-brief §5), the outgoing stage just blurs
    // and fades (exits subtler than entrances). The entrance overlaps the tail
    // of the exit by ~80 ms. Reduce Motion is a plain crossfade.
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: AnyTransition.scale(scale: 0.96)
                .combined(with: .materializeBlur(radius: 6))
                .combined(with: .opacity)
                .animation(.smooth(duration: 0.28).delay(0.10)),
            removal: AnyTransition.materializeBlur(radius: 6)
                .combined(with: .opacity)
                .animation(.easeOut(duration: 0.18))
        )
    }

    private func advance(to step: OnboardingStep) {
        resetAppeared(for: step)
        withAnimation(.easeInOut(duration: 0.28)) {
            currentStep = step
        }
    }

    private func retreat(to step: OnboardingStep) {
        resetAppeared(for: step)
        withAnimation(.easeInOut(duration: 0.28)) {
            currentStep = step
        }
    }

    private func resetAppeared(for step: OnboardingStep) {
        switch step {
        case .welcome: welcomeAppeared = false
        case .showMnemonic: mnemonicAppeared = false
        case .firstMint: firstMintAppeared = false
        case .restoreMethod: restoreMethodAppeared = false
        case .restoreInput: restoreInputAppeared = false
        case .restoreMints: restoreMintsAppeared = false
        case .restoreProgress: restoreProgressAppeared = false
        case .iCloudRestore: iCloudPreviewAppeared = false
        }
    }

    private func triggerEntrance(_ action: @escaping () -> Void) {
        // Fire immediately — the step crossfade owns opacity, so we start
        // the y-rise the moment the view appears.
        action()
    }

    // Y-rise + a touch of blur ("materializing"), no opacity — the step
    // transition owns the fade; doubling opacity here flickers. Tightened to
    // 0.4 s / 12 pt / 0.07 s stagger so each screen settles crisply rather than
    // drifting, and so the rise doesn't compound the new directional slide.
    // Reduce Motion drops both the rise and the blur.
    @ViewBuilder
    private func stagger<V: View>(appeared: Bool, index: Int, @ViewBuilder content: () -> V) -> some View {
        content()
            .offset(y: reduceMotion ? 0 : (appeared ? 0 : 12))
            .blur(radius: reduceMotion ? 0 : (appeared ? 0 : 3))
            .animation(.smooth(duration: 0.4).delay(Double(index) * 0.07), value: appeared)
    }

    // MARK: - Chassis

    /// Per-step chassis content. Every button, label, disabled rule, and
    /// accessibility identifier moved here verbatim from the old inline CTA
    /// stacks — the chassis changes where actions live, never what they do.
    private var chassisModel: OnboardingChassisModel {
        switch currentStep {
        case .welcome:
            return OnboardingChassisModel(
                primary: OnboardingChassisAction(
                    label: "Create Wallet",
                    isLoading: isCreating,
                    isDisabled: isCreating,
                    accessibilityIdentifier: "onboarding-create-wallet",
                    action: createWallet
                ),
                secondary: OnboardingChassisAction(
                    label: "Restore Wallet",
                    isDisabled: isCreating,
                    action: {
                        HapticFeedback.selection()
                        advance(to: .restoreMethod)
                    }
                )
            )

        case .showMnemonic:
            return OnboardingChassisModel(
                primary: OnboardingChassisAction(
                    label: "I've Saved My Seed Phrase",
                    isDisabled: !seedAcknowledged,
                    accessibilityIdentifier: "onboarding-saved-seed",
                    action: {
                        HapticFeedback.selection()
                        advance(to: .firstMint)
                    }
                )
            )

        case .firstMint:
            return OnboardingChassisModel(
                primary: OnboardingChassisAction(
                    label: "Continue",
                    isLoading: isAddingFirstMints,
                    isDisabled: (selectedMintUrls.isEmpty && customMintInput.isEmpty) || isAddingFirstMints,
                    accessibilityIdentifier: "onboarding-continue",
                    action: continueFromFirstMint
                ),
                tertiary: OnboardingChassisAction(
                    label: "Skip for now",
                    isDisabled: isAddingFirstMints,
                    accessibilityIdentifier: "onboarding-skip-mint",
                    action: skipFirstMint
                )
            )

        case .restoreMethod:
            return OnboardingChassisModel(
                primary: OnboardingChassisAction(
                    label: "Restore from iCloud",
                    action: {
                        HapticFeedback.selection()
                        isDetectingICloudBackup = true
                        detectedICloudBackup = nil
                        advance(to: .iCloudRestore)
                    }
                ),
                secondary: OnboardingChassisAction(
                    label: "Use Seed Phrase",
                    action: {
                        HapticFeedback.selection()
                        advance(to: .restoreInput)
                    }
                )
            )

        case .restoreInput:
            return OnboardingChassisModel(
                primary: OnboardingChassisAction(
                    label: "Continue",
                    isLoading: isRestoring,
                    isDisabled: !seedEntry.isComplete || seedEntry.isReviewing || isRestoring,
                    // The seed keyboard's return key is also labelled
                    // "Continue", so a label-only query matches two elements.
                    accessibilityIdentifier: "onboarding-restore-continue",
                    action: initializeAndProceed
                )
                // Paste lives in the stage's chip row, not here: as a chassis
                // tertiary it vanished on the first keystroke and shifted
                // Continue (device review 2026-08-08), and it buried the most
                // common restore path under a disabled CTA.
            )

        case .restoreMints:
            return OnboardingChassisModel(
                primary: OnboardingChassisAction(
                    label: mintsToRestore.isEmpty
                        ? "Restore"
                        : "Restore from \(mintsToRestore.count) mint\(mintsToRestore.count == 1 ? "" : "s")",
                    isDisabled: mintsToRestore.isEmpty,
                    // Stable handle for the label, which is the only readout of
                    // how many mints got staged.
                    accessibilityIdentifier: "onboarding-restore-mints",
                    action: startRestoreFlow
                )
            )

        case .restoreProgress:
            // Forward-only — Continue enables once every mint has settled.
            return OnboardingChassisModel(
                primary: OnboardingChassisAction(
                    label: "Continue",
                    isDisabled: !restoreAllSettled,
                    action: finishRestore
                )
            )

        case .iCloudRestore:
            switch iCloudRestorePhase {
            case .preview:
                // No backup is not a dead end. The seed phrase is the way
                // through, so the primary becomes that route rather than a
                // permanently disabled "Restore Wallet".
                if case .notFound = iCloudPreviewState {
                    return OnboardingChassisModel(
                        primary: OnboardingChassisAction(
                            label: "Use Seed Phrase Instead",
                            action: {
                                HapticFeedback.selection()
                                advance(to: .restoreInput)
                            }
                        )
                    )
                }
                return OnboardingChassisModel(
                    primary: OnboardingChassisAction(
                        label: "Restore Wallet",
                        isDisabled: isDetectingICloudBackup || detectedICloudBackup == nil,
                        action: runICloudRestore
                    )
                )
            case .restoring:
                // No actions while restoring — the stage's spinner carries it.
                return OnboardingChassisModel()
            case .success:
                return OnboardingChassisModel(
                    primary: OnboardingChassisAction(
                        label: "Open Wallet",
                        isDisabled: isCompleting,
                        action: openRestoredWallet
                    ),
                    contentOpacity: isCompleting ? 0 : 1
                )
            }
        }
    }

    /// The seed-acknowledge row is the one control that must sit adjacent to
    /// the primary it gates — it rides the chassis accessory slot, above the
    /// primary so it can never move the button. The "never share" warning sits
    /// with it for the same reason: pinned here it argues for the checkbox
    /// directly below it and can never push the CTA around.
    @ViewBuilder
    private var chassisAccessory: some View {
        if currentStep == .showMnemonic {
            VStack(spacing: 20) {
                seedWarningNotice
                seedAcknowledgeRow
            }
        }
    }

    /// Mirrors the acknowledge row's geometry — icon column, gap, and text
    /// style all match — so the two read as one aligned block. Deliberately a
    /// triangle, not a check-shield: a shield reads as "you're protected",
    /// which is the opposite of what this sentence says.
    private var seedWarningNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
            Text("Never share these words with anyone.")
                .font(.subheadline)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.orange)
        .accessibilityElement(children: .combine)
    }

    private var seedAcknowledgeRow: some View {
        Button(action: {
            HapticFeedback.selection()
            withAnimation(.snappy) { seedAcknowledged.toggle() }
        }) {
            HStack(spacing: 12) {
                Image(systemName: seedAcknowledged ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(seedAcknowledged ? Color.primary : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    // Value-scoped so the checkbox flip stays animated
                    // under the chassis' step-change shield.
                    .animation(.snappy, value: seedAcknowledged)
                Text("I've written down my seed phrase and stored it safely.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-ack-seed")
    }

    // MARK: - Welcome Stage

    private var welcomeStage: some View {
        VStack(spacing: 0) {
            // "What is ecash?" lives here rather than in the chassis: as a
            // tertiary text link it made welcome the only 3-slot step, so the
            // button stack changed height the moment you left it. It sits in
            // the bar band's trailing slot — opposite where other steps put
            // Back — so the band reads the same everywhere and the chassis
            // holds a steady two buttons.
            OnboardingInfoButton {
                HapticFeedback.selection()
                showConceptSheet = true
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, OnboardingMetrics.gutter)
            .padding(.top, OnboardingMetrics.barTopInset)

            stagger(appeared: welcomeAppeared, index: 0) {
                // The only title that keeps a hardcoded break. Left to wrap
                // naturally it wraps after "In" — "Private cash. In" / "your
                // pocket." — splitting the second sentence. Breaking at the
                // sentence boundary is the deliberate exception.
                OnboardingStepHeader(
                    title: "Private cash.\nIn your pocket.",
                    subhead: "An ecash wallet for Bitcoin and Lightning."
                )
            }
            // Welcome now draws a bar button like every other step, so it uses
            // the same barTopInset + barHeight + titleGap stack instead of
            // titleTopInset — the title lands on the identical line either way.
            .padding(.top, OnboardingMetrics.titleGap)

            Spacer(minLength: 0)

            if let error = walletManager.errorMessage {
                ErrorBannerView(message: "Couldn't start the wallet. \(error)", severity: .error)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            if let error = errorMessage {
                InlineNotice(message: error, severity: .error)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: errorMessage)
        .animation(.snappy, value: walletManager.errorMessage)
        .onAppear {
            triggerEntrance { welcomeAppeared = true }
        }
    }

    // MARK: - Concept Sheet

    private var conceptSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ecash is bearer cash for Bitcoin.")
                .font(.title.weight(.heavy))
                .tracking(-0.3)
                .lineSpacing(-1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 16) {
                Text("Whoever holds it, owns it. Your balance stays on this device, hidden from everyone else.")
                Text("Mints hold the Bitcoin behind your ecash. You can use several at once.")
                Text("Send instantly. Cash out to Lightning anytime.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                HapticFeedback.selection()
                showConceptSheet = false
            }) {
                Text("Got it")
            }
            .glassButton()
            .padding(.top, 4)
        }
        .padding(28)
        // Size the sheet to its content. A `.medium` detent is a fraction of the
        // screen, not of the copy, so a `Spacer()` above the button used to
        // absorb the leftover — leaving a gap that grew with device height
        // (~107pt on iPhone 17e, ~134pt on iPhone 11) rather than a designed
        // value. Measuring keeps the copy-to-button gap a constant 20pt and
        // matches Android, whose sheet already hugs its content.
        .contentFitMeasured { conceptSheetHeight = $0 }
        // No `NavigationStack` here, so the detent must not reserve nav-bar
        // chrome. Very large accessibility text scrolls inside the clamped
        // sheet — the same contract as every other content-fit sheet.
        .contentFitDetent(conceptSheetHeight, estimate: 360, navigationBar: false)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Mint Backup Sheet

    /// What "Find my mints" actually does. The chip deliberately names the
    /// outcome rather than the transport, but this sheet is the one place the
    /// user has explicitly asked how it works, and withholding the mechanism
    /// there is the same opacity that made the old automatic lookup feel like
    /// the wallet knew too much. Beat one matches the Settings copy almost word
    /// for word (`NostrSettingsSection`), so the two surfaces corroborate each
    /// other and a curious user can find the toggle. Beat two is why the button
    /// is safe to press. Beat three pre-answers the empty-handed outcome.
    private var mintBackupSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your mint list can be backed up.")
                .font(.title.weight(.heavy))
                .tracking(-0.3)
                .lineSpacing(-1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 16) {
                Text("Your wallet publishes an encrypted list of the mints you use to your Nostr relays. Only your seed phrase can open it.")
                Text("Find my mints looks that list up and stages every mint in it. Nothing is restored until you tap Restore.")
                Text("If you never published a list, nothing turns up. Add your mints by hand instead.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                HapticFeedback.selection()
                showMintBackupSheet = false
            }) {
                Text("Got it")
            }
            .glassButton()
            .padding(.top, 4)
        }
        .padding(28)
        .contentFitMeasured { mintBackupSheetHeight = $0 }
        .contentFitDetent(mintBackupSheetHeight, estimate: 360, navigationBar: false)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Restore Method Stage

    private var restoreMethodStage: some View {
        VStack(spacing: 0) {
            OnboardingBackButton { retreat(to: .welcome) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OnboardingMetrics.gutter)
                .padding(.top, OnboardingMetrics.barTopInset)

            stagger(appeared: restoreMethodAppeared, index: 0) {
                OnboardingStepHeader(
                    title: "Restore wallet.",
                    subhead: "Choose how to restore your wallet."
                )
            }
            .padding(.top, OnboardingMetrics.titleGap)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            triggerEntrance { restoreMethodAppeared = true }
        }
    }

    // MARK: - iCloud Restore Stage

    private var iCloudStage: some View {
        Group {
            switch iCloudRestorePhase {
            case .preview:
                iCloudPreviewStage
            case .restoring:
                iCloudRestoringStage
            case .success:
                iCloudSuccessStage
            }
        }
        .animation(.easeInOut(duration: 0.3), value: iCloudRestorePhase)
        .task {
            // Detection blocks on a keychain query + KV-store flush. Run it off
            // the main actor so it can't hitch the crossfade into this screen.
            let info = await WalletManager.detectICloudBackupOffMain()
            withAnimation(reduceMotion ? nil : .snappy) {
                detectedICloudBackup = info
                isDetectingICloudBackup = false
            }
        }
    }

    private enum ICloudPreviewState {
        case detecting
        case found(ICloudBackupInfo)
        case notFound
    }

    private var iCloudPreviewState: ICloudPreviewState {
        if isDetectingICloudBackup { return .detecting }
        if let backup = detectedICloudBackup { return .found(backup) }
        return .notFound
    }

    private var iCloudPreviewIcon: String {
        switch iCloudPreviewState {
        case .detecting: return "icloud"
        case .found: return "icloud.and.arrow.down"
        case .notFound: return "exclamationmark.icloud"
        }
    }

    private var iCloudPreviewTitle: String {
        switch iCloudPreviewState {
        case .detecting: return "Checking iCloud…"
        case .found: return "Wallet found in iCloud."
        case .notFound: return "No backup in iCloud."
        }
    }

    private var iCloudPreviewStage: some View {
        VStack(spacing: 0) {
            OnboardingBackButton { retreat(to: .restoreMethod) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OnboardingMetrics.gutter)
                .padding(.top, OnboardingMetrics.barTopInset)

            stagger(appeared: iCloudPreviewAppeared, index: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    // Header reflects detection state — no longer a hardcoded
                    // "Wallet found" that contradicts a "no backup" body.
                    OnboardingStepHeader(title: iCloudPreviewTitle)

                    Image(systemName: iCloudPreviewIcon)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 28)
                        .padding(.top, 10)
                        .contentTransition(.symbolEffect(.replace))

                    Group {
                        switch iCloudPreviewState {
                        case .detecting:
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.75)
                                Text("Checking iCloud…")
                            }
                        case .found(let backup):
                            VStack(alignment: .leading, spacing: 4) {
                                Text(backup.timestamp.formatted(date: .abbreviated, time: .shortened))
                                // A backup written before any mint was added
                                // carries the seed alone. Say so plainly — the
                                // wallet lands empty and Settings is the only
                                // place to add mints afterwards.
                                Text(backup.mintURLs.isEmpty
                                     ? "Seed only. No mints saved."
                                     : "\(backup.mintURLs.count) mint\(backup.mintURLs.count == 1 ? "" : "s")")
                            }
                        case .notFound:
                            Text("Make sure you're signed in to the same Apple ID with iCloud Keychain enabled. Otherwise, restore with your seed phrase.")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, OnboardingMetrics.titleGap)

            Spacer()

            if let error = errorMessage {
                ErrorBannerView(message: error, severity: .error)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: errorMessage)
        .onAppear {
            triggerEntrance { iCloudPreviewAppeared = true }
        }
    }

    private var iCloudRestoringStage: some View {
        let mintCount = detectedICloudBackup?.mintURLs.count ?? 0
        return VStack(spacing: 0) {
            OnboardingStepHeader(
                title: "Restoring wallet.",
                // A seed-only backup has no mints to scan, so naming a count
                // of zero here would read as a failure mid-flight.
                subhead: mintCount == 0
                    ? "Restoring your seed…"
                    : "Restoring your funds from \(mintCount) mint\(mintCount == 1 ? "" : "s")…"
            )
            .padding(.top, OnboardingMetrics.titleTopInset)

            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Three genuinely different outcomes hide behind one success screen, and
    /// only one of them is "your money is back". A seed-only backup lands in an
    /// empty wallet with no mints, and a mint-carrying backup can still restore
    /// to zero — neither may claim the funds are ready.
    private func iCloudSuccessSubhead(mintCount: Int) -> String {
        if mintCount == 0 {
            return "Add your mints in Settings to recover any funds."
        }
        if walletManager.balance > 0 {
            return "Across \(mintCount) mint\(mintCount == 1 ? "" : "s")."
        }
        return "No funds on your \(mintCount) mint\(mintCount == 1 ? "" : "s")."
    }

    private var iCloudSuccessStage: some View {
        // A centered terminal "done" moment: the recovered balance is the hero,
        // rendered identically to the wallet's balance. Everything else recedes
        // on exit; the ASCII handoff curtain then sweeps down over what's left.
        let count = detectedICloudBackup?.mintURLs.count ?? 0
        return VStack(spacing: 16) {
            OnboardingStepHeader(
                title: "Wallet restored.",
                subhead: iCloudSuccessSubhead(mintCount: count)
            )
            .padding(.top, OnboardingMetrics.titleTopInset)
            .opacity(isCompleting ? 0 : 1)

            Spacer()

            // Hero — echoes MainWalletView's balance treatment exactly; the
            // one element held at full opacity while the chrome recedes,
            // until the curtain covers it.
            Text(SettingsManager.shared.formatBalanceWithUnit(walletManager.balance))
                .font(.system(size: 44, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(walletManager.balance)))
                .foregroundStyle(.primary)
                // Gutter belongs to the elements that need it — the header
                // carries its own, and stacking a second one indented the
                // title to 56 pt.
                .padding(.horizontal, OnboardingMetrics.gutter)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                // One hero gesture: the symbol bounce. Scale floor raised to
                // 0.85 (Emil's "never below 0.9-ish") so it settles rather
                // than pops. Reduce Motion gets a plain fade, no bounce.
                .symbolEffect(.bounce, value: reduceMotion ? false : iCloudRestorePhase == .success)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                .opacity(isCompleting ? 0 : 1)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func runICloudRestore() {
        guard detectedICloudBackup != nil else { return }
        // This is the one place chassis *occupancy* changes without a step
        // change — `.restoring` empties the stack entirely. It has to ride the
        // same transaction `advance`/`retreat` use, or the slot's transition has
        // nothing to animate against and the button snaps away.
        withAnimation(.easeInOut(duration: 0.28)) {
            iCloudRestorePhase = .restoring
        }
        errorMessage = nil
        Task { @MainActor in
            do {
                try await walletManager.restoreFromICloudBackup()
                withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.85)) {
                    iCloudRestorePhase = .success
                }
                HapticFeedback.notification(.success)
            } catch {
                withAnimation(.easeInOut(duration: 0.28)) {
                    iCloudRestorePhase = .preview
                }
                errorMessage = error.userFacingWalletMessage
            }
        }
    }

    private func openRestoredWallet() {
        guard !isCompleting else { return }
        HapticFeedback.selection()

        // Reduce Motion: skip the staged exit entirely; the coordinator also
        // skips the curtain, so ContentView's plain crossfade is the whole
        // transition (opacity is vestibular-safe).
        if reduceMotion {
            handoff.begin(reduceMotion: true) { await walletManager.completeRestore() }
            return
        }

        // Chrome recedes while the balance hero holds; the curtain sweeps down
        // over both and the handoff flips `needsOnboarding` at full cover.
        withAnimation(.easeOut(duration: 0.22)) { isCompleting = true }
        handoff.begin(reduceMotion: false) { await walletManager.completeRestore() }
    }

    // MARK: - Show Mnemonic Stage

    private var showMnemonicStage: some View {
        VStack(spacing: 0) {
            OnboardingBackButton { retreat(to: .welcome) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OnboardingMetrics.gutter)
                .padding(.top, OnboardingMetrics.barTopInset)

            // Title + subhead only, like every sibling step. The "never share"
            // warning used to sit here; it now rides the chassis accessory
            // directly above the acknowledge row it argues for.
            stagger(appeared: mnemonicAppeared, index: 0) {
                OnboardingStepHeader(
                    title: "Your seed phrase.",
                    subhead: "Write these 12 words down in order. This is the only way to recover your wallet."
                )
            }
            .padding(.top, OnboardingMetrics.titleGap)

            // The seed grid deliberately gets NO stagger entrance: any offset/
            // blur ramp on this block reads as a flicker on first paint, and
            // re-composition mid-entrance restarts it. The step crossfade owns
            // its appearance; the tap-to-reveal animation is untouched.
            ZStack {
                // While hidden, the real words are never put into the view at
                // all — masked strings stand in, exactly like Android's
                // "••••••" placeholders.
                //
                // `.redacted` stops the words being *drawn*, but a `Text` still
                // publishes its own string to the accessibility tree, and
                // `.accessibilityHidden` does not reliably reach the lazily
                // created children of a `LazyVGrid`. VoiceOver could therefore
                // read all 12 words aloud while they sat blurred on screen.
                // Substituting the content is the only version of "hidden" that
                // VoiceOver honours too. As a bonus the uniform mask width
                // stops the redaction bars leaking each word's length.
                mnemonicWordsGrid(
                    words: seedRevealed
                        ? mnemonicWords
                        : Array(repeating: "••••••", count: mnemonicWords.count)
                )
                    // A bare `.blur` is animatable, and on this screen's
                    // entrance transition SwiftUI ramps the radius up from its
                    // identity (0 = fully legible), briefly exposing the phrase
                    // before it settles at 9 — the "flicker" users reported.
                    // Redaction can't be defeated by an animation: while
                    // unrevealed the real characters are never drawn, so no
                    // animation timing can leak them. The blur stays purely for
                    // the reveal aesthetic and animates 9 → 0 on tap; the
                    // simultaneous un-redact is masked under that blur.
                    .redacted(reason: seedRevealed ? [] : .placeholder)
                    .blur(radius: seedRevealed ? 0 : 9)
                    .allowsHitTesting(seedRevealed)
                    // Keep the secret words out of the accessibility tree
                    // until revealed — otherwise VoiceOver reads all 12
                    // aloud while they're still blurred on screen.
                    .accessibilityHidden(!seedRevealed)

                if !seedRevealed {
                    VStack(spacing: 6) {
                        Image(systemName: "eye")
                            .font(.title3)
                        Text("Tap to reveal")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Reveal seed phrase")
                    .accessibilityHint("Shows your 12-word recovery phrase")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default, toggleSeedReveal)
                }
            }
            // Tapping a revealed card hides it again — the phrase should be
            // easy to put away once it's been written down, not stuck on
            // screen for the rest of the step. The label tracks the state so
            // VoiceOver announces the action it will actually perform.
            .accessibilityAction(
                named: seedRevealed ? "Hide seed phrase" : "Reveal seed phrase",
                toggleSeedReveal
            )
            // The Seed Card Exception (DESIGN.md §5): the phrase is a single
            // object you act on, not screen content, so it earns a container.
            // The card is also what gives tap-to-reveal a visible edge — the
            // gesture used to target an invisible rectangle.
            .padding(20)
            .frame(maxWidth: .infinity)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14))
            // Must match the card's shape, not a bare rect, so the hit area is
            // exactly the surface the user can see.
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture(perform: toggleSeedReveal)
            .padding(.horizontal, OnboardingMetrics.gutter)
            .padding(.top, 24)

            Button(action: copyMnemonic) {
                HStack(spacing: 6) {
                    Image(systemName: seedCopied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                    Text(seedCopied ? "Copied" : "Copy")
                        .contentTransition(.opacity)
                }
                .animation(.snappy, value: seedCopied)
            }
            .textLinkButton()
            .frame(maxWidth: .infinity)
            // The card edge already separates the link from the words, so this
            // is less than the 20 the bare grid needed.
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .onAppear {
            mnemonicWords = walletManager.getMnemonicWords()
            // Every entry to this step starts hidden and unacknowledged.
            // These three are @State on the root, so without this a back-out
            // to Welcome and a second Create Wallet would re-enter with the
            // phrase still revealed — and, worse, with the CTA already armed
            // over words the user hasn't looked at this time. Resetting here
            // rather than in `createWallet()` covers every entry path.
            //
            // Android gets the same reset for free: `seedAcknowledged` is
            // cleared in the Welcome chassis' onCreate, and `revealed` /
            // `copied` are `remember` state that dies with the stage
            // composable (OnboardingScreen.kt).
            seedRevealed = false
            seedAcknowledged = false
            seedCopied = false
            triggerEntrance { mnemonicAppeared = true }
        }
    }

    /// Tapping the card toggles the phrase. Hiding is safe in the same way
    /// revealing is: `.redacted` flips instantly so the real characters stop
    /// being drawn on the same frame, and only the blur ramps — there is no
    /// window where the words sit unblurred.
    private func toggleSeedReveal() {
        HapticFeedback.selection()
        withAnimation(.snappy(duration: 0.25)) {
            seedRevealed.toggle()
        }
    }

    private func copyMnemonic() {
        UIPasteboard.general.string = mnemonicWords.joined(separator: " ")
        withAnimation(.snappy) { seedCopied = true }
        HapticFeedback.selection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.snappy) { seedCopied = false }
        }
    }

    private func mnemonicWordsGrid(words: [String]) -> some View {
        // Monospaced words with the number in tertiary. The card around the
        // whole grid carries the containment (see The Seed Card Exception),
        // so the words themselves stay quiet — no per-word material, no
        // per-word background.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 6) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, alignment: .trailing)

                    Text(word)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    // MARK: - First Mint Stage

    private var firstMintStage: some View {
        VStack(spacing: 0) {
            OnboardingBackButton {
                guard !isAddingFirstMints else { return }
                retreat(to: .showMnemonic)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OnboardingMetrics.gutter)
            .padding(.top, OnboardingMetrics.barTopInset)

            stagger(appeared: firstMintAppeared, index: 0) {
                OnboardingStepHeader(
                    title: "Pick your first mint.",
                    subhead: "Mints issue your ecash and redeem it for Bitcoin. Add more anytime in Settings."
                )
            }
            .padding(.top, OnboardingMetrics.titleGap)

            firstMintList
                .padding(.top, 16)
        }
        .animation(.snappy, value: firstMintError)
        .onAppear {
            triggerEntrance { firstMintAppeared = true }
        }
    }

    private var firstMintList: some View {
        ScrollView {
            VStack(spacing: 0) {
                let allRows: [String] = recommendedMints.map(\.url) + customMintUrls

                ForEach(Array(allRows.enumerated()), id: \.element) { index, url in
                    firstMintRow(url: url)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)

            if showCustomMintInput {
                customMintInputRow
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            } else {
                Button(action: {
                    HapticFeedback.selection()
                    withAnimation(.snappy) { showCustomMintInput = true }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add custom mint URL")
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                }
                .textLinkButton()
                .padding(.top, 4)
                .accessibilityIdentifier("onboarding-add-custom-mint")
            }

            if let error = firstMintError {
                InlineNotice(message: error, severity: firstMintSeverity)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            if let current = currentAddingMint, isAddingFirstMints {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to \(shortenUrl(current))…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func firstMintRow(url: String) -> some View {
        let selected = selectedMintUrls.contains(url)
        let recommended = recommendedMints.first(where: { $0.url == url })

        Button(action: {
            HapticFeedback.selection()
            withAnimation(.snappy) {
                if selected {
                    selectedMintUrls.remove(url)
                } else {
                    selectedMintUrls.insert(url)
                }
            }
        }) {
            HStack(spacing: 12) {
                MintAvatarView(
                    iconUrl: recommended?.iconUrl ?? stagedMintIconUrls[url],
                    name: recommended?.name ?? stagedMintNames[url] ?? shortenUrl(url)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(recommended?.name ?? stagedMintNames[url] ?? shortenUrl(url))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(shortenUrl(url))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? .primary : Color.primary.opacity(0.22))
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customMintInputRow: some View {
        // Styled to read as the same control as the Recover-funds mint field
        // (`restoreMintsList`): system font, standard placeholder, 14pt
        // corner. It used to be monospaced with a hand-rolled placeholder
        // overlay — a URL you type is input like any other, not code.
        HStack(spacing: 10) {
            TextField("mint.example.com", text: $customMintInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.done)
                .onSubmit(commitCustomMintInput)
                .foregroundStyle(.primary)
                .tint(.primary)
                .accessibilityIdentifier("onboarding-custom-mint-field")

            Button(action: commitCustomMintInput) {
                Image(systemName: customMintInput.isEmpty ? "doc.on.clipboard" : "arrow.right.circle.fill")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(customMintInput.isEmpty ? .secondary : .primary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(customMintInput.isEmpty ? "Paste from clipboard" : "Add mint")
            .accessibilityHint(customMintInput.isEmpty ? "Pastes mint URL from clipboard" : "Adds mint to restore list")
            .accessibilityIdentifier("onboarding-commit-custom-mint")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func commitCustomMintInput() {
        if customMintInput.isEmpty {
            if let pasted = UIPasteboard.general.string {
                customMintInput = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return
        }
        guard let normalized = normalizedMintURL(from: customMintInput) else {
            setFirstMintNotice("That doesn't look like a mint URL.", severity: .caution)
            return
        }
        if recommendedMints.contains(where: { $0.url == normalized }) || customMintUrls.contains(normalized) {
            setFirstMintNotice("That mint is already in the list.", severity: .caution)
            return
        }
        HapticFeedback.selection()
        firstMintError = nil
        withAnimation(.snappy) {
            customMintUrls.append(normalized)
            selectedMintUrls.insert(normalized)
            customMintInput = ""
            showCustomMintInput = false
        }
        fetchStagedMintInfo(normalized)
    }

    private func continueFromFirstMint() {
        if !customMintInput.isEmpty {
            commitCustomMintInput()
            guard customMintInput.isEmpty else { return }
        }
        guard !selectedMintUrls.isEmpty else { return }
        isAddingFirstMints = true
        firstMintError = nil

        Task { @MainActor in
            // Preserve recommended list order; custom URLs go last in entry order.
            let ordered = recommendedMints.map(\.url).filter { selectedMintUrls.contains($0) }
                + customMintUrls.filter { selectedMintUrls.contains($0) }

            for url in ordered {
                currentAddingMint = url
                do {
                    try await walletManager.addMint(url: url)
                } catch {
                    setFirstMintNotice("Couldn't connect to \(shortenUrl(url)). \(error.userFacingWalletMessage)")
                    AppLogger.wallet.error("First-mint add error for \(url): \(error)")
                    isAddingFirstMints = false
                    currentAddingMint = nil
                    return
                }
            }
            currentAddingMint = nil
            isAddingFirstMints = false
            HapticFeedback.notification(.success)
            finishOnboarding()
        }
    }

    private func skipFirstMint() {
        HapticFeedback.selection()
        finishOnboarding()
    }

    // MARK: - Restore Input Stage

    private var restoreInputStage: some View {
        VStack(spacing: 0) {
            OnboardingBackButton {
                // A sequenced exit, one motion at a time (device review
                // 2026-08-08, three times). The tap drops the keyboard
                // immediately — that is the response cue — and the chassis
                // rides down with it as a stable object, Continue still
                // Continue; only once everything has settled does the stage
                // cross-fade and one button morph into two in place.
                //
                // "Settled" is keyboardDidHide, not a guessed delay: the
                // keyboard's declared duration is 0.25s but its spring tail
                // runs visibly longer, and a cross-fade launched into that
                // tail lands the terrain and the growing chassis on a
                // still-moving floor — the "crashes down" of review three.
                // The timer below is only a fallback for the no-software-
                // keyboard case (hardware keyboard attached), where didHide
                // never fires.
                //
                // Back is one hop to the method chooser, not two to welcome
                // (product decision, reversing the restyle brief's rule).
                seedFieldFocused = false
                pendingSeedRetreat = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    completePendingSeedRetreat()
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OnboardingMetrics.gutter)
                .padding(.top, OnboardingMetrics.barTopInset)

            stagger(appeared: restoreInputAppeared, index: 0) {
                OnboardingStepHeader(
                    title: "Restore wallet.",
                    subhead: SeedEntryCopy.subhead
                )
            }
            .padding(.top, OnboardingMetrics.titleGap)

            // Scrolls because the keyboard is up for this whole step: on an SE
            // at a large Dynamic Type size the card, chips and helper line do
            // not fit the band above it, and clipping them would be worse than
            // a short scroll.
            ScrollView {
                stagger(appeared: restoreInputAppeared, index: 1) {
                    SeedWordEntryField(
                        entry: $seedEntry,
                        isFocused: $seedFieldFocused,
                        notice: seedNotice,
                        onOutcome: handleSeedOutcome,
                        onPaste: pasteMnemonicFromClipboard
                    )
                }
                .padding(.top, 32)
                .padding(.bottom, ScrollFadeMetrics.band)
            }
            .scrollDismissesKeyboard(.never)
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeFade(bottom: 0)
            .frame(maxHeight: .infinity)

            if let error = errorMessage {
                ErrorBannerView(message: error, severity: .error)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: errorMessage)
        .onAppear {
            triggerEntrance { restoreInputAppeared = true }
            // Word-by-word entry is keyboard-driven, so the field autofocuses —
            // a deliberate exception to the "land calm" rule that restoreMints
            // still keeps. But not on the first frame: the keyboard's own
            // animation overlapping the stage materialize read as two fighting
            // motions (device review 2026-08-08). Let the stage land (~0.38s:
            // 0.10 delay + 0.28 transition), then the keyboard rises as its
            // own clean motion.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard currentStep == .restoreInput else { return }
                seedFieldFocused = true
            }
        }
        .onDisappear { seedFieldFocused = false }
        .onChange(of: seedEntry.isReviewing) { _, reviewing in
            // Leaving the review grid means the user is fixing a word; the
            // checksum message that sent them there is no longer true.
            if !reviewing { seedNotice = nil }
        }
    }

    /// Every commit reports back so the host can clear stale copy and run the
    /// checksum at the only moment it can be run.
    private func handleSeedOutcome(_ outcome: SeedCommitOutcome) {
        if outcome != .ignored { seedNotice = nil }
        guard outcome == .completed else { return }
        runSeedChecksum()
    }

    /// The wordlist check is local and per-word; the BIP-39 checksum needs all
    /// twelve and can only say "one of these is wrong", never which one. So the
    /// failure hands the user the whole phrase to look at.
    private func runSeedChecksum() {
        guard seedEntry.isComplete else { return }
        guard !walletManager.validateMnemonic(seedEntry.phrase) else {
            seedNotice = nil
            return
        }
        seedEntry.markReviewing()
        seedFieldFocused = false
        seedNotice = SeedEntryNotice(
            message: SeedEntryCopy.checksumBody,
            title: SeedEntryCopy.checksumTitle,
            severity: .error
        )
        HapticFeedback.notification(.error)
    }

    private func pasteMnemonicFromClipboard() {
        guard let content = UIPasteboard.general.string else {
            seedNotice = SeedEntryNotice(message: SeedEntryCopy.pasteUnusable, severity: .caution)
            return
        }

        let outcome = seedEntry.fill(from: content)
        seedFieldFocused = true

        switch outcome {
        case .filled:
            HapticFeedback.notification(.success)
            seedNotice = nil
            runSeedChecksum()
        case .partial(let count):
            HapticFeedback.selection()
            seedNotice = SeedEntryNotice(message: SeedEntryCopy.pastePartial(count), severity: .caution)
        case .invalid(let index):
            HapticFeedback.notification(.warning)
            seedNotice = SeedEntryNotice(message: SeedEntryCopy.pasteInvalid(at: index), severity: .caution)
        case .unusable:
            HapticFeedback.notification(.error)
            seedNotice = SeedEntryNotice(message: SeedEntryCopy.pasteUnusable, severity: .caution)
        }
    }

    // MARK: - Restore Mints Stage

    private var restoreMintsStage: some View {
        VStack(spacing: 0) {
            // Both bar-band slots are occupied here: Back leading, and help
            // trailing because "Find my mints" is the way through this step for
            // most people and nothing else on screen says what it does.
            HStack(spacing: 0) {
                OnboardingBackButton {
                    mintsToRestore.removeAll()
                    restoreMintError = nil
                    // Clear the searched flag too, or returning to this step
                    // lands on "No backup found" instead of the line that names
                    // the button — a dead screen with no way forward.
                    mintBackupSearchCompleted = false
                    retreat(to: .restoreInput)
                }

                Spacer(minLength: 0)

                OnboardingInfoButton(
                    accessibilityLabel: "What does Find my mints do?",
                    accessibilityIdentifier: "onboarding-mint-backup-info"
                ) {
                    HapticFeedback.selection()
                    showMintBackupSheet = true
                }
            }
            .padding(.horizontal, OnboardingMetrics.gutter)
            .padding(.top, OnboardingMetrics.barTopInset)

            stagger(appeared: restoreMintsAppeared, index: 0) {
                OnboardingStepHeader(
                    title: "Add your mints.",
                    // Name the reason this step exists at all. Without it the
                    // screen reads as busywork, and the user has no way to know
                    // the seed alone can't find their money. The second
                    // sentence names both routes forward, because the backup
                    // lookup no longer runs itself.
                    subhead: "Your seed phrase doesn't record which mints you used. Find them from a backup, or add them yourself."
                )
            }
            .padding(.top, OnboardingMetrics.titleGap)

            restoreMintsList
                .padding(.top, 16)
        }
        .animation(.snappy, value: restoreMintError)
        .animation(.snappy, value: mintsToRestore.isEmpty)
        .onAppear {
            // Land calm — don't pop the keyboard on arrival (it can carry over
            // from the seed screen's crossfade).
            mintFieldFocused = false
            triggerEntrance { restoreMintsAppeared = true }
        }
    }

    private var restoreMintsList: some View {
        // Scrollable body — input + the staged mints the user has added.
        ScrollView {
            VStack(spacing: 20) {
                TextField("mint.example.com", text: $mintUrlInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .focused($mintFieldFocused)
                    .onSubmit(addMintUrl)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                HStack(spacing: 8) {
                    Button(action: addMintUrl) {
                        restoreCapsuleChip("Add", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .disabled(mintUrlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(mintUrlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)

                    Button(action: pasteMintUrlsFromClipboard) {
                        restoreCapsuleChip("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Paste mint URLs from clipboard")

                }
                .padding(.horizontal)

                // "Nostr" named the transport, not the outcome. The user
                // doesn't need to know where their mint list is kept — only
                // that we can go and look for it. It gets its own row because
                // it is the way through this step for anyone who can't recite
                // their mint URLs, which is most people; third-of-a-row next
                // to Add and Paste both buried it and truncated it.
                Button(action: searchMintBackup) {
                    mintLookupChip
                }
                .buttonStyle(.plain)
                // Hit testing, not `.disabled`: a disabled plain Button dims its
                // whole label, glass included, so the pill washed out from
                // 221 to 237 and the spinner sat in a greyed-out capsule looking
                // broken rather than busy. The spinner is the busy signal; the
                // chip should stay at full strength behind it. Re-entry is
                // refused in `searchMintBackup` itself, so this is presentation
                // only.
                .allowsHitTesting(!nostrBackupService.isSearching)
                // No `accessibilityLabel` override — it used to read "Check for
                // a backup of your mint list", which is not what the button
                // says. Voice Control matches spoken words against the label,
                // so "tap Find my mints" missed the one control that is now the
                // way through this step. The visible text is the label; the
                // explanation belongs in the hint.
                .accessibilityHint("Checks your relays for a backup of your mint list")
                .padding(.horizontal)

                // Staged mints — the list that gets restored. Each shows its host.
                if !mintsToRestore.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(mintsToRestore.enumerated()), id: \.element) { index, url in
                            stagedMintRow(url: url)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // The list is empty far more often than not, and the
                    // disabled primary never says why. This is the only place
                    // that explains the wait and the way out.
                    Text(emptyMintListNotice)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                // Mint-list notice (success / advisory / error)
                if let error = restoreMintError {
                    InlineNotice(message: error, severity: restoreMintSeverity)
                        .padding(.horizontal)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 8)
            // Bottom clearance equal to the fade band, so scrolling to the end
            // parks the last row clear of the gradient instead of leaving it
            // permanently dimmed.
            .padding(.bottom, ScrollFadeMetrics.band)
        }
        .scrollDismissesKeyboard(.interactively)
        // Zero inset, not a chassis-height one: `safeAreaInset` on the root
        // *reduces* the region the stage lays out in, so this ScrollView's own
        // bottom edge already sits at the chassis top and nothing runs
        // underneath. Insetting by the chassis floated the band a chassis-height
        // up the screen, which is what shipped and looked broken. No top fade:
        // the whole stage scrolls as one unit, so the first thing in the
        // container is the URL field, and a top mask would dim it at rest.
        .scrollEdgeFade(bottom: 0)
        // Tap anywhere off the field dismisses the keyboard. Guarded so the
        // first tap that focuses the field isn't immediately revoked.
        .simultaneousGesture(
            TapGesture().onEnded {
                if mintFieldFocused { mintFieldFocused = false }
            }
        )
    }

    /// Inline Liquid-Glass capsule chip (Add / Paste) for the restore flow.
    /// Non-interactive glass so taps land on the plain Button label; falls back
    /// to `.quaternary` below iOS 26.
    private func restoreCapsuleChip(_ title: String, systemImage: String) -> some View {
        restoreChipLabel(title) { Image(systemName: systemImage) }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .liquidGlass(in: Capsule())
            .contentShape(Capsule())
    }

    /// A chip's inner label, without the glass. Kept as a `Label` (rather than a
    /// hand-rolled HStack) so a chip with a custom glyph lays out identically to
    /// the plain `systemImage` ones — same icon/title spacing, same Dynamic Type
    /// behaviour. The glyph box is fixed so swapping the symbol for a spinner
    /// can't change the chip's height.
    private func restoreChipLabel<Glyph: View>(
        _ title: String,
        @ViewBuilder glyph: () -> Glyph
    ) -> some View {
        Label {
            Text(title)
        } icon: {
            glyph().frame(width: 16, height: 16)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
    }

    /// The backup-lookup chip, which is the way through this step and therefore
    /// the one chip that has a working state.
    ///
    /// Both states are always mounted and cross-faded, rather than one `Label`
    /// whose title and icon change. That is not a stylistic choice: the stage
    /// carries `.animation(.snappy, value: mintsToRestore.isEmpty)`, so the
    /// moment a lookup stages its mints the whole subtree animates — and a
    /// single `Label` reverting to a shorter title re-centres its row, which
    /// dragged the magnifying glass across the chip. With both states resident
    /// the chip's geometry is constant, so that blanket animation has nothing
    /// to slide and only the opacity moves.
    private var mintLookupChip: some View {
        let searching = nostrBackupService.isSearching
        return ZStack {
            restoreChipLabel("Find my mints") {
                Image(systemName: "magnifyingglass")
            }
            .opacity(searching ? 0 : 1)

            restoreChipLabel("Checking for your mints…") {
                // The system spinner, at the size Apple uses inline in a
                // control. No dimming behind it — a button showing a spinner is
                // already saying it is busy, and a 40% spinner just looks broken.
                ProgressView().controlSize(.small)
            }
            .opacity(searching ? 1 : 0)
        }
        .animation(.smooth(duration: 0.2), value: searching)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .liquidGlass(in: Capsule())
        .contentShape(Capsule())
        // One glass capsule around both states. Two stacked chips would double
        // the glass wherever they overlap mid-fade.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(searching ? "Checking for your mints" : "Find my mints")
    }

    // MARK: - Staged Mint Row (add screen)

    private func stagedMintRow(url: String) -> some View {
        HStack(spacing: 12) {
            MintAvatarView(iconUrl: stagedMintIconUrls[url], name: stagedMintNames[url] ?? shortenUrl(url))

            VStack(alignment: .leading, spacing: 2) {
                Text(stagedMintNames[url] ?? shortenUrl(url))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(url)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { mintsToRestore.removeAll { $0 == url } }) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Remove mint")
            .accessibilityHint("Removes this mint before restoring")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Restore Progress / Results (forward-only)

    private var restoreTotalRecovered: UInt64 {
        restorePhases.values.reduce(UInt64(0)) { acc, phase in
            if case .recovered(let result) = phase { return acc + result.unspent }
            return acc
        }
    }

    private var restoreAllSettled: Bool {
        restorePhases.values.allSatisfy { phase in
            switch phase {
            case .recovered, .failed: return true
            case .pending, .restoring: return false
            }
        }
    }

    /// First mint currently restoring — used to keep it scrolled into view.
    private var currentRestoringUrl: String? {
        restoringMints.first { url in
            if case .restoring = restorePhases[url] { return true }
            return false
        }
    }

    private var restoreSubhead: String {
        if !restoreAllSettled { return "Checking your mints…" }
        if restoreTotalRecovered > 0 { return "Here's what we restored." }
        // Zero back is the outcome the user fears most. Name the one cause
        // they can still act on instead of leaving them to guess.
        return "No funds on these mints. If you used others, go back and add them."
    }

    private var restoreProgressStage: some View {
        VStack(spacing: 0) {
            stagger(appeared: restoreProgressAppeared, index: 0) {
                OnboardingStepHeader(
                    title: "Restoring wallet.",
                    subhead: restoreSubhead
                )
            }
            .padding(.top, OnboardingMetrics.titleTopInset)
            .padding(.bottom, 12)

            // The recovered total is a money value — it keeps its monospaced
            // digits and numeric content transition (Numbers Are Sacred).
            if restoreTotalRecovered > 0 {
                Label("Recovered: \(restoreTotalRecovered) sats", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    .contentTransition(.numericText(value: Double(restoreTotalRecovered)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(restoringMints, id: \.self) { url in
                            restoreProgressRow(url: url, phase: restorePhases[url] ?? .pending)
                                .id(url)
                        }
                    }
                    .padding(.horizontal)
                    // Clearance equal to the fade band at both ends. A static
                    // edge mask can't tell "scrolled past" from "this is the
                    // end", so without this the first and last rows sit inside
                    // the gradient and render dimmed at rest — which is a
                    // defect, not a hint. Padded, the extremes park clear of
                    // the band and only genuinely-clipped rows dissolve.
                    .padding(.vertical, ScrollFadeMetrics.band)
                }
                .onChange(of: currentRestoringUrl) { _, active in
                    guard let active else { return }
                    withAnimation(.snappy) { proxy.scrollTo(active, anchor: .center) }
                }
                // Both edges here, unlike the staging step: this list
                // auto-scrolls to whichever mint is working, so rows cross both
                // boundaries unattended. The recovered-total line is pinned
                // above and the chassis below, and rows were cutting dead
                // against each.
                .scrollEdgeFade(top: 0, bottom: 0)
            }
        }
        .padding(.top, 8)
        .animation(.snappy, value: restoreTotalRecovered)
        .animation(.snappy, value: restoreAllSettled)
        .onAppear {
            triggerEntrance { restoreProgressAppeared = true }
        }
    }

    private func restoreProgressRow(url: String, phase: MintRestorePhase) -> some View {
        let recovered: RestoreMintResult? = {
            if case .recovered(let result) = phase { return result }
            return nil
        }()

        return HStack(spacing: 12) {
            MintAvatarView(
                iconUrl: recovered?.iconUrl ?? stagedMintIconUrls[url],
                name: recovered?.mintName ?? stagedMintNames[url] ?? shortenUrl(url)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(recovered?.mintName ?? stagedMintNames[url] ?? shortenUrl(url))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if case .failed(let message) = phase {
                    InlineNotice(message: message, severity: .error)
                } else {
                    Text(url)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            switch phase {
            case .pending, .restoring:
                ProgressView()
                    .controlSize(.small)
            case .recovered(let result):
                HStack(spacing: 6) {
                    Image(systemName: result.totalRecovered > 0 ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(result.totalRecovered > 0 ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                    Text("\(result.unspent) sats")
                        .font(.subheadline)
                        .fontWeight(result.unspent > 0 ? .semibold : .regular)
                        .monospacedDigit()
                        .foregroundStyle(result.unspent > 0 ? .primary : .secondary)
                }
            case .failed:
                Button("Retry") { retry(url) }
                    .textLinkButton()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func shortenUrl(_ url: String) -> String {
        var shortened = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if shortened.hasSuffix("/") {
            shortened = String(shortened.dropLast())
        }
        return shortened
    }

    // MARK: - Actions

    private func createWallet() {
        // An interrupted onboarding may have already created and persisted a
        // wallet. Never regenerate its seed — the user may have written those
        // words down. Re-show the existing phrase instead.
        if walletManager.mnemonic != nil {
            advance(to: .showMnemonic)
            return
        }

        isCreating = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await walletManager.createNewWallet()
                advance(to: .showMnemonic)
            } catch {
                errorMessage = "Couldn't create the wallet. \(error.userFacingWalletMessage)"
                AppLogger.wallet.error("Create wallet error: \(error)")
            }
            isCreating = false
        }
    }

    private func initializeAndProceed() {
        // Already normalised: every word was committed from the wordlist.
        let cleanedMnemonic = seedEntry.phrase

        guard walletManager.validateMnemonic(cleanedMnemonic) else {
            // Not a banner — a checksum failure is fixable, and the review grid
            // is where it gets fixed.
            runSeedChecksum()
            return
        }

        isRestoring = true
        errorMessage = nil

        Task {
            do {
                try await walletManager.initializeRestoredWallet(mnemonic: cleanedMnemonic)
                advance(to: .restoreMints)
            } catch {
                errorMessage = "Couldn't restore the wallet. \(error.userFacingWalletMessage)"
            }
            isRestoring = false
        }
    }

    private func addMintUrl() {
        if addMintUrlToRestoreList(mintUrlInput, showDuplicateError: true, showValidationError: true) {
            mintUrlInput = ""
            mintFieldFocused = false
            HapticFeedback.selection()
        }
    }

    private func pasteMintUrlsFromClipboard() {
        guard let clipboardContent = UIPasteboard.general.string else {
            setRestoreMintNotice("Clipboard is empty.")
            return
        }

        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        let candidates = clipboardContent
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        var addedCount = 0
        var invalidCount = 0
        for candidate in candidates {
            guard let normalized = normalizedMintURL(from: candidate) else {
                invalidCount += 1
                continue
            }
            if addMintUrlToRestoreList(normalized, showDuplicateError: false, showValidationError: false) {
                addedCount += 1
            }
        }

        if addedCount == 0 {
            setRestoreMintNotice(invalidCount > 0 ? "Nothing in the clipboard looked like a mint URL." : "No new mints to add.")
        } else if invalidCount > 0 {
            setRestoreMintNotice("Added \(addedCount) mint\(addedCount == 1 ? "" : "s"). Skipped \(invalidCount) that didn't look like a mint URL.")
        } else {
            restoreMintError = nil
        }
    }

    /// Look up the encrypted mint-list backup for this seed on the user's
    /// relays (NUT-27, fetched by cdk) and stage every mint it contains.
    ///
    /// Only ever runs from an explicit tap. It used to fire on arrival, on the
    /// grounds that publishing is on by default so most people have a list
    /// waiting — but the step opens by telling the user their seed phrase
    /// doesn't record which mints they used, and then a dozen of their mints
    /// appeared anyway. The user has no way to see the lookup happen, so the
    /// screen read as contradicting itself, or as the wallet knowing more about
    /// them than they agreed to. The lookup is still one tap away; the tap is
    /// now theirs, which is what makes the result explicable.
    private func searchMintBackup() {
        // The chip stops taking taps while a lookup is in flight, but that is a
        // view-layer courtesy; refuse re-entry here so a second call can never
        // double-stage the same backup.
        guard !nostrBackupService.isSearching else { return }
        HapticFeedback.selection()

        Task { @MainActor in
            do {
                let urls = try await nostrBackupService.fetchBackedUpMintURLs()
                var addedCount = 0
                for url in urls where addMintUrlToRestoreList(url, showDuplicateError: false, showValidationError: false) {
                    addedCount += 1
                }
                if addedCount > 0 {
                    setRestoreMintNotice("Added \(addedCount) mint\(addedCount == 1 ? "" : "s") from your backup.")
                } else if urls.isEmpty {
                    // When the list is empty the empty-state line is on screen
                    // already saying this — speak here only when it isn't.
                    if !mintsToRestore.isEmpty {
                        setRestoreMintNotice("No backup of your mint list found.", severity: .caution)
                    }
                } else {
                    setRestoreMintNotice("Backup found. Its mints are already in the list.")
                }
                mintBackupSearchCompleted = true
            } catch {
                mintBackupSearchCompleted = true
                AppLogger.wallet.error("Mint backup lookup failed: \(error)")
                // Through the shared mapper, never `localizedDescription` —
                // a relay failure here surfaced as a raw CDK FFI dump.
                setRestoreMintNotice(error.userFacingWalletMessage, severity: .error)
            }
        }
    }

    /// Fills the blank where the staged list will go. It has three jobs: say
    /// the wallet is looking, say what turned up, and name the manual route
    /// when nothing did.
    ///
    /// The landing line carries the most weight now that the lookup is manual:
    /// it is where everyone arrives, so it names the button rather than
    /// describing the situation. Android twin: `RestoreMintsEmpty*` in
    /// `RestoreWalletFlow.kt`.
    private var emptyMintListNotice: String {
        if nostrBackupService.isSearching {
            return "Checking for a backup of your mint list…"
        }
        if mintBackupSearchCompleted {
            return "No backup found. Add the mints you used before, then restore."
        }
        return "Tap Find my mints to look for a backup of your mint list, or add them above."
    }

    @discardableResult
    private func addMintUrlToRestoreList(_ rawUrl: String, showDuplicateError: Bool, showValidationError: Bool) -> Bool {
        guard let url = normalizedMintURL(from: rawUrl) else {
            if showValidationError {
                setRestoreMintNotice("That doesn't look like a mint URL.", severity: .caution)
            }
            return false
        }

        guard !mintsToRestore.contains(url) else {
            if showDuplicateError {
                setRestoreMintNotice("This mint is already in the list.", severity: .caution)
            }
            return false
        }

        mintsToRestore.append(url)
        restoreMintError = nil
        fetchStagedMintInfo(url)
        return true
    }

    /// Pull the mint's name + logo through CDK so the staged row shows the
    /// mint's own profile pic. Best-effort failures leave the monogram fallback
    /// in place.
    private func fetchStagedMintInfo(_ url: String) {
        guard stagedMintIconUrls[url] == nil, stagedMintNames[url] == nil else { return }
        Task { @MainActor in
            guard let info = await walletManager.fetchMintPreviewInfo(url: url) else { return }
            if let icon = info.iconUrl, !icon.isEmpty { stagedMintIconUrls[url] = icon }
            if let name = info.name, !name.isEmpty { stagedMintNames[url] = name }
        }
    }

    private func normalizedMintURL(from rawUrl: String) -> String? {
        var url = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }

        url = url.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }

        if url.hasSuffix("/") {
            url = String(url.dropLast())
        }

        guard let parsed = URL(string: url), parsed.host != nil else { return nil }
        return url
    }

    /// Snapshot the staged mints and move to the dedicated restore screen, which
    /// runs the recovery and shows per-mint progress + results.
    private func startRestoreFlow() {
        mintFieldFocused = false
        restoringMints = mintsToRestore
        restorePhases = Dictionary(uniqueKeysWithValues: mintsToRestore.map { ($0, .pending) })
        advance(to: .restoreProgress)
        runRestore()
    }

    private func runRestore() {
        Task { @MainActor in
            for url in restoringMints {
                if case .recovered = restorePhases[url] { continue }   // keep successes on retry-all
                withAnimation(.snappy) { restorePhases[url] = .restoring }
                do {
                    let result = try await walletManager.restoreFromMint(url: url)
                    withAnimation(.snappy) { restorePhases[url] = .recovered(result) }
                } catch {
                    withAnimation(.snappy) { restorePhases[url] = .failed(error.userFacingWalletMessage) }
                    AppLogger.wallet.error("Restore error for \(url): \(error)")
                }
            }
        }
    }

    private func retry(_ url: String) {
        Task { @MainActor in
            withAnimation(.snappy) { restorePhases[url] = .restoring }
            do {
                let result = try await walletManager.restoreFromMint(url: url)
                withAnimation(.snappy) { restorePhases[url] = .recovered(result) }
            } catch {
                withAnimation(.snappy) { restorePhases[url] = .failed(error.userFacingWalletMessage) }
                AppLogger.wallet.error("Retry restore error for \(url): \(error)")
            }
        }
    }

    private func finishRestore() {
        handoff.begin(reduceMotion: reduceMotion) {
            await walletManager.completeRestore()
        }
    }

    private func finishOnboarding() {
        // Onboarding complete — the handoff curtain flips the gate at full cover.
        handoff.begin(reduceMotion: reduceMotion) {
            walletManager.completeOnboarding()
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(WalletManager())
        .environmentObject(OnboardingHandoffCoordinator())
}
