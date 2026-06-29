import SwiftUI

// MARK: - Key display helpers

/// Formatting for P2PK keys so they read the same everywhere (this hub, the Send
/// lock chip, the receive token detail). P2PK keys are shown and shared as the
/// 33-byte compressed hex ("02…") — the form Cashu wallets expect; we never
/// re-encode them as npub.
enum P2PKKeyDisplay {
    /// The canonical public key for copy / QR: the stored compressed hex ("02…"),
    /// normalized for casing and whitespace.
    static func canonical(forPubkey pubkey: String) -> String {
        pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// A short, scannable label: middle-truncated hex ("02e56288aa5c…2ef6607a91e00").
    static func shortLabel(forPubkey pubkey: String) -> String {
        middleTruncate(canonical(forPubkey: pubkey), lead: 12, tail: 12)
    }

    /// nsec (bech32) for a 32-byte private-key hex — used only when backing up a key.
    static func nsec(forPrivateKeyHex hex: String) -> String? {
        guard let data = Data(hex: hex), data.count == 32 else { return nil }
        return try? Bech32.encode(hrp: "nsec", data: data)
    }

    static func middleTruncate(_ s: String, lead: Int, tail: Int) -> String {
        guard s.count > lead + tail + 1 else { return s }
        return "\(s.prefix(lead))…\(s.suffix(tail))"
    }
}

/// Identifies a private key the user has chosen to reveal/back up.
private struct PrivateKeyReveal: Identifiable {
    let id: String          // the public key, used as a stable identity
    let title: String
    let nsec: String
}

// MARK: - Locked Ecash hub

/// The "Locked Ecash" settings hub: explains P2PK in plain language and surfaces
/// the recoverable seed-derived primary key. Disposable device-only keys live on
/// a pushed Advanced screen. Self-contained — owns its own sheets.
struct P2PKSettingsSection: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var nostr = NostrService.shared

    @State private var showExplainer = false
    @State private var activeQR: QRPayload?
    @State private var copiedValue: String?
    @State private var privateKeyReveal: PrivateKeyReveal?

