import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var mintBackupService = NostrMintBackupService.shared

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

    enum OnboardingStep {
        case welcome
        case createOrRestore
        case showMnemonic
        case restoreInput
        case restoreMints
    }

    var body: some View {
        ZStack {
            Color.cashuBackground
                .ignoresSafeArea()

            VStack {
                switch currentStep {
                case .welcome:
                    welcomeView
                case .createOrRestore:
                    createOrRestoreView
                case .showMnemonic:
                    showMnemonicView
                case .restoreInput:
                    restoreInputView
                case .restoreMints:
                    restoreMintsView
                }
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
                    .font(.system(size: 80))
                    .foregroundColor(.cashuAccent)

                Text("Cashu Wallet")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Private digital cash for everyone")
                    .font(.subheadline)
                    .foregroundColor(.cashuMutedText)
            }

            Spacer()

            // Error display
            if let error = walletManager.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.cashuError)
                    Text("Initialization Error")
                        .font(.headline)
                        .foregroundColor(.cashuError)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.cashuError)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.cashuCardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
            }

            // Features
            VStack(spacing: 16) {
                featureRow(icon: "lock.shield", text: "Privacy-first ecash")
                featureRow(icon: "bolt.fill", text: "Lightning Network payments")
                featureRow(icon: "arrow.triangle.2.circlepath", text: "Deterministic wallet recovery")
            }

            Spacer()

            // Get Started button
            Button(action: { currentStep = .createOrRestore }) {
                Text("GET STARTED")
            }
            .buttonStyle(CashuPrimaryButtonStyle())
            .padding(.bottom, 40)
        }
        .padding()
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.cashuAccent)
                .frame(width: 32)

            Text(text)
                .font(.body)
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Create or Restore View

    private var createOrRestoreView: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Welcome to Cashu")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Create a new wallet or restore from your seed phrase")
                .font(.subheadline)
                .foregroundColor(.cashuMutedText)
                .multilineTextAlignment(.center)

            Spacer()

            // Error display
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuError)
                    .multilineTextAlignment(.center)
                    .padding()
            }

            // Create new wallet
            Button(action: createWallet) {
                if isCreating {
                    ProgressView()
                        .tint(.black)
                } else {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("CREATE NEW WALLET")
                    }
                }
            }
            .buttonStyle(CashuPrimaryButtonStyle())
            .disabled(isCreating)

            // Restore wallet
            Button(action: { currentStep = .restoreInput }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle")
                    Text("RESTORE FROM SEED")
                }
            }
            .buttonStyle(CashuSecondaryButtonStyle())

            Spacer()

            // Back button
            Button(action: { currentStep = .welcome }) {
                Text("Back")
                    .foregroundColor(.cashuMutedText)
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
                .foregroundColor(.white)

            Text("Write down these 12 words in order and keep them safe. This is the only way to recover your wallet.")
                .font(.subheadline)
                .foregroundColor(.cashuMutedText)
                .multilineTextAlignment(.center)

            // Warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.cashuWarning)
                Text("Never share these words with anyone!")
                    .font(.caption)
                    .foregroundColor(.cashuWarning)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cashuWarning.opacity(0.1))
            )

            // Mnemonic words
            let words = walletManager.getMnemonicWords()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 4) {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                            .frame(width: 20, alignment: .trailing)

                        Text(word)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.cashuCardBackground)
                    )
                }
            }
            .padding()

            Spacer()

            // Continue button
            Button(action: finishOnboarding) {
                Text("I'VE SAVED MY SEED PHRASE")
            }
            .buttonStyle(CashuPrimaryButtonStyle())
            .padding(.bottom, 40)
        }
        .padding()
    }

    // MARK: - Restore Input View

    private var restoreInputView: some View {
        VStack(spacing: 24) {
            Text("Restore Wallet")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Enter your 12-word seed phrase to restore your wallet")
                .font(.subheadline)
                .foregroundColor(.cashuMutedText)
                .multilineTextAlignment(.center)

            // Mnemonic input
            TextEditor(text: $restoreMnemonic)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .frame(height: 150)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cashuCardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.cashuBorder, lineWidth: 1)
                        )
                )

            // Word count
            let wordCount = restoreMnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .count

            Text("\(wordCount) / 12 words")
                .font(.caption)
                .foregroundColor(wordCount == 12 ? .cashuAccent : .cashuMutedText)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuError)
            }

            Spacer()

            // Next button - initializes wallet then goes to mint restore step
            Button(action: initializeAndProceed) {
                if isRestoring {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("NEXT")
                }
            }
            .buttonStyle(CashuPrimaryButtonStyle(isDisabled: wordCount != 12))
            .disabled(wordCount != 12 || isRestoring)

            // Back button
            Button(action: { currentStep = .createOrRestore }) {
                Text("Back")
                    .foregroundColor(.cashuMutedText)
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
                .foregroundColor(.white)

            Text("Add the mint URLs you used before to recover your ecash balance.")
                .font(.subheadline)
                .foregroundColor(.cashuMutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 10) {
                Button(action: searchNostrMintBackups) {
                    HStack(spacing: 8) {
                        if mintBackupService.isSearching {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "tray.and.arrow.down.fill")
                        }
                        Text(mintBackupService.isSearching ? "Searching Nostr backups..." : "Search Nostr mint backups")
                    }
                }
                .buttonStyle(CashuPrimaryButtonStyle())
                .disabled(mintBackupService.isSearching)

                Text("This searches a deterministic Nostr backup key derived from your seed phrase.")
                    .font(.caption2)
                    .foregroundColor(.cashuMutedText)
                    .multilineTextAlignment(.center)

                if !mintBackupService.discoveredMints.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Found on Nostr")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Spacer()
                            Button("Select all") {
                                mintBackupService.selectAllDiscovered()
                            }
                            .font(.caption)
                            .foregroundColor(.cashuAccent)
                        }

                        ForEach(mintBackupService.discoveredMints) { mint in
                            Button(action: {
                                mintBackupService.setSelected(!mint.selected, for: mint.url)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: mint.selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(mint.selected ? .cashuAccent : .cashuMutedText)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mint.url)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                        Text("Updated \(formatRelativeTime(mint.timestamp))")
                                            .font(.caption2)
                                            .foregroundColor(.cashuMutedText)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.cashuCardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: addSelectedNostrMints) {
                            Text("ADD SELECTED MINTS")
                        }
                        .buttonStyle(CashuSecondaryButtonStyle())
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.horizontal)

            // Mint URL input
            HStack(spacing: 12) {
                TextField("https://mint.example.com", text: $mintUrlInput)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.cashuCardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.cashuBorder, lineWidth: 1)
                            )
                    )

                Button(action: addMintUrl) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(mintUrlInput.isEmpty ? .cashuMutedText : .cashuAccent)
                }
                .disabled(mintUrlInput.isEmpty)
            }
            .padding(.horizontal)

            Button(action: pasteMintUrlsFromClipboard) {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                    Text("Paste mints from clipboard")
                }
                .font(.subheadline)
                .foregroundColor(.cashuMutedText)
            }
            .padding(.horizontal)
            .accessibilityLabel("Paste mint URLs from clipboard")

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
                        .font(.system(size: 40))
                        .foregroundColor(.cashuMutedText.opacity(0.5))
                    Text("No mints added yet")
                        .font(.subheadline)
                        .foregroundColor(.cashuMutedText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }

            // Error display
            if let error = restoreMintError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Restore summary
            if !restoreResults.isEmpty {
                let totalRecovered = restoreResults.reduce(UInt64(0)) { $0 + $1.unspent }
                let totalPending = restoreResults.reduce(UInt64(0)) { $0 + $1.pending }

                VStack(spacing: 6) {
                    if totalRecovered > 0 {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.cashuSuccess)
                            Text("Recovered: \(totalRecovered) sats")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.cashuSuccess)
                        }
                    }
                    if totalPending > 0 {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.cashuWarning)
                            Text("Pending: \(totalPending) sats")
                                .font(.subheadline)
                                .foregroundColor(.cashuWarning)
                        }
                    }
                    if totalRecovered == 0 && totalPending == 0 {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.cashuMutedText)
                            Text("No ecash found on these mints")
                                .font(.subheadline)
                                .foregroundColor(.cashuMutedText)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cashuCardBackground)
                )
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
                                    .tint(.black)
                                Text("Restoring...")
                                    .foregroundColor(.black)
                            }
                        } else {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("RESTORE FROM \(mintsToRestore.count) MINT\(mintsToRestore.count == 1 ? "" : "S")")
                            }
                        }
                    }
                    .buttonStyle(CashuPrimaryButtonStyle())
                    .disabled(isRestoringMints)
                }

                // Continue / Skip button
                if restoreResults.isEmpty && mintsToRestore.isEmpty {
                    Button(action: finishRestore) {
                        Text("SKIP")
                    }
                    .buttonStyle(CashuSecondaryButtonStyle())
                    .disabled(isRestoringMints)
                } else {
                    Button(action: finishRestore) {
                        Text("CONTINUE")
                    }
                    .buttonStyle(CashuPrimaryButtonStyle())
                    .disabled(isRestoringMints)
                }
            }

            // Back button
            Button(action: {
                currentStep = .restoreInput
                mintsToRestore.removeAll()
                restoreResults.removeAll()
                restoreMintError = nil
                mintBackupService.clearDiscovered()
            }) {
                Text("Back")
                    .foregroundColor(.cashuMutedText)
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
                    .foregroundColor(result.totalRecovered > 0 ? .cashuSuccess : .cashuMutedText)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "building.columns")
                    .foregroundColor(.cashuMutedText)
                    .frame(width: 24, height: 24)
            }

            // Mint info
            VStack(alignment: .leading, spacing: 2) {
                Text(result?.mintName ?? shortenUrl(url))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(url)
                    .font(.caption2)
                    .foregroundColor(.cashuMutedText)
                    .lineLimit(1)
            }

            Spacer()

            // Amount or pending status
            if let result = result {
                if result.unspent > 0 {
                    Text("\(result.unspent) sats")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.cashuSuccess)
                } else {
                    Text("0 sats")
                        .font(.subheadline)
                        .foregroundColor(.cashuMutedText)
                }
            } else if !isRestoring {
                // Remove button for pending mints
                Button(action: {
                    mintsToRestore.removeAll { $0 == url }
                }) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.cashuMutedText)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.cashuCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.cashuBorder, lineWidth: 1)
                )
        )
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
                print("Create wallet error: \(error)")
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

    private func searchNostrMintBackups() {
        restoreMintError = nil
        let cleanedMnemonic = restoreMnemonic
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .joined(separator: " ")

        Task {
            do {
                _ = try await mintBackupService.searchBackups(using: cleanedMnemonic)
            } catch {
                await MainActor.run {
                    restoreMintError = error.localizedDescription
                }
            }
        }
    }

    private func addSelectedNostrMints() {
        let selected = mintBackupService.discoveredMints.filter(\.selected)
        var addedCount = 0
        for mint in selected {
            if addMintUrlToRestoreList(mint.url, showDuplicateError: false, showValidationError: false) {
                addedCount += 1
            }
        }

        if addedCount == 0 {
            restoreMintError = "No new mint URLs were added from the Nostr backup."
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
                    print("Restore error for \(url): \(error)")
                }
            }
            currentRestoringMint = nil
            isRestoringMints = false
        }
    }

    private func finishRestore() {
        Task {
            await walletManager.completeRestore()
            await MainActor.run {
                mintBackupService.clearDiscovered()
            }
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
