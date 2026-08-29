import SwiftUI

private enum NostrIdentityReplacementWarning {
    static let generate = "This replaces your current Nostr key with a newly generated key. Your Lightning address will change, Nostr apps and messages will use a different identity, and your old key will be replaced."
    static let importKey = "This replaces your current Nostr key with the imported key. Your Lightning address will change, Nostr apps and messages will use a different identity, and your old key will be replaced."
    static let reset = "This switches to the Nostr key derived from your wallet seed. Your Lightning address will change, Nostr apps and messages will use a different identity, and your old custom key will be deleted and replaced."
}

// MARK: - Nostr Keys Section

/// The Nostr key hub, built on the shared single-canvas settings recipe so it
/// reads as one family with the Locked Ecash hub: a `KeyCard` for the active key,
/// a house-styled key-source picker, and plain action rows. Self-contained — owns
/// its own sheets and alerts, mirroring `P2PKSettingsSection`.
struct NostrKeysSettingsSection: View {
    @ObservedObject var nostrService = NostrService.shared

    @State private var showImportNsec = false
    @State private var importNsecText = ""
    @State private var showGenerateKeyConfirm = false
    @State private var showResetKeyConfirm = false
    @State private var nostrKeyError: String?
    @State private var showNsecReveal = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsSectionGroup("Nostr key") {
                keyCard
            }
            SettingsSectionFooter {
                Text("Your Lightning address and npub.cash come from this key.")
            }

            SettingsSectionGroup("Key source") {
                ForEach(Array(NostrSignerType.allCases.enumerated()), id: \.element) { index, type in
                    keySourceRow(type)
                }
            }

