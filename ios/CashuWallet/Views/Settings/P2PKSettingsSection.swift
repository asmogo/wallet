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
                        .toolbarIconTapTarget()
                }
                .accessibilityLabel("How locking works")
            }
        }
        .sheet(isPresented: $showExplainer) {
            LockedEcashExplainerSheet()
        }
        .sheet(item: $activeQR) { payload in
            QRCodeDetailSheet(title: payload.title, content: payload.content)
                .flatBottomSheetSurface()
        }
        .sheet(item: $privateKeyReveal) { reveal in
            PrivateKeyRevealSheet(title: reveal.title, nsec: reveal.nsec)
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
        ConfirmationToast.show("Copied key")
    }
}

// MARK: - Shared key card

/// The canonical card for a single key, used for both the primary key (on the
/// hub) and a device-only key (on its detail screen) so they read as one family:
/// a key glyph, a name, a backup-status line, the tap-to-copy npub, and up to two
/// action buttons. Also reused by the Nostr settings hub (`NostrKeysSettingsSection`)
/// so the two key surfaces stay identical.
struct KeyCard: View {
    enum Status {
        case seedBacked     // recoverable from the seed phrase
        case custom         // a custom key the user must back up themselves
        case deviceOnly     // a random device-only key, not in the seed backup

        /// nil renders no status line — a custom key's backup burden is carried
        /// by the import confirmation, not a permanent orange badge on the card.
        var text: String? {
            switch self {
            case .seedBacked: return "Backed up by your seed phrase"
            case .custom:     return nil
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
    let onCopy: () -> Void
    let actions: [Action]
    /// Overrides the displayed short value. The Nostr hub passes a pre-truncated
    /// npub so a bech32 key isn't routed through the P2PK compressed-hex formatter.
    var displayLabel: String? = nil

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
                    if let statusText = status.text {
                        Label(statusText, systemImage: status.systemImage)
                            .font(.caption)
                            .foregroundStyle(status.tint)
                            .labelStyle(.titleAndIcon)
                    }
                }
                Spacer(minLength: 0)
            }

            Button(action: onCopy) {
                HStack(spacing: 8) {
                    Text(displayLabel ?? P2PKKeyDisplay.shortLabel(forPubkey: pubkey))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy this key")

            if !actions.isEmpty {
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
                            .onChange(of: nameText) { _, _ in saveName() }
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
        .onDisappear { saveName() }
        .onChange(of: key == nil) { _, removed in if removed { dismiss() } }
        .sheet(item: $activeQR) { payload in
            QRCodeDetailSheet(title: payload.title, content: payload.content)
                .flatBottomSheetSurface()
        }
        .sheet(item: $privateKeyReveal) { reveal in
            PrivateKeyRevealSheet(title: reveal.title, nsec: reveal.nsec)
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
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (key?.nickname ?? "") else { return }
        settings.setP2PKKeyNickname(nameText, for: keyId)
    }

    private func copy(_ value: String, label: String) {
        UIPasteboard.general.string = value
        HapticFeedback.selection()
        ConfirmationToast.show("Copied key")
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
        .flatBottomSheetSurface()
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

/// Reveals a key's nsec behind authentication, matching `BackupView` (the
/// seed-phrase reveal) beat for beat: in-content title, warning copy, and one
/// CTA that flips from Reveal to Copy once the key is showing, on a
/// content-fit sheet dismissed by drag. Shared by the Locked Ecash hub and the
/// Nostr settings hub — the caveat line is caller-supplied so each reads
/// accurately (ecash-claim vs. Lightning-address control).
struct PrivateKeyRevealSheet: View {
    let title: String
    let nsec: String
    var warning: String = "Anyone with this key can claim ecash locked to it. Never share it."

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 24) {
            Text(title)
                .font(.title2.weight(.semibold))

            Text(warning)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if revealed {
                Text(nsec)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityLabel("Private key, \(nsec)")
            }

            // Reveal is the sheet's one primary action; once the key is showing,
            // Copy is a quieter follow-up and drops to the secondary style.
            if revealed {
                Button("Copy Private Key") { copyKey() }
                    .flatSheetSecondaryButton()
            } else {
                Button("Reveal Private Key") { revealKey() }
                    .glassButton()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .contentFitMeasured { contentHeight = $0 }
        .contentFitDetent(
            contentHeight,
            estimate: revealed ? 340 : 250,
            navigationBar: false,
            step: revealed,
            stepResize: .milliseconds(300)
        )
        .presentationDragIndicator(.visible)
        .flatBottomSheetSurface()
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: revealed)
    }

    /// Revealing always requires authentication, regardless of the App Lock setting.
    private func revealKey() {
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
            ConfirmationToast.show("Copied private key")
        }
    }
}
