import SwiftUI

struct NostrKeysSettingsSection: View {
    @ObservedObject var nostrService = NostrService.shared

    @Binding var showNsec: Bool
    @Binding var copiedNsec: Bool
    @Binding var showImportNsec: Bool
    @Binding var importNsecText: String
    @Binding var showGenerateKeyConfirm: Bool
    @Binding var showResetKeyConfirm: Bool
    @Binding var nostrKeyError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nostr Key Source")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Your Lightning address is derived from your Nostr public key. Choose which key to use.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Signer type selection
            VStack(spacing: 8) {
                ForEach(NostrSignerType.allCases, id: \.self) { type in
                    signerTypeRow(type)
                }
            }
            .padding(.top, 8)

            // Current key info
            if nostrService.isInitialized {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Public Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)

                    // npub display
                    GroupBox {
                        Text(nostrService.npub)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                // nsec reveal/copy
                VStack(alignment: .leading, spacing: 8) {
                    Text("Private Key (nsec)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    GroupBox {
                        HStack {
                            if showNsec {
                                Text(nostrService.nsec)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text(String(repeating: "*", count: 20))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(action: { showNsec.toggle() }) {
                                Image(systemName: showNsec ? "eye.slash" : "eye")
                                    .foregroundStyle(Color.accentColor)
                            }

                            Button(action: copyNsec) {
                                Image(systemName: copiedNsec ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedNsec ? .green : Color.accentColor)
                            }
                        }
                    }

                    Text("Keep your private key secret. Anyone with it can control your Lightning address.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: { showGenerateKeyConfirm = true }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Generate")
                    }
                    .font(.subheadline)
.foregroundStyle(Color.accentColor)
                }

                Spacer()

                Button(action: { showImportNsec = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                    .font(.subheadline)
.foregroundStyle(Color.accentColor)
                }

                Spacer()

                if nostrService.signerType == .privateKey {
                    Button(action: { showResetKeyConfirm = true }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.top, 12)

            if let error = nostrKeyError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .alert("Generate New Key", isPresented: $showGenerateKeyConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Generate", role: .destructive) {
                generateNewKey()
            }
        } message: {
            Text("This will create a new random Nostr key. Your Lightning address will change. The old key will be replaced.")
        }
        .alert("Reset to Wallet Seed", isPresented: $showResetKeyConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetToSeedKey()
            }
        } message: {
            Text("This will switch back to the Nostr key derived from your wallet seed. Your custom key will be deleted.")
        }
        .sheet(isPresented: $showImportNsec) {
            ImportNsecSheet(
                nsecText: $importNsecText,
                onImport: importNsec
            )
        }
    }

    // MARK: - Subviews

    private func signerTypeRow(_ type: NostrSignerType) -> some View {
        Button(action: {
            switchSignerType(to: type)
        }) {
            GroupBox {
                HStack {
                    Image(systemName: nostrService.signerType == type ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(nostrService.signerType == type ? Color.accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.displayName)
                            .font(.subheadline)
                        Text(type.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Actions

    private func copyNsec() {
        UIPasteboard.general.string = nostrService.getNsec()
        copiedNsec = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedNsec = false
        }
    }

    private func generateNewKey() {
        nostrKeyError = nil
        do {
            try nostrService.generateRandomKeypair()
        } catch {
            nostrKeyError = error.localizedDescription
        }
    }

    private func importNsec() {
        nostrKeyError = nil
        let nsec = importNsecText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nsec.isEmpty else {
            nostrKeyError = "Please enter an nsec"
            return
        }
        do {
            try nostrService.importNsec(nsec)
            importNsecText = ""
            showImportNsec = false
        } catch {
            nostrKeyError = error.localizedDescription
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
        nostrKeyError = nil
        if type == .privateKey && !nostrService.hasCustomPrivateKey() {
            showGenerateKeyConfirm = true
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

struct NostrRelaysSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    @Binding var relayInput: String
    @Binding var relayError: String?
    @Binding var copiedRelay: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Relay servers")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Manage your Nostr relay list for compatible features like npub.cash and backups.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField("wss://relay.example.com", text: $relayInput)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                Button(action: addRelay) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(relayInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : Color.accentColor)
                }
                .disabled(relayInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add relay")
            }

            ForEach(settings.nostrRelays, id: \.self) { relay in
                GroupBox {
                    HStack(spacing: 12) {
                        Text(relay)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button(action: { copyRelay(relay) }) {
                            Image(systemName: copiedRelay == relay ? "checkmark" : "doc.on.doc")
                                .foregroundColor(copiedRelay == relay ? .green : Color.accentColor)
                        }
                        .accessibilityLabel("Copy relay URL")

                        Button(action: { settings.removeNostrRelay(relay) }) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Remove relay")
                    }
                }
            }

            if let relayError {
                Text(relayError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Button(action: {
                settings.resetNostrRelaysToDefault()
                relayError = nil
            }) {
                Text("Reset default relays")
                    .font(.caption)
.foregroundStyle(Color.accentColor)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
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
        copiedRelay = relay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedRelay == relay {
                copiedRelay = nil
            }
        }
    }
}
