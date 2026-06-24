import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var npcService = NPCService.shared

    @State private var showBackup = false
    @State private var showDeleteConfirm = false
    @State private var copiedLightningAddress = false
    @State private var isCheckingPayments = false
    @State private var showMintPicker = false

    // Nostr Key Management
    @State private var showNsec = false
    @State private var copiedNsec = false
    @State private var showImportNsec = false
    @State private var importNsecText = ""
    @State private var showGenerateKeyConfirm = false
    @State private var showResetKeyConfirm = false
    @State private var nostrKeyError: String?
    @State private var relayInput = ""
    @State private var relayError: String?
    @State private var copiedRelay: String?
    @State private var p2pkImportText = ""
    @State private var showImportP2PK = false
    @State private var p2pkError: String?
    @State private var expandedP2PKKeys = false
    @State private var activeQRPayload: QRPayload?
    @State private var copiedP2PKPublicKey: String?
    @State private var walletActionError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    sectionGroup(title: "Backup") {
                        navRow("Backup & Restore", icon: "key.fill") {
                            backupDetailView
                        }
                    }

                    sectionGroup(title: "Security") {
                        navRow("App Lock", icon: "lock.shield") {
                            securityDetailView
                        }
                    }

                    sectionGroup(title: "Payments") {
                        navRow("Lightning", icon: "bolt.fill") {
                            lightningDetailView
                        }
                        CanvasDivider()
                        navRow("P2PK", icon: "lock.fill") {
                            p2pkDetailView
                        }
                    }

                    sectionGroup(title: "Integrations") {
                        navRow("Nostr", icon: "person.circle") {
                            nostrDetailView
                        }
                    }

                    sectionGroup(title: "Privacy & Display") {
                        navRow("Privacy", icon: "eye.slash") {
                            privacyDetailView
                        }
                        CanvasDivider()
                        navRow("Appearance", icon: "paintbrush") {
                            appearanceDetailView
                        }
                    }

                    sectionGroup(title: "About") {
                        externalLinkRow("Learn about Cashu",
                                        icon: "globe",
                                        url: URL(string: "https://cashu.space")!)
                        CanvasDivider()
                        externalLinkRow("Protocol Specs (NUTs)",
                                        icon: "doc.text",
                                        url: URL(string: "https://github.com/cashubtc/nuts")!)
                    }

                    sectionGroup(title: "Danger") {
                        Button(role: .destructive) {
                            HapticFeedback.selection()
                            showDeleteConfirm = true
                        } label: {
                            settingsRow("Delete Wallet", icon: "trash", isDestructive: true)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Cashu Wallet · 1.0.0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showBackup) {
                BackupView()
                    .environmentObject(walletManager)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showImportP2PK) {
                ImportP2PKSheet(
                    nsecText: $p2pkImportText,
                    onImport: importP2PKNsec
                )
                .presentationDetents([.medium])
            }
            .sheet(item: $activeQRPayload) { payload in
                QRCodeDetailSheet(title: payload.title, content: payload.content)
                    .presentationDetents([.medium, .large])
            }
            .alert("Delete Wallet", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteWallet()
                }
            } message: {
                Text("Are you sure you want to delete your wallet? This action cannot be undone. Make sure you have backed up your seed phrase!")
            }
            .alert("Wallet Action Failed", isPresented: Binding(
                get: { walletActionError != nil },
                set: { if !$0 { walletActionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(walletActionError ?? "Something went wrong. Try again.")
            }
        }
    }

    // MARK: - Section + Row Helpers

    @ViewBuilder
    private func sectionGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)
                .padding(.horizontal, 4)
                .padding(.top, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 4)
        }
    }

    private func navRow<Destination: View>(
        _ title: String,
        icon: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            settingsRow(title, icon: icon, showChevron: true)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { HapticFeedback.selection() })
    }

    private func externalLinkRow(_ title: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            settingsRow(title, icon: icon, showChevron: true, isExternal: true)
        }
        .simultaneousGesture(TapGesture().onEnded { HapticFeedback.selection() })
    }

    private func settingsRow(
        _ title: String,
        icon: String,
        showChevron: Bool = false,
        isExternal: Bool = false,
        isDestructive: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(isDestructive ? .red : .secondary)
                .frame(width: 28)

            Text(title)
                .font(.body)
                .foregroundStyle(isDestructive ? .red : .primary)

            Spacer(minLength: 8)

            if showChevron {
                Image(systemName: isExternal ? "arrow.up.right" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Detail Views

    private var backupDetailView: some View {
        List {
            Section {
                BackupSettingsSection(
                    showBackup: $showBackup
                )
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("Backup & Restore")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var lightningDetailView: some View {
        ScrollView {
            LightningAddressSettingsSection(
                copiedLightningAddress: $copiedLightningAddress,
                isCheckingPayments: $isCheckingPayments,
                showMintPicker: $showMintPicker
            )
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .refreshable {
            await npcService.checkAndClaimPayments()
        }
        .navigationTitle("Lightning")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var nostrDetailView: some View {
        List {
            Section("Keys") {
                NostrKeysSettingsSection(
                    showNsec: $showNsec,
                    copiedNsec: $copiedNsec,
                    showImportNsec: $showImportNsec,
                    importNsecText: $importNsecText,
                    showGenerateKeyConfirm: $showGenerateKeyConfirm,
                    showResetKeyConfirm: $showResetKeyConfirm,
                    nostrKeyError: $nostrKeyError
                )
            }
            .listRowSeparator(.hidden)
            Section("Relays") {
                NostrRelaysSettingsSection(
                    relayInput: $relayInput,
                    relayError: $relayError,
                    copiedRelay: $copiedRelay
                )
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("Nostr")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var p2pkDetailView: some View {
        List {
            Section {
                P2PKSettingsSection(
                    expandedP2PKKeys: $expandedP2PKKeys,
                    activeQRPayload: $activeQRPayload,
                    copiedP2PKPublicKey: $copiedP2PKPublicKey,
                    p2pkImportText: $p2pkImportText,
                    showImportP2PK: $showImportP2PK,
                    p2pkError: $p2pkError
                )
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("P2PK")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var privacyDetailView: some View {
        List {
            Section {
                PrivacySettingsSection()
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("Privacy")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var securityDetailView: some View {
        List {
            Section {
                SecuritySettingsSection()
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("App Lock")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var appearanceDetailView: some View {
        List {
            Section {
                ThemeSettingsSection()
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("Appearance")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func deleteWallet() {
        Task { @MainActor in
            do {
                try await walletManager.deleteWallet()
            } catch {
                walletActionError = error.userFacingWalletMessage
            }
        }
    }

    private func importP2PKNsec() {
        p2pkError = nil
        do {
            try settings.importP2PKNsec(p2pkImportText)
            p2pkImportText = ""
            showImportP2PK = false
        } catch {
            p2pkError = error.localizedDescription
        }
    }
}

// MARK: - Security Settings Section

struct SecuritySettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    @State private var biometryNoun = "Face ID"
    @State private var biometryAvailable = true
    @State private var authError: String?

    var body: some View {
        Group {
            Toggle(isOn: appLockBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Require \(biometryNoun)")
                    Text("Ask for \(biometryNoun) when opening the wallet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !biometryAvailable {
                Text("Set a device passcode in iOS Settings to use App Lock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Your seed phrase always requires authentication to reveal, even when App Lock is off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { refreshBiometry() }
        .alert("Couldn't Enable App Lock", isPresented: Binding(
            get: { authError != nil },
            set: { if !$0 { authError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authError ?? "")
        }
    }

    /// Enabling first confirms with a live auth and reverts to off on failure —
    /// you can't switch on a lock you can't satisfy.
    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { settings.appLockEnabled },
            set: { newValue in
                guard newValue else {
                    settings.appLockEnabled = false
                    return
                }
                Task {
                    let ok = await AppLockManager.shared.authenticate(reason: "Confirm to enable App Lock")
                    settings.appLockEnabled = ok
                    if !ok {
                        authError = "Authentication failed. App Lock was not enabled."
                    }
                }
            }
        )
    }

    private func refreshBiometry() {
        let context = LAContext()
        let available = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        biometryAvailable = available
        switch context.biometryType {
        case .faceID: biometryNoun = "Face ID"
        case .touchID: biometryNoun = "Touch ID"
        default: biometryNoun = available ? "your passcode" : "Face ID"
        }
    }
}

// MARK: - Shared Types

struct QRPayload: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}

// MARK: - Restore Wallet View

struct RestoreWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager

    @State private var step: RestoreStep = .seed
    @State private var restoreMnemonic = ""
    @State private var isRestoringSeed = false
    @State private var seedError: String?

    @State private var mintUrlInput = ""
    @State private var mintsToRestore: [String] = []
    @State private var restoreResults: [RestoreMintResult] = []
    @State private var isRestoringMints = false
    @State private var currentRestoringMint: String?
    @State private var mintError: String?
    @State private var previousWalletMintSuggestions: [RecommendedMint] = []

    private enum RestoreStep {
        case seed
        case mints
    }

    var body: some View {
        ZStack {
            switch step {
            case .seed:
                seedStep
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            case .mints:
                mintStep
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.snappy(duration: 0.28), value: step)
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: handleBackNavigation) {
                    Image(systemName: "chevron.left")
                }
                .disabled(isRestoringMints || isRestoringSeed)
                .accessibilityLabel(step == .seed ? "Back" : "Back to seed phrase")
            }
        }
    }

    private var seedStep: some View {
        let wordCount = normalizedWords(from: restoreMnemonic).count
        let invalidIndices = walletManager.invalidMnemonicWords(restoreMnemonic)
        let canContinue = wordCount == 12 && invalidIndices.isEmpty && !isRestoringSeed

        return VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Restore Wallet")
                    .font(.title.weight(.semibold))

                Text("Enter your 12 words in order.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)

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
                        Text("word1 word2 word3 ...")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

                Button(action: restoreMnemonic.isEmpty ? pasteMnemonicFromClipboard : clearMnemonic) {
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
                    Text("- \(invalidIndices.count) invalid")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let seedError {
                ErrorBannerView(message: seedError, type: .error)
                    .padding(.horizontal)
            }

            Button(action: initializeAndProceed) {
                if isRestoringSeed {
                    ProgressView()
                        .tint(.primary)
                } else {
                    Text("Next")
                }
            }
            .glassButton()
            .disabled(!canContinue)
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .padding(.top)
    }

    private var mintStep: some View {
        let isEmpty = mintsToRestore.isEmpty && restoreResults.isEmpty

        return VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Restore Ecash")
                    .font(.title2.weight(.semibold))

                Text("Add the mints you used before to recover ecash from this seed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 12)

            VStack(spacing: 12) {
                TextField("mint.example.com", text: $mintUrlInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .onSubmit(addMintUrl)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 8) {
                    Button(action: addMintUrl) {
                        capsuleChipLabel("Add", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .disabled(mintUrlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(mintUrlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)

                    Button(action: pasteMintUrlsFromClipboard) {
                        capsuleChipLabel("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Paste mint URLs from clipboard")
                }
            }
            .padding(.horizontal)

            restoreMintList

            SuggestedMintsSection(
                existingURLs: Set(mintsToRestore).union(restoreResults.map(\.mintUrl)),
                onAdd: { addMintUrlToRestoreList($0, showDuplicateError: false, showValidationError: false) },
                walletMints: previousWalletMintSuggestions
            )

            if let mintError {
                Text(mintError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            restoreSummary

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if !mintsToRestore.isEmpty {
                    Button(action: startRestore) {
                        if isRestoringMints {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Restoring...")
                            }
                        } else {
                            Text("Restore from \(mintsToRestore.count) mint\(mintsToRestore.count == 1 ? "" : "s")")
                        }
                    }
                    .glassButton()
                    .disabled(isRestoringMints)
                    .padding(.horizontal)
                }

                if isEmpty {
                    Button(action: finishRestore) {
                        Text("Skip")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .textLinkButton()
                    .disabled(isRestoringMints)
                } else {
                    Button(action: finishRestore) {
                        Text("Continue")
                    }
                    .glassButton()
                    .disabled(isRestoringMints)
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
    }

    /// Inline Liquid-Glass capsule chip (Add / Paste). Non-interactive glass so
    /// taps land reliably on the plain Button label; falls back to `.quaternary`
    /// below iOS 26. The leading SF Symbol is the affordance — inline chips are
    /// the documented exception to the iconless-CTA rule.
    private func capsuleChipLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .liquidGlass(in: Capsule())
            .contentShape(Capsule())
    }

    @ViewBuilder
    private var restoreMintList: some View {
        if !mintsToRestore.isEmpty || !restoreResults.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    let allItems: [(url: String, result: RestoreMintResult?)] =
                        mintsToRestore.map { ($0, nil) }
                        + restoreResults.map { ($0.mintUrl, $0) }

                    ForEach(Array(allItems.enumerated()), id: \.offset) { index, item in
                        restoreMintRow(
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
            .frame(maxHeight: 260)
        }
    }

    @ViewBuilder
    private var restoreSummary: some View {
        if !restoreResults.isEmpty {
            let totalRecovered = restoreResults.reduce(UInt64(0)) { $0 + $1.unspent }
            let totalPending = restoreResults.reduce(UInt64(0)) { $0 + $1.pending }

            VStack(spacing: 8) {
                if totalRecovered > 0 {
                    Label("Recovered: \(totalRecovered) sats", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                        .contentTransition(.numericText(value: Double(totalRecovered)))
                }

                if totalPending > 0 {
                    Label("Pending: \(totalPending) sats", systemImage: "clock")
                        .symbolEffect(.pulse, options: .repeating)
                        .font(.subheadline)
                        .monospacedDigit()
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
    }

    private func restoreMintRow(url: String, result: RestoreMintResult?, isRestoring: Bool) -> some View {
        HStack(spacing: 12) {
            if isRestoring {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 24, height: 24)
            } else if let result {
                Image(systemName: result.totalRecovered > 0 ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(result.totalRecovered > 0 ? .green : .secondary)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "bitcoinsign.bank.building")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result?.mintName ?? shortenedURL(url))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(url)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let result {
                Text(result.unspent > 0 ? "\(result.unspent) sats" : "0 sats")
                    .font(.subheadline.weight(result.unspent > 0 ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(result.unspent > 0 ? .green : .secondary)
            } else if !isRestoring {
                Button {
                    mintsToRestore.removeAll { $0 == url }
                } label: {
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

    private func pasteMnemonicFromClipboard() {
        guard let content = UIPasteboard.general.string else { return }
        HapticFeedback.selection()
        restoreMnemonic = content.trimmingCharacters(in: .whitespacesAndNewlines)
        seedError = nil
    }

    private func clearMnemonic() {
        HapticFeedback.selection()
        restoreMnemonic = ""
        seedError = nil
    }

    private func initializeAndProceed() {
        let cleanedMnemonic = normalizedWords(from: restoreMnemonic).joined(separator: " ")
        let currentMintSuggestions = walletManager.mints.map {
            RecommendedMint(name: $0.name, url: $0.url)
        }

        guard walletManager.validateMnemonic(cleanedMnemonic) else {
            seedError = "That seed phrase doesn't look right. Check the spelling and try again."
            return
        }

        isRestoringSeed = true
        seedError = nil

        Task { @MainActor in
            defer { isRestoringSeed = false }

            do {
                try await walletManager.initializeRestoredWallet(mnemonic: cleanedMnemonic)
                if !currentMintSuggestions.isEmpty {
                    previousWalletMintSuggestions = currentMintSuggestions
                }
                step = .mints
            } catch {
                seedError = "Couldn't open the wallet. \(error.userFacingWalletMessage)"
            }
        }
    }

    private func addMintUrl() {
        if addMintUrlToRestoreList(mintUrlInput, showDuplicateError: true, showValidationError: true) {
            mintUrlInput = ""
            HapticFeedback.selection()
        }
    }

    private func pasteMintUrlsFromClipboard() {
        guard let clipboardContent = UIPasteboard.general.string else {
            mintError = "Clipboard is empty."
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
            mintError = invalidCount > 0 ? "Nothing in the clipboard looked like a mint URL." : "No new mint URLs to add."
        } else if invalidCount > 0 {
            mintError = "Added \(addedCount) mint URL\(addedCount == 1 ? "" : "s"). Skipped \(invalidCount) invalid."
        } else {
            mintError = nil
        }
    }

    @discardableResult
    private func addMintUrlToRestoreList(_ rawUrl: String, showDuplicateError: Bool, showValidationError: Bool) -> Bool {
        guard let url = normalizedMintURL(from: rawUrl) else {
            if showValidationError {
                mintError = "That doesn't look like a mint URL."
            }
            return false
        }

        guard !mintsToRestore.contains(url),
              !restoreResults.contains(where: { $0.mintUrl == url }) else {
            if showDuplicateError {
                mintError = "This mint is already in the list."
            }
            return false
        }

        mintsToRestore.append(url)
        mintError = nil
        return true
    }

    private func startRestore() {
        isRestoringMints = true
        mintError = nil

        Task { @MainActor in
            defer {
                currentRestoringMint = nil
                isRestoringMints = false
            }

            let urls = mintsToRestore
            for url in urls {
                currentRestoringMint = url

                do {
                    let result = try await walletManager.restoreFromMint(url: url)
                    restoreResults.append(result)
                    mintsToRestore.removeAll { $0 == url }
                } catch {
                    mintError = "Couldn't reach \(shortenedURL(url)). \(error.userFacingWalletMessage)"
                    AppLogger.wallet.error("Restore error for \(url): \(error)")
                }
            }
        }
    }

    private func finishRestore() {
        Task { @MainActor in
            await walletManager.completeRestore()
            dismiss()
        }
    }

    private func handleBackNavigation() {
        HapticFeedback.selection()
        if step == .seed {
            dismiss()
        } else {
            goBackToSeed()
        }
    }

    private func goBackToSeed() {
        mintsToRestore.removeAll()
        restoreResults.removeAll()
        mintError = nil
        step = .seed
    }

    private func normalizedWords(from phrase: String) -> [String] {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
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

    private func shortenedURL(_ url: String) -> String {
        var shortened = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")

        if shortened.hasSuffix("/") {
            shortened = String(shortened.dropLast())
        }

        return shortened
    }
}

// MARK: - QR Code Detail Sheet

struct QRCodeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let content: String

    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                QRCodeView(content: content, showControls: false)
                    .padding()
                    .frame(width: 280, height: 280)
                    .background(Color.white)
                    .clipShape(.rect(cornerRadius: 12))

                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Button(action: copyToClipboard) {
                        Text(copied ? "Copied" : "Copy")
                    }
                    .glassButton()

                    ShareLink(item: content) {
                        Text("Share")
                    }
                    .glassButton()
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = content
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

// MARK: - Import P2PK Sheet

struct ImportP2PKSheet: View {
    @Binding var nsecText: String
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("nsec1...", text: $nsecText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Import an nsec key to add a P2PK locking key.")
                }

                if let validationError {
                    Section {
                        Text(validationError)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Import nsec") {
                        if validate() { onImport() }
                    }
                    .disabled(nsecText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Import P2PK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func validate() -> Bool {
        validationError = nil
        let value = nsecText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.hasPrefix("nsec1") else {
            validationError = "Invalid nsec format"
            return false
        }
        return true
    }
}

// MARK: - Backup View

struct BackupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager

    @State private var showWords = false
    @State private var copiedToClipboard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.orange)

                        Text("Keep Your Seed Phrase Safe")
                            .font(.headline)

                        Text("Anyone with these words can access your funds. Never share them with anyone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()

                    let words = walletManager.getMnemonicWords()
                    let mnemonic = words.joined(separator: " ")
                    let hiddenMnemonic = words.map { String(repeating: "\u{2022}", count: max(3, $0.count)) }.joined(separator: " ")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seed phrase")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        HStack(spacing: 10) {
                            Text(showWords ? mnemonic : hiddenMnemonic)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(showWords ? .primary : .secondary)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)

                            VStack(spacing: 8) {
                                Button(action: toggleReveal) {
                                    Image(systemName: showWords ? "eye.slash" : "eye")
                                }

                                Button(action: copyToClipboard) {
                                    Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                        .foregroundStyle(copiedToClipboard ? .green : Color.accentColor)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                    Spacer(minLength: 50)

                    Button(action: { dismiss() }) {
                        Text("Done")
                    }
                    .glassButton()
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Hiding is free; revealing always requires authentication, regardless of
    /// the App Lock setting.
    private func toggleReveal() {
        if showWords {
            showWords = false
            return
        }
        Task {
            if await AppLockManager.shared.authenticate(reason: "Reveal your seed phrase") {
                showWords = true
            }
        }
    }

    private func copyToClipboard() {
        Task {
            guard await AppLockManager.shared.authenticate(reason: "Copy your seed phrase") else { return }
            let words = walletManager.getMnemonicWords().joined(separator: " ")
            UIPasteboard.general.string = words
            copiedToClipboard = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                copiedToClipboard = false
            }
        }
    }
}

// MARK: - Mint Picker Sheet

struct MintPickerSheet: View {
    let mints: [MintInfo]
    @Binding var selectedMintUrl: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(mints, id: \.url) { mint in
                Button {
                    selectedMintUrl = mint.url
                    onSelect(mint.url)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mint.name)
                            Text(mint.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if selectedMintUrl == mint.url {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Select Mint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Import Nsec Sheet

struct ImportNsecSheet: View {
    @Binding var nsecText: String
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("nsec1...", text: $nsecText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Enter your nsec (Nostr private key) to use it for your Lightning address.")
                }

                Section {
                    Button("Paste from Clipboard") {
                        if let text = UIPasteboard.general.string {
                            nsecText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Import Key") {
                        if validateNsec() { onImport() }
                    }
                    .disabled(nsecText.isEmpty)
                }
            }
            .navigationTitle("Import Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func validateNsec() -> Bool {
        errorMessage = nil
        let trimmed = nsecText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("nsec1") else {
            errorMessage = "Invalid format. nsec must start with 'nsec1'"
            return false
        }
        guard trimmed.count >= 59 else {
            errorMessage = "nsec is too short"
            return false
        }
        return true
    }
}

#Preview {
    SettingsView()
        .environmentObject(WalletManager())
}
