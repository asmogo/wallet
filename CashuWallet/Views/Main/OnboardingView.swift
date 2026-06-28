import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    // First-mint state (create path)
    @State private var showConceptSheet = false
    @State private var selectedMintUrls: Set<String> = []
    @State private var customMintUrls: [String] = []
    @State private var showCustomMintInput = false
    @State private var customMintInput = ""
    @State private var isAddingFirstMints = false
    @State private var currentAddingMint: String?
    @State private var firstMintError: String?

    // iCloud restore state
    @State private var detectedICloudBackup: ICloudBackupInfo? = nil
    @State private var isDetectingICloudBackup = true
    @State private var iCloudRestorePhase = ICloudRestorePhase.preview
    // Staged exit on the success screen: chrome recedes while the balance hero
    // holds, then `completeRestore()` hands off to the ContentView crossfade.
    @State private var isCompleting = false

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
                welcomeView
                    .transition(stepTransition)
            case .showMnemonic:
                showMnemonicView
                    .transition(stepTransition)
            case .firstMint:
                firstMintView
                    .transition(stepTransition)
            case .restoreMethod:
                restoreMethodView
                    .transition(stepTransition)
            case .restoreInput:
                restoreInputView
                    .transition(stepTransition)
            case .restoreMints:
                restoreMintsView
                    .transition(stepTransition)
            case .restoreProgress:
                restoreProgressView
                    .transition(stepTransition)
            case .iCloudRestore:
                iCloudRestoreView
                    .transition(stepTransition)
            }
        }
        .sheet(isPresented: $showConceptSheet) {
            conceptSheet
                .canvasSheetBackground()
        }
    }

    // Quiet crossfade between steps — no lateral slide. A horizontal push read
    // as jarring here; the per-element stagger inside each step supplies enough
    // sense of arrival. Fits the "System Utility" restraint.
    private var stepTransition: AnyTransition { .opacity }

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

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 0) {
            Spacer()

            stagger(appeared: welcomeAppeared, index: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Private cash.\nIn your pocket.")
                        .font(.largeTitle.weight(.heavy))
                        .tracking(-0.5)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("An ecash wallet for Bitcoin and Lightning.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
            }

            Spacer()

            if let error = walletManager.errorMessage {
                ErrorBannerView(message: "Couldn't start the wallet. \(error)", type: .error)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            stagger(appeared: welcomeAppeared, index: 1) {
                VStack(spacing: 12) {
                    Button(action: createWallet) {
                        Group {
                            if isCreating {
                                ProgressView().tint(.primary)
                            } else {
                                Text("Create Wallet")
                            }
                        }
                    }
                    .glassButton()
                    .disabled(isCreating)
                    .accessibilityIdentifier("onboarding-create-wallet")

                    Button(action: {
                        HapticFeedback.selection()
                        advance(to: .restoreMethod)
                    }) {
                        Text("Restore Wallet")
                    }
                    .glassButton()
                    .disabled(isCreating)

                    Button(action: {
                        HapticFeedback.selection()
                        showConceptSheet = true
                    }) {
                        Text("What is ecash?")
                            .padding(.top, 4)
                    }
                    .textLinkButton()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .animation(.snappy, value: errorMessage)
        .animation(.snappy, value: walletManager.errorMessage)
        .onAppear {
            triggerEntrance { welcomeAppeared = true }
        }
    }

    // MARK: - Concept Sheet

    private var conceptSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ecash is bearer cash\nfor Bitcoin.")
                .font(.title.weight(.heavy))
                .tracking(-0.3)
                .lineSpacing(-1)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 16) {
                Text("Whoever holds it, owns it. Your balance stays on this device, hidden from everyone else.")
                Text("Mints hold the Bitcoin behind your ecash. You can use several at once.")
                Text("Send instantly. Cash out to Lightning anytime.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: {
                HapticFeedback.selection()
                showConceptSheet = false
            }) {
                Text("Got it")
            }
            .glassButton()
            .padding(.bottom, 8)
        }
        .padding(28)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Restore Method Chooser

    private var restoreMethodView: some View {
        VStack(spacing: 0) {
            Spacer()

            stagger(appeared: restoreMethodAppeared, index: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Restore Wallet")
                        .font(.largeTitle.weight(.heavy))
                        .tracking(-0.5)
                        .foregroundStyle(.primary)

                    Text("Choose how to recover your wallet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
            }

            Spacer()

            stagger(appeared: restoreMethodAppeared, index: 1) {
                VStack(spacing: 12) {
                    Button(action: {
                        HapticFeedback.selection()
                        isDetectingICloudBackup = true
                        detectedICloudBackup = nil
                        advance(to: .iCloudRestore)
                    }) {
                        Text("Restore from iCloud")
                    }
                    .glassButton()

                    Button(action: {
                        HapticFeedback.selection()
                        advance(to: .restoreInput)
                    }) {
                        Text("Use Seed Phrase")
                    }
                    .glassButton()

                    Button(action: { retreat(to: .welcome) }) {
                        Text("Back")
                    }
                    .textLinkButton()
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            triggerEntrance { restoreMethodAppeared = true }
        }
    }

    // MARK: - iCloud Restore View

    private var iCloudRestoreView: some View {
        Group {
            switch iCloudRestorePhase {
            case .preview:
                iCloudRestorePreviewView
            case .restoring:
                iCloudRestoringView
            case .success:
                iCloudRestoreSuccessView
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

    private var iCloudRestorePreviewView: some View {
        VStack(spacing: 0) {
            Spacer()

            stagger(appeared: iCloudPreviewAppeared, index: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: iCloudPreviewIcon)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                        .contentTransition(.symbolEffect(.replace))

                    // Header reflects detection state — no longer a hardcoded
                    // "Wallet found" that contradicts a "no backup" body.
                    Text(iCloudPreviewTitle)
                        .font(.largeTitle.weight(.heavy))
                        .tracking(-0.5)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

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
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
            }

            Spacer()

            stagger(appeared: iCloudPreviewAppeared, index: 1) {
                VStack(spacing: 12) {
                    if let error = errorMessage {
                        ErrorBannerView(message: error, type: .error)
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button(action: runICloudRestore) {
                        Text("Restore Wallet")
                    }
                    .glassButton()
                    .disabled(isDetectingICloudBackup || detectedICloudBackup == nil)

                    Button(action: { retreat(to: .restoreMethod) }) {
                        Text("Back")
                    }
                    .textLinkButton()
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .animation(.snappy, value: errorMessage)
        .onAppear {
            triggerEntrance { iCloudPreviewAppeared = true }
        }
    }

    private var iCloudRestoringView: some View {
        let mintCount = detectedICloudBackup?.mintURLs.count ?? 0
        return VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: 8) {
                Text("Restoring Wallet")
                    .font(.title2.weight(.semibold))

                Text("Recovering your ecash from \(mintCount) mint\(mintCount == 1 ? "" : "s")…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var iCloudRestoreSuccessView: some View {
        // A centered terminal "done" moment: the recovered balance is the hero,
        // rendered identically to the wallet's balance so it appears to stay put
        // through the crossfade into the wallet. Everything else recedes on exit.
        let count = detectedICloudBackup?.mintURLs.count ?? 0
        return VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    // One hero gesture: the symbol bounce. Scale floor raised to
                    // 0.85 (Emil's "never below 0.9-ish") so it settles rather
                    // than pops. Reduce Motion gets a plain fade, no bounce.
                    .symbolEffect(.bounce, value: reduceMotion ? false : iCloudRestorePhase == .success)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                    .opacity(isCompleting ? 0 : 1)

                Text("Wallet Restored")
                    .font(.title.weight(.heavy))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
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

                Group {
                    if walletManager.balance > 0 && count > 0 {
                        Text("across \(count) mint\(count == 1 ? "" : "s")")
                    } else {
                        Text("Your ecash is ready.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(isCompleting ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)

            Spacer()

            Button(action: openRestoredWallet) {
                Text("Open Wallet")
            }
            .glassButton()
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(isCompleting ? 0 : 1)
        }
    }

    private func runICloudRestore() {
        guard detectedICloudBackup != nil else { return }
        iCloudRestorePhase = .restoring
        errorMessage = nil
        Task { @MainActor in
            do {
                try await walletManager.restoreFromICloudBackup()
                withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.85)) {
                    iCloudRestorePhase = .success
                }
                HapticFeedback.notification(.success)
            } catch {
                iCloudRestorePhase = .preview
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

    // MARK: - Show Mnemonic View

    private var showMnemonicView: some View {
        VStack(spacing: 0) {
            Spacer()

            stagger(appeared: mnemonicAppeared, index: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your Seed\nPhrase.")
                        .font(.largeTitle.weight(.heavy))
                        .tracking(-0.5)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Write these 12 words down in order. This is the only way to recover your wallet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Label("Never share these words with anyone", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
            }

            stagger(appeared: mnemonicAppeared, index: 1) {
                VStack(spacing: 12) {
                    // Mnemonic words — plain on canvas, blurred until revealed
                    ZStack {
                        mnemonicWordsGrid(words: walletManager.getMnemonicWords())
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
                            .accessibilityAction(.default, revealSeed)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: revealSeed)
                    .padding(.horizontal, 28)

                    Button(action: copyMnemonic) {
                        Text(seedCopied ? "Copied" : "Copy")
                            .contentTransition(.opacity)
                    }
                    .textLinkButton()
                }
                .padding(.top, 24)
            }

            Spacer()

            stagger(appeared: mnemonicAppeared, index: 2) {
                VStack(spacing: 16) {
                    Button(action: {
                        HapticFeedback.selection()
                        withAnimation(.snappy) { seedAcknowledged.toggle() }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: seedAcknowledged ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(seedAcknowledged ? Color.primary : Color.secondary)
                                .contentTransition(.symbolEffect(.replace))
                            Text("I've written down my seed phrase and stored it safely.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("onboarding-ack-seed")

                    Button(action: {
                        HapticFeedback.selection()
                        advance(to: .firstMint)
                    }) {
                        Text("I've Saved My Seed Phrase")
                    }
                    .glassButton()
                    .disabled(!seedAcknowledged)
                    .accessibilityIdentifier("onboarding-saved-seed")
                    .animation(.easeOut(duration: 0.2), value: seedAcknowledged)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            triggerEntrance { mnemonicAppeared = true }
        }
    }

    private func revealSeed() {
        guard !seedRevealed else { return }
        HapticFeedback.selection()
        withAnimation(.snappy(duration: 0.25)) {
            seedRevealed = true
        }
    }

    private func copyMnemonic() {
        UIPasteboard.general.string = walletManager.getMnemonicWords().joined(separator: " ")
        withAnimation(.snappy) { seedCopied = true }
        HapticFeedback.selection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.snappy) { seedCopied = false }
        }
    }

    private func mnemonicWordsGrid(words: [String]) -> some View {
        // Family-style: plain words on the canvas, monospaced, with the
        // number in tertiary. The seed phrase deserves quiet treatment — no
        // glass material per word, no busy backgrounds.
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

    // MARK: - First Mint View

    private var firstMintView: some View {
        VStack(spacing: 16) {
            stagger(appeared: firstMintAppeared, index: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick your\nfirst mint.")
                        .font(.largeTitle.weight(.heavy))
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Mints issue your ecash and redeem it for Bitcoin. Add more anytime in Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 8)
            }

            ScrollView {
                VStack(spacing: 0) {
                    let allRows: [String] = recommendedMints.map(\.url) + customMintUrls

                    ForEach(Array(allRows.enumerated()), id: \.element) { index, url in
                        firstMintRow(url: url)
                        if index < allRows.count - 1 {
                            CanvasDivider()
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)

                if showCustomMintInput {
                    customMintInputRow
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
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
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
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

            Spacer(minLength: 0)

            stagger(appeared: firstMintAppeared, index: 1) {
                VStack(spacing: 10) {
                    Button(action: continueFromFirstMint) {
                        Group {
                            if isAddingFirstMints {
                                ProgressView().tint(.primary)
                            } else {
                                Text("Continue")
                            }
                        }
                    }
                    .glassButton()
                    .disabled(selectedMintUrls.isEmpty || isAddingFirstMints)
                    .animation(.easeOut(duration: 0.2), value: selectedMintUrls.isEmpty)
                    .accessibilityIdentifier("onboarding-continue")

                    Button(action: skipFirstMint) {
                        Text("Skip for now")
                            .padding(.top, 2)
                    }
                    .textLinkButton()
                    .disabled(isAddingFirstMints)
                    .accessibilityIdentifier("onboarding-skip-mint")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .animation(.snappy, value: firstMintError)
        .onAppear {
            triggerEntrance { firstMintAppeared = true }
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
                MintAvatarView(iconUrl: recommended?.iconUrl, name: recommended?.name ?? shortenUrl(url))

                VStack(alignment: .leading, spacing: 2) {
                    Text(recommended?.name ?? shortenUrl(url))
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
        HStack(spacing: 10) {
            TextField("", text: $customMintInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.primary)
                .tint(.primary)
                .overlay(alignment: .leading) {
                    if customMintInput.isEmpty {
                        Text("https://mint.example.com")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                }
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
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func commitCustomMintInput() {
        if customMintInput.isEmpty {
            if let pasted = UIPasteboard.general.string {
                customMintInput = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return
        }
        guard let normalized = normalizedMintURL(from: customMintInput) else {
            firstMintError = "That doesn't look like a mint URL."
            return
        }
        if recommendedMints.contains(where: { $0.url == normalized }) || customMintUrls.contains(normalized) {
            firstMintError = "That mint is already in the list."
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
    }

    private func continueFromFirstMint() {
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
                    firstMintError = "Couldn't connect to \(shortenUrl(url)). \(error.userFacingWalletMessage)"
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

    // MARK: - Restore Input View

    private var restoreInputView: some View {
        let wordCount = restoreMnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .count
        let invalidIndices = walletManager.invalidMnemonicWords(restoreMnemonic)

        return VStack(spacing: 16) {
            stagger(appeared: restoreInputAppeared, index: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Restore\nWallet.")
                        .font(.largeTitle.weight(.heavy))
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Enter your 12 words in order.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 8)

            // Mnemonic input — same pattern as Receive Ecash paste screen
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

            HStack(spacing: 6) {
                Text("\(wordCount) / 12 words")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(wordCount == 12 && invalidIndices.isEmpty ? .green : .secondary)
                    .animation(.smooth(duration: 0.2), value: wordCount == 12 && invalidIndices.isEmpty)
                if wordCount > 0 && !invalidIndices.isEmpty {
                    Text("· \(invalidIndices.count) invalid")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let error = errorMessage {
                ErrorBannerView(message: error, type: .error)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            stagger(appeared: restoreInputAppeared, index: 1) {
                VStack(spacing: 12) {
                    Button(action: initializeAndProceed) {
                        Group {
                            if isRestoring {
                                ProgressView().tint(.primary)
                            } else {
                                Text("Next")
                            }
                        }
                    }
                    .glassButton()
                    .disabled(wordCount != 12 || isRestoring)
                    .padding(.horizontal)

                    Button(action: { retreat(to: .welcome) }) {
                        Text("Back")
                    }
                    .textLinkButton()
                    .padding(.bottom, 32)
                }
            }
        }
        .padding(.top)
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

    // MARK: - Restore Mints View

    private var restoreMintsView: some View {
        VStack(spacing: 0) {
            // Fixed header — sits at the top safe area and never scrolls under the
            // status bar, no matter how tall the list or whether the keyboard is up.
            stagger(appeared: restoreMintsAppeared, index: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recover\nYour Ecash.")
                        .font(.largeTitle.weight(.heavy))
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Add the mints you used before to recover ecash from this seed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)

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

                    // Staged mints — the list that gets restored. Each shows its host.
                    if !mintsToRestore.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(mintsToRestore.enumerated()), id: \.element) { index, url in
                                stagedMintRow(url: url)
                                if index < mintsToRestore.count - 1 {
                                    CanvasDivider()
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Error display
                    if let error = restoreMintError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
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
        // Pinned footer — one Restore CTA (enabled once a mint is staged) + Back.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: startRestoreFlow) {
                    Text(mintsToRestore.isEmpty
                         ? "Restore"
                         : "Restore from \(mintsToRestore.count) Mint\(mintsToRestore.count == 1 ? "" : "s")")
                }
                .glassButton()
                .disabled(mintsToRestore.isEmpty)
                .padding(.horizontal)

                Button(action: {
                    mintsToRestore.removeAll()
                    restoreMintError = nil
                    retreat(to: .restoreInput)
                }) {
                    Text("Back")
                }
                .textLinkButton()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(.background)
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
        if !restoreAllSettled { return "Recovering ecash from your mints…" }
        return restoreTotalRecovered > 0
            ? "Here's what we recovered."
            : "No ecash found on these mints."
    }

    private var restoreProgressView: some View {
        VStack(spacing: 0) {
            stagger(appeared: restoreProgressAppeared, index: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recover\nYour Ecash.")
                        .font(.largeTitle.weight(.heavy))
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(restoreSubhead)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if restoreTotalRecovered > 0 {
                        Label("Recovered: \(restoreTotalRecovered) sats", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                            .contentTransition(.numericText(value: Double(restoreTotalRecovered)))
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
            .animation(.snappy, value: restoreTotalRecovered)
            .animation(.snappy, value: restoreAllSettled)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(restoringMints, id: \.self) { url in
                            restoreProgressRow(url: url, phase: restorePhases[url] ?? .pending)
                                .id(url)
                            if url != restoringMints.last {
                                CanvasDivider()
                            }
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
        .safeAreaInset(edge: .bottom) {
            // Forward-only — Continue enables once every mint has settled.
            VStack(spacing: 12) {
                Button(action: finishRestore) {
                    Text("Continue")
                }
                .glassButton()
                .disabled(!restoreAllSettled)
                .padding(.horizontal)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(.background)
        }
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
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
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
            restoreMintError = "Clipboard is empty."
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
            restoreMintError = invalidCount > 0 ? "Nothing in the clipboard looked like a mint URL." : "No new mint URLs to add."
        } else if invalidCount > 0 {
            restoreMintError = "Added \(addedCount) mint URL\(addedCount == 1 ? "" : "s"). Skipped \(invalidCount) that didn't look like a mint URL."
        } else {
            restoreMintError = nil
        }
    }

    @discardableResult
    private func addMintUrlToRestoreList(_ rawUrl: String, showDuplicateError: Bool, showValidationError: Bool) -> Bool {
        guard let url = normalizedMintURL(from: rawUrl) else {
            if showValidationError {
                restoreMintError = "That doesn't look like a mint URL."
            }
            return false
        }

        guard !mintsToRestore.contains(url) else {
            if showDuplicateError {
                restoreMintError = "This mint is already in the list."
            }
            return false
        }

        mintsToRestore.append(url)
        restoreMintError = nil
        fetchStagedMintInfo(url)
        return true
    }

    /// Pull the mint's name + logo from its `/v1/info` so the staged row shows the
    /// mint's own profile pic. Best-effort and side-effect-free — failures leave
    /// the monogram fallback in place.
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
