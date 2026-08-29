import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var npcService = NPCService.shared
    @ObservedObject var nwc = NWCManager.shared

    @State private var showBackup = false
    @State private var showDeleteConfirm = false
    @State private var isCheckingPayments = false
    @State private var showMintPicker = false
    @State private var showCurrencySheet = false

    // Nostr key + relay state is owned by the sections themselves
    // (NostrKeysSettingsSection / NostrRelaysSettingsSection), matching the
    // self-contained P2PKSettingsSection.
    @State private var walletActionError: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                sectionGroup(title: "Display") {
                    currencyRow
                    toggleRow(
                        "Use ₿ symbol",
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
                    navRow("Locked Ecash", icon: "lock.fill") {
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

                Text(versionFooter)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier("settings-screen")
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("Wallet", systemImage: "chevron.backward")
                }
                .accessibilityLabel("Back to Wallet")
                .accessibilityIdentifier("settings-back-button")
            }
        }
        .sheet(isPresented: $showBackup) {
            BackupView()
                .environmentObject(walletManager)
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
        .errorBanner($walletActionError)
    }

    // MARK: - Section + Row Helpers

    /// Footer mirrors Android's "Cashu Wallet · <VERSION_NAME>", sourced from bundle
    /// metadata so a version bump never leaves Settings showing a stale literal.
    private var versionFooter: String {
        if let version = AppVersion.displayString() {
            return "Cashu Wallet · \(version)"
        }
        return "Cashu Wallet"
    }

    @ViewBuilder
    private func sectionGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .cashuText(.overline)
                .foregroundStyle(.secondary)
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

    /// A `navRow` variant with a trailing status value ("On" / "Off"), matching
    /// the iOS Settings idiom for toggleable features behind a push.
    private func navValueRow<Destination: View>(
        _ title: String,
        icon: String,
        value: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
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
                Text("Nostr powers your Lightning address, npub.cash requests, encrypted backups, and Wallet Connect.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .padding(.bottom, 28)

                NostrKeysSettingsSection()
                NostrRelaysSettingsSection()

                SettingsSectionGroup("Apps") {
                    navValueRow(
                        "Wallet Connect",
                        icon: "bolt.horizontal.circle",
                        value: nwc.isEnabled ? "On" : "Off"
                    ) {
                        NWCSettingsView()
                    }
                }
                SettingsSectionFooter {
                    Text("Let a Nostr app create invoices and pay Lightning invoices from this wallet.")
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
            P2PKSettingsSection()
                .padding(.horizontal)
                .padding(.bottom, 32)
        }
        .navigationTitle("Locked Ecash")
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
    @ObservedObject private var nostrBackupService = NostrMintBackupService.shared

    @State private var step: RestoreStep = .seed
    @State private var seedEntry = SeedPhraseEntry()
    /// Paste results and checksum failure. Per-word rejection is the field's own.
    @State private var seedNotice: SeedEntryNotice?
    @State private var seedFieldFocused = false
    @State private var isRestoringSeed = false
    @State private var seedError: String?

    @State private var mintUrlInput = ""
    @State private var mintsToRestore: [String] = []
    @State private var mintError: String?
    @State private var mintNoticeSeverity: ErrorSeverity = .info

    /// The restore mint-list channel carries successes ("Added 3 mint URLs…") and
    /// gentle advisories as well as real errors, so it sets a severity, not just text.
    private func setMintNotice(_ message: String?, severity: ErrorSeverity = .info) {
        mintError = message
        mintNoticeSeverity = severity
    }
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
            // Quiet cross-fade between restore steps — no lateral slide. This mirrors
            // OnboardingView's restore twin (which documents the horizontal push as
            // "jarring here"), and honors DESIGN.md rule #6: an in-place flow swap
            // cross-fades; only cross-screen pushes slide.
            switch step {
            case .seed:
                seedStep
                    .transition(.opacity)
            case .mints:
                mintStep
                    .transition(.opacity)
            case .progress:
                progressStep
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: step)
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
                            .toolbarIconTapTarget()
                    }
                    .disabled(isRestoringSeed)
                    .accessibilityLabel(step == .seed ? "Back" : "Back to seed phrase")
                }
            }
        }
    }

    private var seedStep: some View {
        let canContinue = seedEntry.isComplete && !seedEntry.isReviewing && !isRestoringSeed

        // The same word-by-word field the onboarding step uses. This screen and
        // that one ask for the identical thing, so they ask for it the same way.
        return VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Restore Wallet")
                    .font(.title.weight(.semibold))

                Text(SeedEntryCopy.subhead)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)

            ScrollView {
                SeedWordEntryField(
                    entry: $seedEntry,
                    isFocused: $seedFieldFocused,
                    notice: seedNotice,
                    onOutcome: handleSeedOutcome,
                    onPaste: pasteMnemonicFromClipboard
                )
                .padding(.top, 24)
                .padding(.bottom, ScrollFadeMetrics.band)
            }
            .scrollDismissesKeyboard(.never)
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeFade(bottom: 0)
            .frame(maxHeight: .infinity)

            if let seedError {
                ErrorBannerView(message: seedError, severity: .error)
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
        .onAppear { seedFieldFocused = true }
        .onDisappear { seedFieldFocused = false }
        .onChange(of: seedEntry.isReviewing) { _, reviewing in
            if !reviewing { seedNotice = nil }
        }
    }

    private var mintStep: some View {
        VStack(spacing: 0) {
            // Fixed header — stays put below the nav bar / top safe area.
            VStack(spacing: 6) {
                Text("Restore Funds")
                    .font(.title2.weight(.semibold))

                Text("Add the mints you used before to recover funds from this seed.")
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

                            Button(action: searchNostrMintBackups) {
                                capsuleChipLabel(
                                    nostrBackupService.isSearching ? "Searching…" : "Nostr",
                                    systemImage: "antenna.radiowaves.left.and.right"
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(nostrBackupService.isSearching)
                            .opacity(nostrBackupService.isSearching ? 0.4 : 1)
                            .accessibilityLabel("Find mints from your Nostr backup")
                        }
                    }
                    .padding(.horizontal)

                    restoreMintList

                    if let mintError {
                        InlineNotice(message: mintError, severity: mintNoticeSeverity)
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

    /// Twin of `OnboardingView.handleSeedOutcome`.
    private func handleSeedOutcome(_ outcome: SeedCommitOutcome) {
        if outcome != .ignored { seedNotice = nil }
        guard outcome == .completed else { return }
        runSeedChecksum()
    }

    /// A checksum failure names no single word, so it hands back all twelve.
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
        seedError = nil

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

    private func initializeAndProceed() {
        // Already normalised: every word was committed from the wordlist.
        let cleanedMnemonic = seedEntry.phrase

        guard walletManager.validateMnemonic(cleanedMnemonic) else {
            runSeedChecksum()
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
            setMintNotice("Clipboard is empty.")
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
            setMintNotice(invalidCount > 0 ? "Nothing in the clipboard looked like a mint URL." : "No new mint URLs to add.")
        } else if invalidCount > 0 {
            setMintNotice("Added \(addedCount) mint URL\(addedCount == 1 ? "" : "s"). Skipped \(invalidCount) invalid.")
        } else {
            mintError = nil
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
                    setMintNotice("No Nostr mint backup found on your relays.", severity: .caution)
                } else if addedCount == 0 {
                    setMintNotice("Backup found — its mints are already in the list.")
                } else {
                    setMintNotice("Added \(addedCount) mint\(addedCount == 1 ? "" : "s") from your Nostr backup.")
                }
            } catch {
                // Through the shared mapper, never `localizedDescription` —
                // a relay failure here surfaced as a raw CDK FFI dump.
                setMintNotice(error.userFacingWalletMessage, severity: .error)
            }
        }
    }

    @discardableResult
    private func addMintUrlToRestoreList(_ rawUrl: String, showDuplicateError: Bool, showValidationError: Bool) -> Bool {
        guard let url = normalizedMintURL(from: rawUrl) else {
            if showValidationError {
                setMintNotice("That doesn't look like a mint URL.", severity: .caution)
            }
            return false
        }

        guard !mintsToRestore.contains(url) else {
            if showDuplicateError {
                setMintNotice("This mint is already in the list.", severity: .caution)
            }
            return false
        }

        mintsToRestore.append(url)
        mintError = nil
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
                        Text("Copy")
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
            // Extra top clearance so the wide, centered QR card doesn't tuck
            // under the floating close-X (its column overlaps the card's
            // top-left corner at this width).
            .padding(.top, 44)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SheetCloseButton()
                }
            }
        }
        .flatBottomSheetSurface()
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = content
        ConfirmationToast.show("Copied \(title.lowercased())")
    }
}

