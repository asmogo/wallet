import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var nostrBackupService = NostrMintBackupService.shared

    @State private var currentStep: OnboardingStep = .welcome
    @State private var restoreMnemonic = ""
    @State private var isCreating = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    // Restore mints state
    @State private var mintUrlInput = ""
    @State private var mintsToRestore: [String] = []
    @State private var restoreMintError: String?
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
    // holds, then `completeRestore()` hands off to the ContentView crossfade.
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
        .onAppear {
            startAsciiFieldEntrance()
            guard walletManager.hasIncompleteICloudRestore else { return }
            currentStep = .iCloudRestore
            iCloudRestorePhase = .preview
            detectedICloudBackup = nil
            isDetectingICloudBackup = true
        }
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
                    label: "Next",
                    isLoading: isRestoring,
                    isDisabled: restoreWordCount != 12 || isRestoring,
                    action: initializeAndProceed
                )
            )

        case .restoreMints:
            return OnboardingChassisModel(
                primary: OnboardingChassisAction(
                    label: mintsToRestore.isEmpty
                        ? "Restore"
                        : "Restore from \(mintsToRestore.count) Mint\(mintsToRestore.count == 1 ? "" : "s")",
                    isDisabled: mintsToRestore.isEmpty,
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

    // MARK: - Restore Method Stage

    private var restoreMethodStage: some View {
        VStack(spacing: 0) {
            OnboardingBackButton { retreat(to: .welcome) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OnboardingMetrics.gutter)
                .padding(.top, OnboardingMetrics.barTopInset)

            stagger(appeared: restoreMethodAppeared, index: 0) {
                OnboardingStepHeader(
                    title: "Restore Wallet",
                    subhead: "Choose how to recover your wallet."
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
        case .detecting: return "Checking\niCloud…"
        case .found: return "Wallet found\nin iCloud."
        case .notFound: return "No backup\nin iCloud."
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
                                Text(backup.mintURLs.isEmpty
                                     ? "Seed backup — add mints after"
                                     : "\(backup.mintURLs.count) mint\(backup.mintURLs.count == 1 ? "" : "s")")
                            }
                        case .notFound:
                            Text("No backup found. Make sure you're signed in to the same Apple ID with iCloud Keychain enabled.")
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
                title: "Restoring Wallet",
                subhead: "Recovering your funds from \(mintCount) mint\(mintCount == 1 ? "" : "s")…"
            )
            .padding(.top, OnboardingMetrics.titleTopInset)

            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var iCloudSuccessStage: some View {
        // A centered terminal "done" moment: the recovered balance is the hero,
        // rendered identically to the wallet's balance so it appears to stay put
        // through the crossfade into the wallet. Everything else recedes on exit.
        let count = detectedICloudBackup?.mintURLs.count ?? 0
        return VStack(spacing: 16) {
            OnboardingStepHeader(
                title: "Wallet Restored",
                subhead: walletManager.balance > 0 && count > 0
                    ? "across \(count) mint\(count == 1 ? "" : "s")"
                    : "Your funds are ready."
            )
            .padding(.top, OnboardingMetrics.titleTopInset)
            .opacity(isCompleting ? 0 : 1)

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                // One hero gesture: the symbol bounce. Scale floor raised to
                // 0.85 (Emil's "never below 0.9-ish") so it settles rather
                // than pops. Reduce Motion gets a plain fade, no bounce.
                .symbolEffect(.bounce, value: reduceMotion ? false : iCloudRestorePhase == .success)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                .opacity(isCompleting ? 0 : 1)

            // Hero — echoes MainWalletView's balance treatment exactly; the
            // one element held at full opacity so it carries the handoff.
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

        // Reduce Motion: skip the staged exit entirely; ContentView still
        // crossfades (opacity is vestibular-safe).
        if reduceMotion {
            Task { @MainActor in await walletManager.completeRestore() }
            return
        }

        // Chrome recedes while the balance hero holds, a brief settle, then the
        // handoff flips `needsOnboarding` and ContentView dissolves to the wallet.
        withAnimation(.easeOut(duration: 0.22)) { isCompleting = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            await walletManager.completeRestore()
        }
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
                    title: "Your Seed Phrase.",
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

    /// Word count of the entered seed — drives the chassis' Next button.
    private var restoreWordCount: Int {
        restoreMnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .count
    }

    private var restoreInputStage: some View {
        let wordCount = restoreWordCount
        let invalidIndices = walletManager.invalidMnemonicWords(restoreMnemonic)

        // Mnemonic input — same pattern as Receive Ecash paste screen
        return VStack(spacing: 0) {
            OnboardingBackButton { retreat(to: .welcome) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OnboardingMetrics.gutter)
                .padding(.top, OnboardingMetrics.barTopInset)

            stagger(appeared: restoreInputAppeared, index: 0) {
                OnboardingStepHeader(
                    title: "Restore Wallet.",
                    subhead: "Enter your 12 words in order."
                )
            }
            .padding(.top, OnboardingMetrics.titleGap)

            ZStack(alignment: .bottomTrailing) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $restoreMnemonic)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 56)

                    if restoreMnemonic.isEmpty {
                        Text("word1 word2 word3 …")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

                Button(action: restoreMnemonic.isEmpty ? pasteMnemonicFromClipboard : { clearMnemonic() }) {
                    Image(systemName: restoreMnemonic.isEmpty ? "doc.on.clipboard" : "xmark.circle.fill")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(restoreMnemonic.isEmpty ? "Paste from clipboard" : "Clear")
                .accessibilityHint(restoreMnemonic.isEmpty ? "Pastes seed phrase from clipboard" : "Clears the entered seed phrase")
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .frame(maxHeight: .infinity)
            .padding(.horizontal)
            .padding(.top, 16)

            HStack(spacing: 6) {
                Text("\(wordCount) / 12 words")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(wordCount == 12 && invalidIndices.isEmpty ? .green : .secondary)
                    .animation(.smooth(duration: 0.2), value: wordCount == 12 && invalidIndices.isEmpty)
                if wordCount > 0 && !invalidIndices.isEmpty {
                    Text("· \(invalidIndices.count) invalid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 16)

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
        }
    }

    private func pasteMnemonicFromClipboard() {
        guard let content = UIPasteboard.general.string else { return }
        HapticFeedback.selection()
        restoreMnemonic = content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearMnemonic() {
        HapticFeedback.selection()
        restoreMnemonic = ""
        errorMessage = nil
    }

    // MARK: - Restore Mints Stage

    private var restoreMintsStage: some View {
        VStack(spacing: 0) {
            OnboardingBackButton {
                mintsToRestore.removeAll()
                restoreMintError = nil
                retreat(to: .restoreInput)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OnboardingMetrics.gutter)
            .padding(.top, OnboardingMetrics.barTopInset)

            stagger(appeared: restoreMintsAppeared, index: 0) {
                OnboardingStepHeader(
                    title: "Recover funds.",
                    subhead: "Add the mints you used before to recover funds from this seed."
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

                    Button(action: searchNostrMintBackups) {
                        restoreCapsuleChip(
                            nostrBackupService.isSearching ? "Searching…" : "Nostr",
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(nostrBackupService.isSearching)
                    .opacity(nostrBackupService.isSearching ? 0.4 : 1)
                    .accessibilityLabel("Find mints from your Nostr backup")
                }
                .padding(.horizontal)

                // Staged mints — the list that gets restored. Each shows its host.
                if !mintsToRestore.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(mintsToRestore.enumerated()), id: \.element) { index, url in
                            stagedMintRow(url: url)
                        }
                    }
                    .padding(.horizontal)
                }

                // Mint-list notice (success / advisory / error)
                if let error = restoreMintError {
                    InlineNotice(message: error, severity: restoreMintSeverity)
                        .padding(.horizontal)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
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
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .liquidGlass(in: Capsule())
            .contentShape(Capsule())
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
        if !restoreAllSettled { return "Recovering funds from your mints…" }
        return restoreTotalRecovered > 0
            ? "Here's what we recovered."
            : "No funds found on these mints."
    }

    private var restoreProgressStage: some View {
        VStack(spacing: 0) {
            stagger(appeared: restoreProgressAppeared, index: 0) {
                OnboardingStepHeader(
                    title: "Recover funds.",
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
                    .padding(.bottom, 8)
                }
                .onChange(of: currentRestoringUrl) { _, active in
                    guard let active else { return }
                    withAnimation(.snappy) { proxy.scrollTo(active, anchor: .center) }
                }
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
        let cleanedMnemonic = restoreMnemonic
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .joined(separator: " ")

        guard walletManager.validateMnemonic(cleanedMnemonic) else {
            errorMessage = "That seed phrase doesn't look right. Check the spelling and try again."
            return
        }

        isRestoring = true
        errorMessage = nil

        Task {
            do {
                try await walletManager.initializeRestoredWallet(mnemonic: cleanedMnemonic)
                advance(to: .restoreMints)
            } catch {
                errorMessage = "Couldn't open the wallet. \(error.userFacingWalletMessage)"
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
            setRestoreMintNotice(invalidCount > 0 ? "Nothing in the clipboard looked like a mint URL." : "No new mint URLs to add.")
        } else if invalidCount > 0 {
            setRestoreMintNotice("Added \(addedCount) mint URL\(addedCount == 1 ? "" : "s"). Skipped \(invalidCount) that didn't look like a mint URL.")
        } else {
            restoreMintError = nil
        }
    }

    /// Look up the encrypted mint-list backup for this seed on the user's
    /// relays (NUT-27, fetched by cdk) and stage every mint it contains.
    private func searchNostrMintBackups() {
        HapticFeedback.selection()

        Task { @MainActor in
            do {
                let urls = try await nostrBackupService.fetchBackedUpMintURLs()
                var addedCount = 0
                for url in urls where addMintUrlToRestoreList(url, showDuplicateError: false, showValidationError: false) {
                    addedCount += 1
                }
                if urls.isEmpty {
                    setRestoreMintNotice("No Nostr mint backup found on your relays.", severity: .caution)
                } else if addedCount == 0 {
                    setRestoreMintNotice("Backup found — its mints are already in the list.")
                } else {
                    setRestoreMintNotice("Added \(addedCount) mint\(addedCount == 1 ? "" : "s") from your Nostr backup.")
                }
            } catch {
                // Through the shared mapper, never `localizedDescription` —
                // a relay failure here surfaced as a raw CDK FFI dump.
                setRestoreMintNotice(error.userFacingWalletMessage, severity: .error)
            }
        }
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
        Task {
            await walletManager.completeRestore()
        }
    }

    private func finishOnboarding() {
        // Onboarding complete - wallet is ready
        walletManager.completeOnboarding()
    }
}

#Preview {
    OnboardingView()
        .environmentObject(WalletManager())
}