            SettingsSectionGroup(nil) {
                Button(action: { HapticFeedback.selection(); nostrKeyError = nil; showGenerateKeyConfirm = true }) {
                    settingsActionRow("Generate new key", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)

                Button(action: { nostrKeyError = nil; importNsecText = ""; showImportNsec = true }) {
                    settingsActionRow("Import key", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.plain)

                if nostrService.signerType == .privateKey {
                    Button(action: { HapticFeedback.selection(); showResetKeyConfirm = true }) {
                        settingsActionRow("Reset to wallet seed", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                }
            }

            if let nostrKeyError {
                InlineNotice(message: nostrKeyError, severity: .error)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: nostrService.signerType)
        .animation(.easeInOut(duration: 0.2), value: nostrKeyError)
        .alert("Generate New Key", isPresented: $showGenerateKeyConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Generate", role: .destructive) {
                generateNewKey()
            }
        } message: {
            Text(NostrIdentityReplacementWarning.generate)
        }
        .alert("Reset to Wallet Seed", isPresented: $showResetKeyConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetToSeedKey()
            }
        } message: {
            Text(NostrIdentityReplacementWarning.reset)
        }
        .sheet(isPresented: $showImportNsec) {
            ImportNsecSheet(
                nsecText: $importNsecText,
                replacementWarning: NostrIdentityReplacementWarning.importKey,
                onImport: importNsec
            )
        }
        .sheet(isPresented: $showNsecReveal) {
            PrivateKeyRevealSheet(
                title: "Nostr Private Key",
                nsec: nostrService.getNsec(),
                warning: "Anyone with this key can control your Lightning address. Never share it."
            )
        }
    }

    // MARK: Key card

    @ViewBuilder
    private var keyCard: some View {
        if nostrService.isInitialized && !nostrService.npub.isEmpty {
            KeyCard(
                title: "Nostr key",
                pubkey: nostrService.npub,
                status: nostrService.signerType == .seed ? .seedBacked : .custom,
                onCopy: { copyNpub() },
                actions: [
                    .init(title: "Reveal nsec", systemImage: "eye") {
                        showNsecReveal = true
                    }
                ],
                displayLabel: P2PKKeyDisplay.middleTruncate(nostrService.npub, lead: 12, tail: 12)
            )
        } else {
            HStack(spacing: 12) {
                Image(systemName: "key")
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: Circle())
                Text("Your Nostr key appears once your wallet finishes setting up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func keySourceRow(_ type: NostrSignerType) -> some View {
        Button(action: { switchSignerType(to: type) }) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(type.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if nostrService.signerType == type {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func copyNpub() {
        UIPasteboard.general.string = nostrService.npub
        HapticFeedback.selection()
        ConfirmationToast.show("Copied Nostr public key")
    }

    private func generateNewKey() {
        nostrKeyError = nil
        do {
            try nostrService.generateRandomKeypair()
        } catch {
            nostrKeyError = error.localizedDescription
        }
    }

    /// Returns nil on success, or a message for the sheet to render. Reporting
    /// back to the sheet keeps a decode failure visible — writing it to
    /// `nostrKeyError` put the message on the screen *behind* the open sheet.
    private func importNsec() -> String? {
        nostrKeyError = nil
        let nsec = importNsecText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nsec.isEmpty else { return "Please enter an nsec" }
        do {
            try nostrService.importNsec(nsec)
            importNsecText = ""
            showImportNsec = false
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func resetToSeedKey() {
        nostrKeyError = nil
        do {
            try nostrService.resetToSeedKey()
        } catch {
            nostrKeyError = error.localizedDescription
        }
    }

    private func switchSignerType(to type: NostrSignerType) {
        guard nostrService.signerType != type else { return }
        HapticFeedback.selection()
        nostrKeyError = nil
        if type == .privateKey && !nostrService.hasCustomPrivateKey() {
            showGenerateKeyConfirm = true
            return
        }
        if type == .seed {
            showResetKeyConfirm = true
            return
        }
        do {
            try nostrService.switchSignerType(to: type)
        } catch {
            nostrKeyError = error.localizedDescription
        }
    }
}

// MARK: - Nostr Relays Section

/// The Nostr relay list, on the same single-canvas recipe: a glass input field
/// (matching `ImportP2PKSheet`) over a list of relay rows.
/// Self-contained — owns its own input/error state.
struct NostrRelaysSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    @State private var relayInput = ""
    @State private var relayError: String?

    private var canAdd: Bool {
        !relayInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSectionGroup("Relays") {
                HStack(spacing: 10) {
                    TextField("wss://relay.example.com", text: $relayInput)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addRelay)

                    Button(action: addRelay) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(canAdd ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .accessibilityLabel("Add relay")
                }
                .padding(14)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14))

                if !settings.nostrRelays.isEmpty {
                    Color.clear.frame(height: 10)
                    ForEach(Array(settings.nostrRelays.enumerated()), id: \.element) { index, relay in
                        relayRow(relay)
                    }
                }
            }

            if let relayError {
                InlineNotice(message: relayError, severity: .error)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .transition(.opacity)
            }

            SettingsSectionFooter {
                Text("Relays sync your Nostr data for compatible features like npub.cash and backups.")
            }

            SettingsSectionGroup(nil) {
                Button(action: {
                    HapticFeedback.selection()
                    settings.resetNostrRelaysToDefault()
                    relayError = nil
                }) {
                    settingsActionRow("Reset to default relays", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: settings.nostrRelays)
        .animation(.easeInOut(duration: 0.2), value: relayError)
    }

    private func relayRow(_ relay: String) -> some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemName: "antenna.radiowaves.left.and.right")
            Text(relay)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            HStack(spacing: 18) {
                Button(action: { copyRelay(relay) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy relay URL")

                Button(action: { HapticFeedback.selection(); settings.removeNostrRelay(relay) }) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove relay")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func addRelay() {
        relayError = nil
        let trimmed = relayInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lowercased = trimmed.lowercased()
        guard lowercased.hasPrefix("wss://") || lowercased.hasPrefix("ws://") else {
            relayError = "Relay URL must start with ws:// or wss://"
            return
        }
        guard settings.addNostrRelay(trimmed) else {
            relayError = "Relay already added"
            return
        }
        relayInput = ""
    }

    private func copyRelay(_ relay: String) {
        UIPasteboard.general.string = relay
        HapticFeedback.selection()
        ConfirmationToast.show("Copied relay URL")
    }
}

// MARK: - Nostr Mint Backup Section

/// Encrypted mint-list backup on Nostr (NUT-27, handled entirely by cdk), on
/// the same single-canvas recipe: an auto-backup toggle, a manual backup row,
/// and a footer carrying the last backup time. Self-contained — owns its own
/// error state, mirroring the other sections in this file.
struct NostrMintBackupSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var backupService = NostrMintBackupService.shared

    @State private var backupError: String?

    var body: some View {
        VStack(spacing: 0) {
            SettingsSectionGroup("Mint backup") {
                HStack(spacing: 14) {
                    SettingsRowIcon(systemName: "tray.and.arrow.up")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic mint backup")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("Publish after every mint change.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $settings.nostrMintBackupEnabled)
                        .labelsHidden()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)

                Button(action: backupNow) {
                    HStack(spacing: 14) {
                        SettingsRowIcon(systemName: "arrow.up.circle")
                        Text(backupService.isBackingUp ? "Backing up…" : "Back up now")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if backupService.isBackingUp {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(backupService.isBackingUp || walletManager.mints.isEmpty)
                .opacity(walletManager.mints.isEmpty ? 0.5 : 1)
            }

            if let backupError {
                InlineNotice(message: backupError, severity: .error)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .transition(.opacity)
            }

            SettingsSectionFooter {
                Text(footerText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: backupError)
    }

    private var footerText: String {
        guard !walletManager.mints.isEmpty else {
            return "Add a mint to back up. The list is encrypted to your seed and published to your relays."
        }
        if let date = backupService.lastBackupDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Your mint list is encrypted to your seed and published to your relays. Last backup \(formatter.localizedString(for: date, relativeTo: Date()))."
        }
        return "Your mint list is encrypted to your seed and published to your relays, so restoring from seed can find your mints."
    }

    private func backupNow() {
        HapticFeedback.selection()
        backupError = nil

        Task { @MainActor in
            do {
                try await backupService.backupMints()
                HapticFeedback.notification(.success)
            } catch {
                backupError = error.localizedDescription
            }
        }
    }
}

// MARK: - Shared row helper

/// A plain single-canvas settings action row (leading glyph + title), matching
/// `AdvancedKeysView.actionRow`. Shared by both Nostr sections in this file.
private func settingsActionRow(_ title: String, systemImage: String) -> some View {
    HStack(spacing: 14) {
        SettingsRowIcon(systemName: systemImage)
        Text(title)
            .font(.body)
            .foregroundStyle(.primary)
        Spacer(minLength: 8)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 14)
    .contentShape(Rectangle())
}
