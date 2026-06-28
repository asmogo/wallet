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
    @State private var showCurrencySheet = false

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
                    sectionGroup(title: "Display") {
                        currencyRow
                        toggleRow(
                            "Use ₿ symbol",
                            subtitle: "Use ₿ symbol instead of sats.",
                            icon: "bitcoinsign",
                            isOn: $settings.useBitcoinSymbol
                        )
                    }

                    sectionGroup(title: "Backup & Security") {
                        navRow("Backup & Restore", icon: "key.fill") {
                            backupDetailView
                        }
                        navRow("App Lock", icon: "lock.shield") {
                            securityDetailView
                        }
                    }

                    sectionGroup(title: "Payments") {
                        navRow("Lightning", icon: "bolt.fill") {
                            lightningDetailView
                        }
                        navRow("P2PK", icon: "lock.fill") {
                            p2pkDetailView
                        }
                    }

                    sectionGroup(title: "Integrations") {
                        navRow("Nostr", icon: "person.circle") {
                            nostrDetailView
                        }
                    }

                    sectionGroup(title: "Privacy") {
                        navRow("Privacy", icon: "eye.slash") {
                            privacyDetailView
                        }
                    }

                    sectionGroup(title: "About") {
                        externalLinkRow("Learn about Cashu",
                                        icon: "globe",
                                        url: URL(string: "https://cashu.space")!)
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
            .sheet(isPresented: $showCurrencySheet) {
                CurrencyPickerSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
            SettingsRowIcon(systemName: icon, tint: isDestructive ? .red : .secondary)

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

    /// Currency row in the Display group — shows the active fiat code (or "Off"
    /// when fiat display is disabled) and opens the bottom-sheet selector.
    private var currencyRow: some View {
        Button {
            HapticFeedback.selection()
            showCurrencySheet = true
        } label: {
            valueRow(
                "Currency",
                icon: "coloncurrencysign",
                value: settings.showFiatBalance ? settings.bitcoinPriceCurrency : "Off"
            )
        }
        .buttonStyle(.plain)
    }

    /// A row with a trailing value + chevron (a tap target that opens a sheet).
    private func valueRow(_ title: String, icon: String, value: String) -> some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemName: icon)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    /// A row carrying a trailing toggle, matching the tile + 14pt rhythm.
    private func toggleRow(
        _ title: String,
        subtitle: String? = nil,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemName: icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    // MARK: - Detail Views

    private var backupDetailView: some View {
        ScrollView {
            BackupSettingsSection(showBackup: $showBackup)
                .padding(.horizontal)
                .padding(.bottom, 32)
        }
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
        ScrollView {
            LazyVStack(spacing: 0) {
                SettingsSectionGroup("Keys") {
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
                SettingsSectionGroup("Relays") {
                    NostrRelaysSettingsSection(
                        relayInput: $relayInput,
                        relayError: $relayError,
                        copiedRelay: $copiedRelay
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Nostr")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var p2pkDetailView: some View {
        ScrollView {
            P2PKSettingsSection(
                expandedP2PKKeys: $expandedP2PKKeys,
                activeQRPayload: $activeQRPayload,
                copiedP2PKPublicKey: $copiedP2PKPublicKey,
                p2pkImportText: $p2pkImportText,
                showImportP2PK: $showImportP2PK,
                p2pkError: $p2pkError
            )
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("P2PK")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var privacyDetailView: some View {
        ScrollView {
            PrivacySettingsSection()
                .padding(.horizontal)
                .padding(.bottom, 32)
        }
        .navigationTitle("Privacy")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var securityDetailView: some View {
        ScrollView {
            SecuritySettingsSection()
                .padding(.horizontal)
                .padding(.bottom, 32)
        }
        .navigationTitle("App Lock")
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
        LazyVStack(spacing: 0) {
            SettingsSectionGroup(nil) {
                Toggle(isOn: appLockBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Require \(biometryNoun)")
                        Text("Ask for \(biometryNoun) when opening the wallet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
            }

            SettingsSectionFooter {
                VStack(alignment: .leading, spacing: 8) {
                    if !biometryAvailable {
                        Text("Set a device passcode in iOS Settings to use App Lock.")
                    }
                    Text("Your seed phrase always requires authentication to reveal, even when App Lock is off.")
                }
            }
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
    @State private var mintError: String?
    @FocusState private var mintFieldFocused: Bool

    // Dedicated restore/results screen (forward-only): a snapshot of the staged
    // mints plus each one's phase, driving the progress rows + live total.
    @State private var restoringMints: [String] = []
    @State private var restorePhases: [String: MintRestorePhase] = [:]

    // Best-effort mint identity (name + logo) fetched the moment a URL is staged,
    // so rows show the mint's own profile pic instead of a monogram.
    @State private var stagedMintIconUrls: [String: String] = [:]
    @State private var stagedMintNames: [String: String] = [:]

    private enum RestoreStep {
        case seed
        case mints
        case progress
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
            case .progress:
                progressStep
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
                // Forward-only on the restore/results screen — no back chevron there.
                if step != .progress {
                    Button(action: handleBackNavigation) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(isRestoringSeed)
                    .accessibilityLabel(step == .seed ? "Back" : "Back to seed phrase")
                }
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
        VStack(spacing: 0) {
            // Fixed header — stays put below the nav bar / top safe area.
            VStack(spacing: 6) {
                Text("Restore Ecash")
                    .font(.title2.weight(.semibold))

                Text("Add the mints you used before to recover ecash from this seed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 16)

            // Scrollable body — input + the staged mints the user has added.
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
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

                    if let mintError {
                        Text(mintError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
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
        // Pinned footer — one Restore CTA, enabled once a mint is staged. Back is
        // the nav-bar chevron.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: startRestoreFlow) {
                    Text(mintsToRestore.isEmpty
                         ? "Restore"
                         : "Restore from \(mintsToRestore.count) mint\(mintsToRestore.count == 1 ? "" : "s")")
                }
                .glassButton()
                .disabled(mintsToRestore.isEmpty)
                .padding(.horizontal)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(.background)
        }
        .animation(.snappy, value: mintError)
        .onAppear { mintFieldFocused = false }
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
    }

    private func stagedMintRow(url: String) -> some View {
        HStack(spacing: 12) {
            MintAvatarView(iconUrl: stagedMintIconUrls[url], name: stagedMintNames[url] ?? shortenedURL(url))

            VStack(alignment: .leading, spacing: 2) {
                Text(stagedMintNames[url] ?? shortenedURL(url))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(url)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                mintsToRestore.removeAll { $0 == url }
            } label: {
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

    private var progressStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(restoreAllSettled ? "Restore Complete" : "Restoring…")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.opacity)

                Text(restoreSubhead)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if restoreTotalRecovered > 0 {
                    Label("Recovered: \(restoreTotalRecovered) sats", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                        .contentTransition(.numericText(value: Double(restoreTotalRecovered)))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
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
            .padding(.bottom, 16)
            .background(.background)
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
                name: recovered?.mintName ?? stagedMintNames[url] ?? shortenedURL(url)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(recovered?.mintName ?? stagedMintNames[url] ?? shortenedURL(url))
                    .font(.subheadline.weight(.medium))
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
                        .font(.subheadline.weight(result.unspent > 0 ? .semibold : .regular))
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
                step = .mints
            } catch {
                seedError = "Couldn't open the wallet. \(error.userFacingWalletMessage)"
            }
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

        guard !mintsToRestore.contains(url) else {
            if showDuplicateError {
                mintError = "This mint is already in the list."
            }
            return false
        }

        mintsToRestore.append(url)
        mintError = nil
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

    /// Snapshot the staged mints and move to the dedicated restore screen, which
    /// runs the recovery and shows per-mint progress + results.
    private func startRestoreFlow() {
        mintFieldFocused = false
        restoringMints = mintsToRestore
        restorePhases = Dictionary(uniqueKeysWithValues: mintsToRestore.map { ($0, .pending) })
        step = .progress
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

// MARK: - iCloud Backup Settings

struct ICloudBackupSettingsView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var showEnableConfirm = false
    @State private var showDisableConfirm = false
    @State private var didBackUp = false
    @State private var backupError: String?

    var body: some View {
        List {
            Section {
                iCloudRow(
                    title: "Seed phrase",
                    detail: "iCloud Keychain · End-to-end encrypted",
                    systemImage: "key.fill"
                )
                iCloudRow(
                    title: "Mint list",
                    detail: "iCloud · Apple-encrypted",
                    systemImage: "bitcoinsign.bank.building"
                )
            } header: {
                Text("What's backed up")
            }

            Section {
                if !walletManager.iCloudAvailable() {
                    Text("Sign in to iCloud in Settings to enable backup.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Back up to iCloud", isOn: enabledBinding)
                }
            } footer: {
                Text("Your seed phrase is stored in iCloud Keychain, protected by Apple's end-to-end encryption. Mint URLs are stored in iCloud and encrypted by Apple.")
            }

            if walletManager.iCloudBackupEnabled {
                Section {
                    if let date = walletManager.lastICloudBackupDate {
                        LabeledContent("Last backed up") {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button(action: backUpNow) {
                        if didBackUp {
                            Label("Backed up", systemImage: "checkmark")
                                .foregroundStyle(.green)
                        } else {
                            Text("Back Up Now")
                        }
                    }
                }
            }
        }
        .navigationTitle("iCloud Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("Enable iCloud Backup?", isPresented: $showEnableConfirm) {
            Button("Enable") {
                walletManager.iCloudBackupEnabled = true
                if let outcome = walletManager.lastICloudBackupOutcome {
                    backupError = backupErrorMessage(for: outcome)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your seed phrase will be stored in iCloud Keychain, which is end-to-end encrypted and inaccessible to Apple. Mint URLs will be stored in iCloud encrypted by Apple.")
        }
        .alert("Disable iCloud Backup?", isPresented: $showDisableConfirm) {
            Button("Disable", role: .destructive) { walletManager.iCloudBackupEnabled = false }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your backup will be removed from iCloud Keychain and iCloud. Your local wallet is not affected.")
        }
        .alert("Backup Failed", isPresented: Binding(get: { backupError != nil }, set: { if !$0 { backupError = nil } })) {
            Button("OK", role: .cancel) { backupError = nil }
        } message: {
            Text(backupError ?? "")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { walletManager.iCloudBackupEnabled },
            set: { newValue in
                if newValue { showEnableConfirm = true }
                else { showDisableConfirm = true }
            }
        )
    }

    private func backUpNow() {
        let outcome = walletManager.performICloudBackup()
        if let message = backupErrorMessage(for: outcome) {
            backupError = message
            return
        }
        didBackUp = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            didBackUp = false
        }
    }

    /// User-facing message for a non-success backup outcome, or nil on success.
    private func backupErrorMessage(for outcome: ICloudBackupOutcome) -> String? {
        switch outcome {
        case .success: return nil
        case .unavailable: return "iCloud is unavailable. Sign in to iCloud in Settings and try again."
        case .noSeed: return "There's no wallet seed to back up."
        case .failed(let message): return message
        }
    }

    private func iCloudRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
