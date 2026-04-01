import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var walletManager: WalletManager

    @State private var currentStep: OnboardingStep = .welcome
    @State private var restoreMnemonic = ""
    @State private var isCreating = false
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var showMnemonicWords = false

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

    enum OnboardingStep {
        case welcome
        case createOrRestore
        case showMnemonic
        case verifyMnemonic
        case restoreInput
        case restoreMints
    }

    var body: some View {
        VStack {
            switch currentStep {
            case .welcome:
                welcomeView
            case .createOrRestore:
                createOrRestoreView
            case .showMnemonic:
                showMnemonicView
            case .verifyMnemonic:
                verifyMnemonicView
            case .restoreInput:
                restoreInputView
            case .restoreMints:
                restoreMintsView
            }
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 40) {
            Spacer()

            // Logo
            VStack(spacing: 16) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.largeTitle)
.foregroundStyle(Color.accentColor)

                Text("Cashu Wallet")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Private digital cash for everyone")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Error display
            if let error = walletManager.errorMessage {
                ErrorBannerView(message: "Initialization Error: \(error)", type: .error)
                    .padding(.horizontal)
            }

            // Features
            VStack(alignment: .leading, spacing: 16) {
                Label("Privacy-first ecash", systemImage: "lock.shield")
                Label("Lightning Network payments", systemImage: "bolt.fill")
                Label("Deterministic wallet recovery", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.body)
            .padding(.horizontal, 24)

            Spacer()

            // Get Started button
            Button(action: { currentStep = .createOrRestore }) {
                Text("GET STARTED")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .padding(.bottom, 40)
        }
        .padding()
    }


    // MARK: - Create or Restore View

    private var createOrRestoreView: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Welcome to Cashu")
                .font(.title)
                .fontWeight(.bold)

            Text("Create a new wallet or restore from your seed phrase")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            // Error display
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            }

            // Create new wallet
            Button(action: createWallet) {
                if isCreating {
                    ProgressView()
                } else {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("CREATE NEW WALLET")
                    }
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(isCreating)

            // Restore wallet
            Button(action: { currentStep = .restoreInput }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle")
                    Text("RESTORE FROM SEED")
                }
            }
            .buttonStyle(.bordered).controlSize(.large)

            Spacer()

            // Back button
            Button(action: { currentStep = .welcome }) {
                Text("Back")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
        .padding()
    }

    // MARK: - Show Mnemonic View

    private var showMnemonicView: some View {
        VStack(spacing: 24) {
            Text("Your Seed Phrase")
                .font(.title2)
                .fontWeight(.bold)

            Text("Write down these 12 words in order and keep them safe. This is the only way to recover your wallet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Warning
            Label("Never share these words with anyone!", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding()

            // Mnemonic words
            let words = walletManager.getMnemonicWords()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    GroupBox {
                        HStack(spacing: 4) {
                            Text("\(index + 1).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)

                            Text(word)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .padding()

            Spacer()

            // Continue button — go to verification step
            Button(action: startVerification) {
                Text("I'VE SAVED MY SEED PHRASE")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .padding(.bottom, 40)
        }
        .padding()
    }

    // MARK: - Verify Mnemonic View

    private var verifyMnemonicView: some View {
        VStack(spacing: 24) {
            Text("Verify Seed Phrase")
                .font(.title2)
                .fontWeight(.bold)

            Text("Select the correct word for each position to confirm you saved your seed phrase.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            verificationWordsGridView(indices: verificationIndices)
            .padding()

            if let error = verificationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button(action: checkVerification) {
                Text("CONFIRM")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(verificationAnswers.count < verificationIndices.count)

            Button(action: { currentStep = .showMnemonic }) {
                Text("Go back and check")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
        .padding()
    }

    private func verificationWordsGridView(indices: [Int]) -> some View {
        let words = walletManager.getMnemonicWords()
        return VStack(spacing: 16) {
            ForEach(Array(indices.enumerated()), id: \.offset) { _, index in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Word #\(index + 1)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    let options = generateWordOptions(correctWord: words[index])
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            Button(action: {
                                verificationAnswers[index] = option
                                verificationError = nil
                            }) {
                                Text(option)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .tint(verificationAnswers[index] == option ? .accentColor : .secondary)
                        }
                    }
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
        currentStep = .verifyMnemonic
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
                verificationError = "Incorrect. Please go back and check your seed phrase."
                verificationAnswers = [:]
                return
            }
        }
        finishOnboarding()
    }

    // MARK: - Restore Input View

    private var restoreInputView: some View {
        VStack(spacing: 24) {
            Text("Restore Wallet")
                .font(.title2)
                .fontWeight(.bold)

            Text("Enter your 12-word seed phrase to restore your wallet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Mnemonic input
            GroupBox {
                TextEditor(text: $restoreMnemonic)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: 150)
            }

            // Word count
            let wordCount = restoreMnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .count

            let invalidIndices = walletManager.invalidMnemonicWords(restoreMnemonic)
            HStack(spacing: 4) {
                Text("\(wordCount) / 12 words")
                    .font(.caption)
                    .foregroundColor(wordCount == 12 ? .accentColor : .secondary)
                if wordCount > 0 && !invalidIndices.isEmpty {
                    Text("(\(invalidIndices.count) invalid)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let error = errorMessage {
                ErrorBannerView(message: error, type: .error)
                    .padding(.horizontal)
            }

            Spacer()

            // Next button - initializes wallet then goes to mint restore step
            Button(action: initializeAndProceed) {
                if isRestoring {
                    ProgressView()
                } else {
                    Text("NEXT")
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(wordCount != 12 || isRestoring)

            // Back button
            Button(action: { currentStep = .createOrRestore }) {
                Text("Back")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
        .padding()
    }

    // MARK: - Restore Mints View

    private var restoreMintsView: some View {
        VStack(spacing: 20) {
            Text("Restore Ecash")
                .font(.title2)
                .fontWeight(.bold)

            Text("Add the mint URLs you used before to recover your ecash balance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            GroupBox {
                TextField("https://mint.example.com", text: $mintUrlInput)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button(action: addMintUrl) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(mintUrlInput.isEmpty)

                Button(action: pasteMintUrlsFromClipboard) {
                    Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Paste mint URLs from clipboard")
            }
            .padding(.horizontal)

            // Mints list
            if !mintsToRestore.isEmpty || !restoreResults.isEmpty {
                ScrollView {
                    VStack(spacing: 10) {
                        // Pending mints (not yet restored)
                        ForEach(mintsToRestore, id: \.self) { mintUrl in
                            mintRow(url: mintUrl, result: nil, isRestoring: currentRestoringMint == mintUrl)
                        }

                        // Completed restore results
                        ForEach(restoreResults) { result in
                            mintRow(url: result.mintUrl, result: result, isRestoring: false)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 280)
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "building.columns")
                        .font(.title)
                        .foregroundColor(.secondary.opacity(0.5))
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

            // Restore summary
            if !restoreResults.isEmpty {
                let totalRecovered = restoreResults.reduce(UInt64(0)) { $0 + $1.unspent }
                let totalPending = restoreResults.reduce(UInt64(0)) { $0 + $1.pending }

                GroupBox {
                    VStack(spacing: 6) {
                        if totalRecovered > 0 {
                            Label("Recovered: \(totalRecovered) sats", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                        if totalPending > 0 {
                            Label("Pending: \(totalPending) sats", systemImage: "clock.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                        if totalRecovered == 0 && totalPending == 0 {
                            Label("No ecash found on these mints", systemImage: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                // Restore button
                if !mintsToRestore.isEmpty {
                    Button(action: startRestore) {
                        if isRestoringMints {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Restoring...")
                            }
                        } else {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Restore from \(mintsToRestore.count) mint\(mintsToRestore.count == 1 ? "" : "s")")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(isRestoringMints)
                }

                // Continue / Skip button
                if restoreResults.isEmpty && mintsToRestore.isEmpty {
                    Button(action: finishRestore) {
                        Text("SKIP")
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(isRestoringMints)
                } else {
                    Button(action: finishRestore) {
                        Text("CONTINUE")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(isRestoringMints)
                }
            }

            // Back button
            Button(action: {
                currentStep = .restoreInput
                mintsToRestore.removeAll()
                restoreResults.removeAll()
                restoreMintError = nil
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
        GroupBox {
            HStack(spacing: 12) {
                // Status icon
                if isRestoring {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 24, height: 24)
                } else if let result = result {
                    Image(systemName: result.totalRecovered > 0 ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundColor(result.totalRecovered > 0 ? .green : .secondary)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "building.columns")
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
                    // Remove button for pending mints
                    Button(action: {
                        mintsToRestore.removeAll { $0 == url }
                    }) {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
                currentStep = .showMnemonic
            } catch {
                errorMessage = "Failed to create wallet: \(error.localizedDescription)"
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
            errorMessage = "Invalid seed phrase. Please check your words."
            return
        }

        isRestoring = true
        errorMessage = nil

        Task {
            do {
                try await walletManager.initializeRestoredWallet(mnemonic: cleanedMnemonic)
                currentStep = .restoreMints
            } catch {
                errorMessage = "Failed to initialize wallet: \(error.localizedDescription)"
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
            restoreMintError = invalidCount > 0 ? "No valid mint URLs found in clipboard." : "No new mint URLs found in clipboard."
        } else if invalidCount > 0 {
            restoreMintError = "Added \(addedCount) mint URL\(addedCount == 1 ? "" : "s"). Skipped \(invalidCount) invalid entr\(invalidCount == 1 ? "y" : "ies")."
        } else {
            restoreMintError = nil
        }
    }

    @discardableResult
    private func addMintUrlToRestoreList(_ rawUrl: String, showDuplicateError: Bool, showValidationError: Bool) -> Bool {
        guard let url = normalizedMintURL(from: rawUrl) else {
            if showValidationError {
                restoreMintError = "Invalid mint URL."
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
                    restoreMintError = "Failed to restore from \(shortenUrl(url)): \(error.localizedDescription)"
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