    var body: some View {
        LazyVStack(spacing: 0) {
            Text("Lock ecash to a key so only its holder can claim it — even if the token is intercepted in transit.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .padding(.bottom, 28)

            SettingsSectionGroup("Your key") {
                primaryKeyCard
            }
            SettingsSectionFooter {
                Text("Show your QR or share this key, and anyone can send you locked ecash. The key comes from your seed phrase, so only you can claim it.")
            }

            SettingsSectionGroup("When sending") {
                Toggle(isOn: $settings.showP2PKButtonInDrawer.animation(.easeInOut(duration: 0.2))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick lock to my key")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("Show a “Lock to my key” shortcut when sending ecash.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
            }

            SettingsSectionGroup(nil) {
                NavigationLink {
                    AdvancedKeysView()
                } label: {
                    HStack(spacing: 14) {
                        SettingsRowIcon(systemName: "ellipsis.circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Advanced keys")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(advancedSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
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
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { HapticFeedback.selection(); showExplainer = true } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("How locking works")
            }
        }
        .sheet(isPresented: $showExplainer) {
            LockedEcashExplainerSheet()
        }
        .sheet(item: $activeQR) { payload in
            QRCodeDetailSheet(title: payload.title, content: payload.content)
                .canvasSheetBackground()
        }
        .sheet(item: $privateKeyReveal) { reveal in
            PrivateKeyRevealSheet(title: reveal.title, nsec: reveal.nsec)
                .canvasSheetBackground()
        }
    }

    private var advancedSubtitle: String {
        let count = settings.p2pkKeys.count
        if count == 0 { return "Add a key that lives only on this device" }
        return count == 1 ? "1 device key" : "\(count) device keys"
    }

    // MARK: Primary key

    @ViewBuilder
    private var primaryKeyCard: some View {
        if let pubkey = settings.primaryP2PKPublicKey {
            KeyCard(
                title: "Your key",
                pubkey: pubkey,
                status: settings.primaryP2PKIsSeedBacked
                    ? .seedBacked
                    : .custom,
                copiedValue: copiedValue,
                onCopy: { copy(P2PKKeyDisplay.canonical(forPubkey: pubkey), label: "key") },
                actions: [
                    .init(title: "Show QR", systemImage: "qrcode") { showPrimaryRequest(pubkey: pubkey) },
                    .init(title: "Reveal key", systemImage: "eye") { revealPrimaryPrivateKey() },
                ]
            )
        } else {
            HStack(spacing: 12) {
                Image(systemName: "key")
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: Circle())
                Text("Your key appears once your wallet finishes setting up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: Actions

    private func showPrimaryRequest(pubkey: String) {
        if let encoded = LockedReceiveRequest.build() {
            activeQR = QRPayload(title: "Receive Locked Ecash", content: encoded)
        } else {
            // No Nostr transport available — fall back to sharing the raw key.
            activeQR = QRPayload(title: "Your Key", content: P2PKKeyDisplay.canonical(forPubkey: pubkey))
        }
    }

    private func revealPrimaryPrivateKey() {
        guard let hex = settings.primaryP2PKPrivateKeyHex,
              let nsec = P2PKKeyDisplay.nsec(forPrivateKeyHex: hex) else { return }
        privateKeyReveal = PrivateKeyReveal(id: "primary", title: "Your Key", nsec: nsec)
    }

    private func copy(_ value: String, label: String) {
        UIPasteboard.general.string = value
        HapticFeedback.selection()
        withAnimation { copiedValue = label }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedValue == label { withAnimation { copiedValue = nil } }
        }
    }
}

// MARK: - Shared key card

/// The canonical card for a single key, used for both the primary key (on the
/// hub) and a device-only key (on its detail screen) so they read as one family:
/// a key glyph, a name, a backup-status line, the tap-to-copy npub, and up to two
/// action buttons.
private struct KeyCard: View {
    enum Status {
        case seedBacked     // recoverable from the seed phrase
        case custom         // a custom key the user must back up themselves
        case deviceOnly     // a random device-only key, not in the seed backup

        var text: String {
            switch self {
            case .seedBacked: return "Backed up by your seed phrase"
            case .custom:     return "Custom key — back it up yourself"
            case .deviceOnly: return "On this device only — not in your seed backup"
            }
        }
        var systemImage: String {
            switch self {
            case .seedBacked: return "checkmark.seal.fill"
            case .custom, .deviceOnly: return "exclamationmark.triangle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .seedBacked: return .secondary
            case .custom, .deviceOnly: return .orange
            }
        }
    }

    struct Action: Identifiable {
        var id: String { title }
        let title: String
        let systemImage: String
        let perform: () -> Void
    }

    let title: String
    let pubkey: String
    let status: Status
    let copiedValue: String?
    let onCopy: () -> Void
    let actions: [Action]

    private var isCopied: Bool { copiedValue == "key" || copiedValue == pubkey }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Label(status.text, systemImage: status.systemImage)
                        .font(.caption)
                        .foregroundStyle(status.tint)
                        .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
            }

            Button(action: onCopy) {
                HStack(spacing: 8) {
                    Text(P2PKKeyDisplay.shortLabel(forPubkey: pubkey))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCopied ? Color.green : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy this key")

            if !actions.isEmpty {
                CanvasDivider(inset: 0)
                HStack(spacing: 0) {
                    ForEach(actions) { action in
                        Button(action: { HapticFeedback.selection(); action.perform() }) {
                            VStack(spacing: 4) {
                                Image(systemName: action.systemImage)
                                    .font(.body.weight(.medium))
                                Text(action.title)
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Advanced (device-only) keys screen

/// A dedicated screen for disposable device-only keys: generate, import, and
/// browse. Each key opens its own detail screen. Pushed from the Locked Ecash hub
/// so the main screen stays calm.
private struct AdvancedKeysView: View {
    @ObservedObject private var settings = SettingsManager.shared

    @State private var showImport = false
    @State private var importText = ""
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                SettingsSectionGroup(nil) {
                    Button(action: generateKey) {
                        actionRow("Generate a key", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)

                    CanvasDivider()

                    Button(action: { actionError = nil; importText = ""; showImport = true }) {
                        actionRow("Import a key", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                }

                if let actionError {
                    InlineNotice(message: actionError, severity: .error)
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                        .transition(.opacity)
                }

                if settings.p2pkKeys.isEmpty {
                    SettingsSectionFooter {
                        Text("Device-only keys are stored on this device, not in your seed backup. If you lose this device, ecash locked to them is gone — keep amounts small.")
                    }
                } else {
                    SettingsSectionGroup("Device keys") {
                        ForEach(Array(settings.p2pkKeys.enumerated()), id: \.element.id) { index, key in
                            if index > 0 { CanvasDivider() }
                            keyRow(key)
                        }
                    }
                    SettingsSectionFooter {
                        Text("These keys aren't in your seed backup. Back up each one, or keep amounts small.")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Advanced Keys")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.2), value: settings.p2pkKeys)
        .animation(.easeInOut(duration: 0.2), value: actionError)
        .sheet(isPresented: $showImport) {
            ImportP2PKSheet(nsecText: $importText) { importKey() }
        }
    }

    private func actionRow(_ title: String, systemImage: String) -> some View {
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

    private func keyRow(_ key: P2PKKey) -> some View {
        NavigationLink {
            DeviceKeyDetailView(keyId: key.id)
        } label: {
            HStack(spacing: 14) {
                SettingsRowIcon(systemName: "key")
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.nickname?.isEmpty == false ? key.nickname! : P2PKKeyDisplay.shortLabel(forPubkey: key.publicKey))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text("Device only")
                        if key.usedCount > 0 {
                            Text("·")
                            Text(key.usedCount == 1 ? "Used once" : "Used \(key.usedCount) times")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { HapticFeedback.selection() })
    }

    private func generateKey() {
        actionError = nil
        HapticFeedback.selection()
        if !settings.generateP2PKKey() {
            actionError = "Couldn't generate a key. Please try again."
        }
    }

    private func importKey() {
        actionError = nil
        do {
            try settings.importP2PKNsec(importText)
            importText = ""
            showImport = false
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Device key detail

/// One device-only key, with everything you can do to it laid out as plain rows
/// — copy, show QR, back up, rename, remove — instead of a floating menu. Resolves
/// the key live from settings so a rename updates in place; pops if it's removed.
private struct DeviceKeyDetailView: View {
    let keyId: UUID

    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var activeQR: QRPayload?
    @State private var privateKeyReveal: PrivateKeyReveal?
    @State private var copiedValue: String?
    @State private var nameText = ""
    @State private var showRemoveConfirm = false

    private var key: P2PKKey? { settings.p2pkKeys.first { $0.id == keyId } }

    var body: some View {
        ScrollView {
            if let key {
                VStack(spacing: 0) {
                    KeyCard(
                        title: key.nickname?.isEmpty == false ? key.nickname! : "Device key",
                        pubkey: key.publicKey,
                        status: .deviceOnly,
                        copiedValue: copiedValue,
                        onCopy: { copy(P2PKKeyDisplay.canonical(forPubkey: key.publicKey), label: key.publicKey) },
                        actions: [
                            .init(title: "Show QR", systemImage: "qrcode") {
                                activeQR = QRPayload(title: "Key", content: P2PKKeyDisplay.canonical(forPubkey: key.publicKey))
                            },
                            .init(title: "Back up key", systemImage: "key") { backUp(key) },
                        ]
                    )
                    .padding(.top, 8)

                    SettingsSectionGroup("Name") {
                        TextField("Add a name", text: $nameText)
                            .font(.body)
                            .submitLabel(.done)
                            .onSubmit { saveName() }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 14)
                    }

                    SettingsSectionGroup(nil) {
                        Button(role: .destructive, action: { showRemoveConfirm = true }) {
                            HStack(spacing: 14) {
                                SettingsRowIcon(systemName: "trash", tint: .red)
                                Text("Remove Key")
                                    .font(.body)
                                    .foregroundStyle(.red)
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    SettingsSectionFooter {
                        Text("Ecash locked to this key can only be claimed with it. Removing it can't be undone — back it up first if you might still receive to it.")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(key?.nickname?.isEmpty == false ? key!.nickname! : "Device Key")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { nameText = key?.nickname ?? "" }
        .onChange(of: key == nil) { _, removed in if removed { dismiss() } }
        .sheet(item: $activeQR) { payload in
            QRCodeDetailSheet(title: payload.title, content: payload.content)
                .canvasSheetBackground()
        }
        .sheet(item: $privateKeyReveal) { reveal in
            PrivateKeyRevealSheet(title: reveal.title, nsec: reveal.nsec)
                .canvasSheetBackground()
        }
        .alert("Remove this key?", isPresented: $showRemoveConfirm) {
            Button("Remove Key", role: .destructive) {
                if let key { settings.removeP2PKKey(key) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ecash locked to this key can only be claimed with it. This can't be undone.")
        }
    }

    private func backUp(_ key: P2PKKey) {
        guard let nsec = P2PKKeyDisplay.nsec(forPrivateKeyHex: key.privateKey) else { return }
        privateKeyReveal = PrivateKeyReveal(id: key.publicKey, title: "Back up key", nsec: nsec)
    }

    private func saveName() {
        settings.setP2PKKeyNickname(nameText, for: keyId)
    }

    private func copy(_ value: String, label: String) {
        UIPasteboard.general.string = value
        HapticFeedback.selection()
        withAnimation { copiedValue = label }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedValue == label { withAnimation { copiedValue = nil } }
        }
    }
}

// MARK: - Educational sheet

/// Plain-language explainer for locked ecash, modeled on the onboarding
/// "What is ecash?" concept sheet — heavy title, secondary prose, single CTA.
private struct LockedEcashExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Locked ecash")
                    .font(.title.weight(.heavy))
                    .tracking(-0.3)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 16) {
                    explainerPoint(
                        "lock.open",
                        "Ecash is bearer cash. Whoever holds a token can spend it — like a banknote."
                    )
                    explainerPoint(
                        "lock",
                        "Locking ties a token to a key. Even if it's intercepted in transit, only the key's holder can claim it."
                    )
                    explainerPoint(
                        "key.fill",
                        "Your key comes from your seed phrase, so it's backed up automatically. Share your key or QR, and anyone can send you locked ecash."
                    )
                    explainerPoint(
                        "paperplane",
                        "When you send, you can lock ecash to someone else's key so only they can claim it."
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .padding(.bottom, 80)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: { dismiss() }) { Text("Got it") }
                .glassButton()
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func explainerPoint(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(width: 24)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Private-key reveal sheet

/// Reveals a key's nsec behind authentication, mirroring the seed-phrase backup
/// pattern: hidden by default, reveal and copy both require auth.
private struct PrivateKeyRevealSheet: View {
    let title: String
    let nsec: String

    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var copied = false

    private var hidden: String {
        String(repeating: "•", count: 24)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text("Keep this key secret")
                            .font(.headline)
                        Text("Anyone with this key can claim ecash locked to it. Never share it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Private key (nsec)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        HStack(spacing: 10) {
                            Text(revealed ? nsec : hidden)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(revealed ? .primary : .secondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            VStack(spacing: 8) {
                                Button(action: toggleReveal) {
                                    Image(systemName: revealed ? "eye.slash" : "eye")
                                }
                                Button(action: copyKey) {
                                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                        .foregroundStyle(copied ? .green : Color.accentColor)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                    Spacer(minLength: 40)

                    Button(action: { dismiss() }) { Text("Done") }
                        .glassButton()
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func toggleReveal() {
        if revealed { revealed = false; return }
        Task {
            if await AppLockManager.shared.authenticate(reason: "Reveal this private key") {
                revealed = true
            }
        }
    }

    private func copyKey() {
        Task {
            guard await AppLockManager.shared.authenticate(reason: "Copy this private key") else { return }
            UIPasteboard.general.string = nsec
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { copied = false }
        }
    }
}