// MARK: - Import P2PK Sheet

struct ImportP2PKSheet: View {
    @Binding var nsecText: String
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var validationError: String?

    private var trimmed: String {
        nsecText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Paste a private key (nsec) to add it. You'll be able to claim ecash locked to it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                HStack(spacing: 10) {
                    TextField("nsec1…", text: $nsecText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button(action: { nsecText.isEmpty ? paste() : clear() }) {
                        // Padding expands the hit area; the negative outer
                        // padding cancels the layout growth so the field row
                        // keeps its height.
                        Image(systemName: nsecText.isEmpty ? "doc.on.clipboard" : "xmark.circle.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .contentShape(Rectangle())
                            .padding(-10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(nsecText.isEmpty ? "Paste" : "Clear")
                }
                .padding(14)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 12))

                if let validationError {
                    InlineNotice(message: validationError, severity: .error)
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)

                Button(action: { if validate() { onImport() } }) {
                    Text("Import key")
                }
                .glassButton()
                .disabled(trimmed.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
            .animation(.easeInOut(duration: 0.2), value: validationError)
            .navigationTitle("Import a key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .flatBottomSheetSurface()
    }

    private func paste() {
        if let clip = UIPasteboard.general.string {
            HapticFeedback.selection()
            nsecText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func clear() {
        HapticFeedback.selection()
        nsecText = ""
        validationError = nil
    }

    private func validate() -> Bool {
        validationError = nil
        guard trimmed.lowercased().hasPrefix("nsec1") else {
            validationError = "That doesn't look like an nsec key. It should start with “nsec1”."
            return false
        }
        return true
    }
}

// MARK: - Backup View

struct BackupView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showWords = false
    @State private var contentHeight: CGFloat = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        let words = walletManager.getMnemonicWords()

        VStack(spacing: 24) {
            Text("Backup Wallet")
                .font(.title2.weight(.semibold))

            Text(showWords
                 ? "Write down these words in order and store them somewhere safe. Do not share them with anyone."
                 : "Your recovery phrase is the only way to restore your wallet. Keep it private and stored somewhere safe. Never share it with anyone.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if showWords {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: 6) {
                                Text("\(index + 1).")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(word)
                                    .font(.caption2.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Word \(index + 1), \(word)")
                        }
                    }
                }
                .frame(maxHeight: 260)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Button(showWords ? "Copy Recovery Phrase" : "Reveal Recovery Phrase") {
                if showWords {
                    copyToClipboard()
                } else {
                    revealWords()
                }
            }
            .glassButton()
            .contentTransition(.opacity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .contentFitMeasured { contentHeight = $0 }
        .contentFitDetent(
            contentHeight,
            estimate: showWords ? 460 : 250,
            navigationBar: false,
            step: showWords,
            stepResize: .milliseconds(300)
        )
        .presentationDragIndicator(.visible)
        .flatBottomSheetSurface()
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: showWords)
    }

    /// Revealing always requires authentication, regardless of the App Lock setting.
    private func revealWords() {
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
            ConfirmationToast.show("Copied recovery phrase")
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
        .errorBanner($backupError, retry: { backUpNow() })
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
        case .deferred: return "iCloud backup is paused until wallet recovery finishes."
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
                    // Selection is confirmed by the server round-trip in
                    // onSelect; writing it here would show a mint the server
                    // never accepted.
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
        .flatBottomSheetSurface()
    }
}

// MARK: - Import Nsec Sheet

/// Imports a custom Nostr key on the same content-fit sheet recipe as
/// `BackupView` and `PrivateKeyRevealSheet`: in-content title, secondary copy,
/// one primary CTA, dismissed by drag. Two faces on one sheet — entry and the
/// replace-key confirmation — cross-fade while the sheet resizes between them,
/// instead of stacking an alert on top of the sheet.
struct ImportNsecSheet: View {
    @Binding var nsecText: String
    let replacementWarning: String
    /// Returns nil on success, or a message to render here. Reporting back keeps
    /// a decode failure visible instead of leaving it on the screen behind us.
    let onImport: () -> String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var step: Step = .entry
    @State private var contentHeight: CGFloat = 0
    @FocusState private var fieldFocused: Bool

    private enum Step: Hashable { case entry, confirm, success }

    private var canImport: Bool {
        !nsecText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case .entry: entryFace
            case .confirm: confirmFace
            case .success: successFace
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .contentFitMeasured { contentHeight = $0 }
        .contentFitDetent(
            contentHeight,
            estimate: 300,
            navigationBar: false,
            step: [AnyHashable(step), AnyHashable(errorMessage)],
            stepResize: .milliseconds(300)
        )
        .presentationDragIndicator(.visible)
        .flatBottomSheetSurface()
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: step)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: errorMessage)
    }

    @ViewBuilder private var entryFace: some View {
        Group {
            Text("Import Key")
                .font(.title2.weight(.semibold))

            Text("Enter your nsec (Nostr private key) to use it for your Lightning address.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                // Field and action row copy the Add Mint form: a clear affordance
                // in the field, Paste as the secondary button beside the CTA.
                HStack(spacing: 10) {
                    TextField("nsec1…", text: $nsecText)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel("Nostr private key")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .onSubmit(review)
                        .onChange(of: nsecText) {
                            if errorMessage != nil { errorMessage = nil }
                        }

                    if !nsecText.isEmpty {
                        Button {
                            nsecText = ""
                            errorMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear")
                    }
                }
                .animation(.smooth(duration: 0.2), value: nsecText.isEmpty)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    InlineNotice(message: errorMessage, severity: .error)
                        .transition(.opacity)
                }
            }

            HStack(spacing: 12) {
                Button("Paste", action: pasteFromClipboard)
                    .flatSheetSecondaryButton()
                    .accessibilityHint("Pastes an nsec key from the clipboard")

                Button("Review Import", action: review)
                    .glassButton()
                    .disabled(!canImport)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private var confirmFace: some View {
        Group {
            Text("Replace Nostr Key?")
                .font(.title2.weight(.semibold))

            Text(replacementWarning)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Cancel") { step = .entry }
                    .flatSheetSecondaryButton()

                Button("Import", action: confirmImport)
                    .glassButton()
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private var successFace: some View {
        Group {
            Text("Key Imported")
                .font(.title2.weight(.semibold))

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(ErrorSeverity.success.foreground)
                .accessibilityLabel("Success")

            Text("Your Nostr key was replaced with the imported key. Your Lightning address and npub.cash now come from this key.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") { dismiss() }
                .glassButton()
        }
        .transition(.opacity)
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Clipboard is empty."
            return
        }
        nsecText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
    }

    private func review() {
        guard canImport, validateNsec() else { return }
        // Resign concurrently with the face swap — sequencing behind the
        // keyboard leaves the morph waiting on keyboard-blind geometry.
        fieldFocused = false
        step = .confirm
    }

    private func confirmImport() {
        if let failure = onImport() {
            // Import failed: morph back to the entry face with the error
            // inline, where the field is available to fix it.
            errorMessage = failure
            step = .entry
        } else {
            step = .success
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
            errorMessage = "That doesn't look like a complete nsec. Check you copied the whole key and try again."
            return false
        }
        return true
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(WalletManager())
    }
}
