import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var walletManager: WalletManager

    @State private var currentStep: OnboardingStep = .welcome
    @State private var restoreMnemonic = ""
    @State private var isCreating = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    // Restore mints state
    @State private var mintUrlInput = ""
    @State private var mintsToRestore: [String] = []
    @State private var restoreResults: [RestoreMintResult] = []
    @State private var isRestoringMints = false
    @State private var currentRestoringMint: String?
    @State private var restoreMintError: String?

    // Seed phrase verification state
    @State private var verificationIndices: [Int] = []
    @State private var verificationAnswers: [Int: String] = [:]
    @State private var verificationError: String?

    // First-mint state (create path)
    @State private var showConceptSheet = false
    @State private var selectedMintUrls: Set<String> = []
    @State private var customMintUrls: [String] = []
    @State private var showCustomMintInput = false
    @State private var customMintInput = ""
    @State private var isAddingFirstMints = false
    @State private var currentAddingMint: String?
    @State private var firstMintError: String?

    // Transition direction for step changes
    @State private var stepDirection: StepDirection = .forward

    enum StepDirection { case forward, backward }

    enum OnboardingStep {
        case welcome
        case showMnemonic
        case verifyMnemonic
        case firstMint
        case restoreInput
        case restoreMints
    }

    private struct RecommendedMint: Identifiable {
        let name: String
        let url: String
        var id: String { url }
    }

    private let recommendedMints: [RecommendedMint] = [
        RecommendedMint(name: "Minibits", url: "https://mint.minibits.cash/Bitcoin"),
        RecommendedMint(name: "Coinos", url: "https://mint.coinos.io"),
        RecommendedMint(name: "Macadamia", url: "https://mint.macadamia.cash")
    ]

    var body: some View {
        ZStack {
            switch currentStep {
            case .welcome:
                welcomeView
                    .transition(stepTransition)
            case .showMnemonic:
                showMnemonicView
                    .transition(stepTransition)
            case .verifyMnemonic:
                verifyMnemonicView
                    .transition(stepTransition)
            case .firstMint:
                firstMintView
                    .transition(stepTransition)
            case .restoreInput:
                restoreInputView
                    .transition(stepTransition)
            case .restoreMints:
                restoreMintsView
                    .transition(stepTransition)
            }
        }
        .sheet(isPresented: $showConceptSheet) {
            conceptSheet
        }
    }

    private var stepTransition: AnyTransition {
        let forward = AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
        let backward = AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .leading)),
            removal: .opacity.combined(with: .move(edge: .trailing))
        )
        return stepDirection == .forward ? forward : backward
    }

    private func advance(to step: OnboardingStep) {
        withAnimation(.snappy(duration: 0.35)) {
            stepDirection = .forward
            currentStep = step
        }
    }

    private func retreat(to step: OnboardingStep) {
        withAnimation(.snappy(duration: 0.35)) {
            stepDirection = .backward
            currentStep = step
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Text("CASHU")
                    .font(.caption2.weight(.semibold))
                    .tracking(3)
                    .foregroundStyle(.secondary)

                Text("Private cash.\nIn your pocket.")
                    .font(.largeTitle.weight(.heavy))
                    .tracking(-0.5)
                    .lineSpacing(-2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("An ecash wallet for Bitcoin and Lightning.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

            Spacer()

            if let error = walletManager.errorMessage {
                ErrorBannerView(message: "Couldn't start the wallet. \(error)", type: .error)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

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

                Button(action: {
                    HapticFeedback.selection()
                    advance(to: .restoreInput)
                }) {
                    Text("I have a seed phrase")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(isCreating)

                Button(action: {
                    HapticFeedback.selection()
                    showConceptSheet = true
                }) {
                    Text("What is ecash?")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
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

    // MARK: - Show Mnemonic View

    private var showMnemonicView: some View {
        VStack(spacing: 24) {
            Text("Your Seed Phrase")
                .font(.title.weight(.semibold))

            Text("Write these 12 words down in order. This is the only way to recover your wallet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Label("Never share these words with anyone", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.top, 4)

            // Mnemonic words — plain on canvas, no per-word material
            mnemonicWordsGrid(words: walletManager.getMnemonicWords())
                .padding(.horizontal)
                .padding(.top, 8)

            Spacer()

            Button(action: {
                HapticFeedback.selection()
                startVerification()
            }) {
                Text("I've Saved My Seed Phrase")
            }
            .glassButton()
            .padding(.bottom, 40)
        }
        .padding()
    }

    // MARK: - Verify Mnemonic View

    private var verifyMnemonicView: some View {
        VStack(spacing: 24) {
            Text("Verify Seed Phrase")
                .font(.title.weight(.semibold))

            Text("Tap the right word for each position.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            verificationWordsGridView(indices: verificationIndices)
                .padding(.horizontal)
                .padding(.top, 8)

            if let error = verificationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            Spacer()

            Button(action: {
                HapticFeedback.selection()
                checkVerification()
            }) {
                Text("Confirm")
            }
            .glassButton()
            .disabled(verificationAnswers.count < verificationIndices.count)
            .animation(.easeOut(duration: 0.2), value: verificationAnswers.count)

            Button(action: { retreat(to: .showMnemonic) }) {
                Text("Go back and check")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
        .padding()
    }

    private func verificationWordsGridView(indices: [Int]) -> some View {
        let words = walletManager.getMnemonicWords()
        return VStack(spacing: 20) {
            ForEach(Array(indices.enumerated()), id: \.offset) { _, index in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Word \(String(format: "#%02d", index + 1))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)

                    let options = generateWordOptions(correctWord: words[index])
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            verificationChip(option: option, index: index)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func verificationChip(option: String, index: Int) -> some View {
        let selected = verificationAnswers[index] == option
        Button(action: {
            HapticFeedback.selection()
            withAnimation(.snappy) {
                verificationAnswers[index] = option
                verificationError = nil
            }
        }) {
            Text(option)
                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(selected ? Color.secondary.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.primary.opacity(0.4) : Color.secondary.opacity(0.25),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
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

    private func startVerification() {
        let words = walletManager.getMnemonicWords()
        guard words.count >= 3 else { return }
        // Pick 3 random non-overlapping indices
        var indices = Array(0..<words.count)
        indices.shuffle()
        verificationIndices = Array(indices.prefix(3)).sorted()
        verificationAnswers = [:]
        verificationError = nil
        advance(to: .verifyMnemonic)
    }

    private func generateWordOptions(correctWord: String) -> [String] {
        let words = walletManager.getMnemonicWords()
        var options: Set<String> = [correctWord]
        // Add random wrong words from the mnemonic (different from correct)
        let otherWords = words.filter { $0 != correctWord }
        for word in otherWords.shuffled() where options.count < 3 {
            options.insert(word)
        }
        // If not enough from mnemonic, add from BIP39 list
        let sampleWords = ["abandon", "ability", "about", "abstract", "access", "account",
                           "achieve", "adapt", "affair", "agent", "alarm", "anchor"]
        for word in sampleWords.shuffled() where options.count < 3 {
            if !words.contains(word) {
                options.insert(word)
            }
        }
        return Array(options).shuffled()
    }

    private func checkVerification() {
        let words = walletManager.getMnemonicWords()
        for index in verificationIndices {
            if verificationAnswers[index] != words[index] {
                verificationError = "That's not right. Go back and check your seed phrase."
                verificationAnswers = [:]
                return
            }
        }
        HapticFeedback.notification(.success)
        advance(to: .firstMint)
    }

    // MARK: - First Mint View

    private var firstMintView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick your first mint")
                    .font(.title.weight(.semibold))

                Text("Mints issue your ecash and redeem it for Bitcoin. Add more anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 8)

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
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }

                if let error = firstMintError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
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

                Button(action: skipFirstMint) {
                    Text("Skip for now")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
                .disabled(isAddingFirstMints)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommended?.name ?? shortenUrl(url))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(url)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? .primary : Color.primary.opacity(0.25))
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var customMintInputRow: some View {
        HStack(spacing: 8) {
            TextField("https://mint.example.com", text: $customMintInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(.subheadline, design: .monospaced))
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button(action: commitCustomMintInput) {
                Image(systemName: customMintInput.isEmpty ? "doc.on.clipboard" : "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(customMintInput.isEmpty ? "Paste from clipboard" : "Add mint")
            .accessibilityHint(customMintInput.isEmpty ? "Pastes mint URL from clipboard" : "Adds mint to restore list")
        }
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
                    firstMintError = "Couldn't connect to \(shortenUrl(url)). \(error.localizedDescription)"
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
            VStack(spacing: 6) {
                Text("Restore Wallet")
                    .font(.title.weight(.semibold))

                Text("Enter your 12 words in order.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
                if wordCount > 0 && !invalidIndices.isEmpty {
                    Text("· \(invalidIndices.count) invalid")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let error = errorMessage {
                ErrorBannerView(message: error, type: .error)
                    .padding(.horizontal)
            }

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
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 32)
        }
        .padding(.top)
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
        VStack(spacing: 20) {
            Text("Restore Ecash")
                .font(.title2)
                .fontWeight(.bold)

            Text("Add the mints you used before to recover your ecash.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            GroupBox {
                TextField("https://mint.example.com", text: $mintUrlInput)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
            .padding(.horizontal)

            HStack(spacing: 8) {
                Button(action: addMintUrl) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.thinMaterial, in: Capsule())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(mintUrlInput.isEmpty)
                .opacity(mintUrlInput.isEmpty ? 0.4 : 1)

                Button(action: pasteMintUrlsFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.thinMaterial, in: Capsule())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste mint URLs from clipboard")
            }
            .padding(.horizontal)

            // Mints list — rows on canvas with hairline dividers between
            if !mintsToRestore.isEmpty || !restoreResults.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        let allItems: [(url: String, result: RestoreMintResult?)] =
                            mintsToRestore.map { ($0, nil) }
                            + restoreResults.map { ($0.mintUrl, $0) }

                        ForEach(Array(allItems.enumerated()), id: \.offset) { index, item in
                            mintRow(
                                url: item.url,
                                result: item.result,
                                isRestoring: item.result == nil && currentRestoringMint == item.url
                            )
                            if index < allItems.count - 1 {
                                CanvasDivider()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 280)
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "bitcoinsign.bank.building")
                        .font(.title)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No mints added yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }

            // Error display
            if let error = restoreMintError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Restore summary — plain on canvas, no glass
            if !restoreResults.isEmpty {
                let totalRecovered = restoreResults.reduce(UInt64(0)) { $0 + $1.unspent }
                let totalPending = restoreResults.reduce(UInt64(0)) { $0 + $1.pending }

                VStack(spacing: 8) {
                    if totalRecovered > 0 {
                        Label("Recovered: \(totalRecovered) sats", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                            .contentTransition(.numericText(value: Double(totalRecovered)))
                    }
                    if totalPending > 0 {
                        Label("Pending: \(totalPending) sats", systemImage: "clock")
                            .symbolEffect(.pulse, options: .repeating)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    if totalRecovered == 0 && totalPending == 0 {
                        Label("No ecash to recover from these mints.", systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }

            Spacer()

            VStack(spacing: 10) {
                // Restore button (secondary capsule when mints are pending)
                if !mintsToRestore.isEmpty {
                    Button(action: startRestore) {
                        Group {
                            if isRestoringMints {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Restoring...")
                                }
                            } else {
                                Label("Restore from \(mintsToRestore.count) mint\(mintsToRestore.count == 1 ? "" : "s")",
                                      systemImage: "arrow.counterclockwise")
                            }
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestoringMints)
                    .padding(.horizontal)
                }

                // Continue / Skip button
                Button(action: finishRestore) {
                    Text(restoreResults.isEmpty && mintsToRestore.isEmpty ? "Skip" : "Continue")
                }
                .glassButton()
                .disabled(isRestoringMints)
                .padding(.horizontal)
            }

            // Back button
            Button(action: {
                mintsToRestore.removeAll()
                restoreResults.removeAll()
                restoreMintError = nil
                retreat(to: .restoreInput)
            }) {
                Text("Back")
                    .foregroundStyle(.secondary)
            }
            .disabled(isRestoringMints)
            .padding(.bottom, 20)
        }
        .padding(.top)
    }

    // MARK: - Mint Row

    private func mintRow(url: String, result: RestoreMintResult?, isRestoring: Bool) -> some View {
        HStack(spacing: 12) {
                // Status icon
                if isRestoring {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 24, height: 24)
                } else if let result = result {
                    Image(systemName: result.totalRecovered > 0 ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(result.totalRecovered > 0 ? .green : .secondary)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "bitcoinsign.bank.building")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }

                // Mint info
                VStack(alignment: .leading, spacing: 2) {
                    Text(result?.mintName ?? shortenUrl(url))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(url)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Amount or pending status
                if let result = result {
                    if result.unspent > 0 {
                        Text("\(result.unspent) sats")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    } else {
                        Text("0 sats")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if !isRestoring {
                    Button(action: {
                        mintsToRestore.removeAll { $0 == url }
                    }) {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Remove mint")
                    .accessibilityHint("Skips this mint during restore")
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
                errorMessage = "Couldn't create the wallet. \(error.localizedDescription)"
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
                errorMessage = "Couldn't open the wallet. \(error.localizedDescription)"
            }
            isRestoring = false
        }
    }

    private func addMintUrl() {
        if addMintUrlToRestoreList(mintUrlInput, showDuplicateError: true, showValidationError: true) {
            mintUrlInput = ""
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

        guard !mintsToRestore.contains(url),
              !restoreResults.contains(where: { $0.mintUrl == url }) else {
            if showDuplicateError {
                restoreMintError = "This mint is already in the list."
            }
            return false
        }

        mintsToRestore.append(url)
        restoreMintError = nil
        return true
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

    private func startRestore() {
        isRestoringMints = true
        restoreMintError = nil

        Task {
            let urls = mintsToRestore
            for url in urls {
                currentRestoringMint = url
                do {
                    let result = try await walletManager.restoreFromMint(url: url)
                    restoreResults.append(result)
                    mintsToRestore.removeAll { $0 == url }
                } catch {
                    restoreMintError = "Couldn't reach \(shortenUrl(url)). \(error.localizedDescription)"
                    AppLogger.wallet.error("Restore error for \(url): \(error)")
                }
            }
            currentRestoringMint = nil
            isRestoringMints = false
        }
    }

    private func finishRestore() {
        Task {
            await walletManager.completeRestore()
        }
    }

    private func finishOnboarding() {
        // Onboarding complete - wallet is ready
        walletManager.needsOnboarding = false
    }
}

#Preview {
    OnboardingView()
        .environmentObject(WalletManager())
}
