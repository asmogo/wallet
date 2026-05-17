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
                LazyVStack(spacing: 0) {
                    sectionGroup(title: "Backup") {
                        navRow("Backup & Restore", icon: "key.fill") {
                            backupDetailView
                        }
                    }

                    sectionGroup(title: "Payments") {
                        navRow("Lightning", icon: "bolt.fill") {
                            lightningDetailView
                        }
                        CanvasDivider()
                        navRow("Payment Requests", icon: "arrow.left.arrow.right") {
                            paymentRequestsDetailView
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
                        CanvasDivider()
                        navRow("Nostr Wallet Connect", icon: "link") {
                            nwcDetailView
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
                    showBackup: $showBackup,
                    showRestoreFlowAlert: $showRestoreFlowAlert
                )
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("Backup & Restore")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var lightningDetailView: some View {
        List {
            Section {
                LightningAddressSettingsSection(
                    copiedLightningAddress: $copiedLightningAddress,
                    isCheckingPayments: $isCheckingPayments,
                    showMintPicker: $showMintPicker
                )
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
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

    private var paymentRequestsDetailView: some View {
        List {
            Section {
                PaymentRequestsSettingsSection()
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("Payment Requests")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var nwcDetailView: some View {
        List {
            Section {
                NWCSettingsSection(
                    nwcError: $nwcError,
                    copiedNWCConnectionId: $copiedNWCConnectionId,
                    activeQRPayload: $activeQRPayload
                )
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("Nostr Wallet Connect")
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
                    .clipShape(.rect(cornerRadius: 12))

                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal)

                Button(action: copyToClipboard) {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .glassButton()
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
                                Button(action: { showWords.toggle() }) {
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
