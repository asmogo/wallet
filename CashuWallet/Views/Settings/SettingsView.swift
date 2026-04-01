import SwiftUI

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
    @State private var showRestoreFlowAlert = false
    @State private var p2pkImportText = ""
    @State private var showImportP2PK = false
    @State private var p2pkError: String?
    @State private var nwcError: String?
    @State private var expandedP2PKKeys = false
    @State private var activeQRPayload: QRPayload?
    @State private var copiedNWCConnectionId: UUID?
    @State private var copiedP2PKPublicKey: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                        sectionHeader("BACKUP & RESTORE")
                        BackupSettingsSection(
                            showBackup: $showBackup,
                            showRestoreFlowAlert: $showRestoreFlowAlert
                        )

                        sectionHeader("LIGHTNING ADDRESS")
                        LightningAddressSettingsSection(
                            copiedLightningAddress: $copiedLightningAddress,
                            isCheckingPayments: $isCheckingPayments,
                            showMintPicker: $showMintPicker
                        )

                        sectionHeader("NOSTR")
                        NostrKeysSettingsSection(
                            showNsec: $showNsec,
                            copiedNsec: $copiedNsec,
                            showImportNsec: $showImportNsec,
                            importNsecText: $importNsecText,
                            showGenerateKeyConfirm: $showGenerateKeyConfirm,
                            showResetKeyConfirm: $showResetKeyConfirm,
                            nostrKeyError: $nostrKeyError
                        )
                        NostrRelaysSettingsSection(
                            relayInput: $relayInput,
                            relayError: $relayError,
                            copiedRelay: $copiedRelay
                        )

                        sectionHeader("PAYMENT REQUESTS")
                        PaymentRequestsSettingsSection()

                        sectionHeader("NOSTR WALLET CONNECT")
                        NWCSettingsSection(
                            nwcError: $nwcError,
                            copiedNWCConnectionId: $copiedNWCConnectionId,
                            activeQRPayload: $activeQRPayload
                        )

                        sectionHeader("P2PK FEATURES")
                        P2PKSettingsSection(
                            expandedP2PKKeys: $expandedP2PKKeys,
                            activeQRPayload: $activeQRPayload,
                            copiedP2PKPublicKey: $copiedP2PKPublicKey,
                            p2pkImportText: $p2pkImportText,
                            showImportP2PK: $showImportP2PK,
                            p2pkError: $p2pkError
                        )

                        sectionHeader("PRIVACY")
                        PrivacySettingsSection()

                        sectionHeader("APPEARANCE")
                        ThemeSettingsSection()

                        sectionHeader("WALLET INFO")
                        infoRow(label: "Balance", value: settings.formatAmount(walletManager.balance))
                        infoRow(label: "Mints", value: "\(walletManager.mints.count)")
                        infoRow(label: "Unit", value: settings.unitLabel)
                        infoRow(label: "Version", value: "1.0.0")

                        sectionHeader("ABOUT")
                        linkRow(
                            icon: "globe",
                            title: "Learn about Cashu",
                            subtitle: "cashu.space",
                            url: "https://cashu.space"
                        )
                        linkRow(
                            icon: "doc.text",
                            title: "Protocol Specs (NUTs)",
                            subtitle: "github.com/cashubtc/nuts",
                            url: "https://github.com/cashubtc/nuts"
                        )

                        sectionHeader("ADVANCED")
                        AdvancedSettingsSection(
                            showDeleteConfirm: $showDeleteConfirm
                        )

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal)
                }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.headline)
                }
            }
            .sheet(isPresented: $showBackup) {
                BackupView()
                    .environmentObject(walletManager)
            }
            .sheet(isPresented: $showImportP2PK) {
                ImportP2PKSheet(
                    nsecText: $p2pkImportText,
                    onImport: importP2PKNsec
                )
            }
            .sheet(item: $activeQRPayload) { payload in
                QRCodeDetailSheet(title: payload.title, content: payload.content)
            }
            .alert("Open Restore Wizard", isPresented: $showRestoreFlowAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open") {
                    walletManager.needsOnboarding = true
                }
            } message: {
                Text("This will open the restore flow used during onboarding.")
            }
            .alert("Delete Wallet", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteWallet()
                }
            } message: {
                Text("Are you sure you want to delete your wallet? This action cannot be undone. Make sure you have backed up your seed phrase!")
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 32)
            .padding(.bottom, 8)
    }

    private func infoRow(label: String, value: String) -> some View {
        LabeledContent(label, value: value)
            .font(.subheadline)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func linkRow(icon: String, title: String, subtitle: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                linkRowLabel(icon: icon, title: title, subtitle: subtitle)
            }
        } else {
            linkRowLabel(icon: icon, title: title, subtitle: subtitle)
        }
    }

    private func linkRowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
.foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    private func deleteWallet() {
        try? KeychainService().deleteMnemonic()
        walletManager.needsOnboarding = true
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

// MARK: - Shared Types

struct QRPayload: Identifiable {
    let id = UUID()
    let title: String
    let content: String
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
                    .cornerRadius(12)

                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal)

                Button(action: copyToClipboard) {
                    HStack {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                }
                .buttonStyle(.bordered).controlSize(.large)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
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
            VStack(spacing: 20) {
                Text("Import P2PK nsec")
                    .font(.headline)

                Text("Import an nsec key to add a P2PK locking key.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("nsec1...", text: $nsecText)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                    if let validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        Button(action: {
                            if validate() {
                                onImport()
                            }
                        }) {
                            Text("Import nsec")
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(nsecText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(action: { dismiss() }) {
                            Text("Cancel")
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
            .padding(.top, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Import P2PK")
                        .font(.headline)
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
                    // Warning
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
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

                    GroupBox("Seed phrase") {
                        HStack(spacing: 10) {
                            Text(showWords ? mnemonic : hiddenMnemonic)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(showWords ? .primary : .secondary)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)

                            VStack(spacing: 8) {
                                Button(action: { showWords.toggle() }) {
                                    Image(systemName: showWords ? "eye.slash" : "eye")
                                        .foregroundStyle(Color.accentColor)
                                }

                                Button(action: copyToClipboard) {
                                    Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                        .foregroundColor(copiedToClipboard ? .green : Color.accentColor)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 50)

                    Button(action: { dismiss() }) {
                        Text("DONE")
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Backup")
                        .font(.headline)
                }
            }
        }
    }

    private func copyToClipboard() {
        let words = walletManager.getMnemonicWords().joined(separator: " ")
        UIPasteboard.general.string = words
        copiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copiedToClipboard = false
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
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(mints, id: \.url) { mint in
                        Button(action: {
                            selectedMintUrl = mint.url
                            onSelect(mint.url)
                            dismiss()
                        }) {
                            GroupBox {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(mint.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)

                                        Text(mint.url)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    if selectedMintUrl == mint.url {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Select Mint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Select Mint")
                        .font(.headline)
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
            VStack(spacing: 24) {
                // Instructions
                VStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)

                    Text("Import Nostr Key")
                        .font(.headline)

                    Text("Enter your nsec (Nostr private key) to use it for your Lightning address.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()

                // nsec input
                VStack(alignment: .leading, spacing: 8) {
                    Text("nsec")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("nsec1...", text: $nsecText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)

                // Paste from clipboard button
                Button(action: pasteFromClipboard) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste from Clipboard")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        if validateNsec() {
                            onImport()
                        }
                    }) {
                        Text("Import Key")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(nsecText.isEmpty)

                    Button(action: { dismiss() }) {
                        Text("Cancel")
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Import Key")
                        .font(.headline)
                }
            }
        }
    }

    private func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            nsecText = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
