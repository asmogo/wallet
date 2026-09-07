import SwiftUI
import Cdk

struct MintDetailView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let mint: MintInfo

    /// Navigation carries a stable URL, while balances and metadata keep
    /// following WalletManager publications after this screen is open.
    private var liveMint: MintInfo {
        walletManager.mints.first(where: { $0.url == mint.url }) ?? mint
    }

    @State private var infoLoader = MintDetailInfoLoader<Cdk.MintInfo>()
    @State private var refreshID = UUID()

    @State private var showRemoveConfirmation = false
    @State private var nutsExpanded = false
    @State private var aboutExpanded = false
    @State private var showNavTitle = false
    @State private var isSettingDefault = false
    @State private var isRemovingMint = false
    @State private var actionError: String?
    /// Balances for the mint's non-sat units, loaded on demand (the sat balance
    /// is the cached `mint.balance`). Where a freshly-minted eur/usd shows up.
    @State private var unitBalances: [String: UInt64] = [:]
    @State private var storedUnits: [String] = []

    private var cdkInfo: Cdk.MintInfo? { infoLoader.info }
    private var isLoading: Bool { infoLoader.isLoading }
    private var showsConnectionRecovery: Bool { infoLoader.errorMessage != nil }

    /// The mint's non-sat units (sat is shown by `balanceRow`).
    private var nonSatUnits: [String] {
        Set(liveMint.units + storedUnits).filter { $0.lowercased() != "sat" }.sorted()
    }

    private var isDefaultMint: Bool {
        walletManager.activeMint?.url == liveMint.url
    }

    private var showFiat: Bool {
        settings.showFiatBalance && priceService.btcPriceUSD > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                // Identity stats — available immediately from local mint data.
                VStack(spacing: 0) {
                    balanceRow
                    // Per-unit balances for a multi-unit mint (e.g. a minted €5).
                    ForEach(nonSatUnits, id: \.self) { unit in
                        unitBalanceRow(unit)
                    }
                    connectionRow
                }
                .padding(.bottom, 24)

                // Saved metadata remains visible during initial loading and retries.
                aboutSection
                motdSection
                capabilitiesSection
                paymentMethodsSection
                contactSection
                detailsSection

                footerNote

                actions
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > 120
        } action: { _, newValue in
            showNavTitle = newValue
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(liveMint.name)
                    .font(.headline)
                    .opacity(showNavTitle ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showNavTitle)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: liveMint.url) {
                    Image(systemName: "square.and.arrow.up")
                        .toolbarIconTapTarget()
                }
                .accessibilityLabel("Share mint")
            }
        }
        .task(id: refreshID) { await loadMintInfo() }
        .task { await loadUnitBalances() }
        .backdropSheet(isPresented: $showRemoveConfirmation) {
            ActionConfirmationSheet(
                title: "Remove mint?",
                message: "Remove \(liveMint.name) from your wallet? Any unspent ecash on this mint will need to be restored from your seed phrase.",
                actionLabel: "Remove",
                destructive: true,
                action: removeMint
            )
        }
        .bottomSheetBackdropHost()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            mintIcon
                .overlay(alignment: .bottomTrailing) {
                    if isDefaultMint { defaultDot }
                }
            Text(liveMint.name)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            copyUrlChip
            if isDefaultMint { defaultBadge }
        }
        .frame(maxWidth: .infinity)
    }

    // Default-mint indicator on the mint icon. Green here is a documented
    // One Green Rule carve-out (DESIGN.md): it marks the user's selected
    // default mint, matching the dot in MintsListView.
    private var defaultDot: some View {
        Circle()
            .fill(.green)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
            .offset(x: 3, y: 3)
    }

    private var defaultBadge: some View {
        Text("Default mint")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary)
            .accessibilityLabel("This is your default mint")
    }

    @ViewBuilder
    private var mintIcon: some View {
        // Prefer live CDK info, but fall back to the persisted mint icon so the
        // header doesn't blank while `loadMintInfo()` is in flight.
        let iconURLString = cdkInfo?.iconUrl ?? liveMint.iconUrl
        if let iconURLString, let url = URL(string: iconURLString) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                mintIconPlaceholder
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            mintIconPlaceholder
        }
    }

    private var copyUrlChip: some View {
        Button(action: copyUrl) {
            HStack(spacing: 4) {
                Text(liveMint.url)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy mint URL")
    }

    // MARK: - Identity stats

    private var balanceRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Balance", systemImage: "bitcoinsign")
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(AmountFormatter.sats(liveMint.balance, useBitcoinSymbol: settings.useBitcoinSymbol))
                    .monospacedDigit()
                if showFiat, let fiatBalance = priceService.formatSatsAsFiat(liveMint.balance) {
                    Text(fiatBalance)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.body)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    private func unitBalanceRow(_ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Balance (\(unit.uppercased()))", systemImage: "banknote")
                .foregroundStyle(.secondary)
            Spacer()
            Text(unitBalances[unit].map {
                CurrencyAmount(value: $0, currency: CurrencyRegistry.currency(forMintUnit: unit)).formatted()
            } ?? "…")
                .monospacedDigit()
        }
        .font(.body)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    private var connectionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("Connection", systemImage: "network")
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Spacer(minLength: 12)
                    connectionStatus.fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Connection", systemImage: "network")
                        .foregroundStyle(.secondary)
                    connectionStatus
                }
            }
            .font(.body)
            .accessibilityElement(children: .combine)

            if showsConnectionRecovery {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        connectionRecoveryText.fixedSize()
                        Spacer(minLength: 0)
                        connectionRetryButton
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        connectionRecoveryText
                        connectionRetryButton
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .onChange(of: infoLoader.connection) { _, connection in
            if connection == .offline {
                AccessibilityNotification.Announcement(
                    "Mint unreachable. Couldn't refresh mint information. Showing saved information."
                ).post()
            } else if connection == .online {
                AccessibilityNotification.Announcement("Mint online.").post()
            }
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch infoLoader.connection {
        case .notChecked:
            Text("Not checked").foregroundStyle(.secondary)
        case .checking:
            if showsConnectionRecovery {
                Text("Refreshing").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().accessibilityHidden(true)
                    Text("Checking…").foregroundStyle(.secondary)
                }
            }
        case .online:
            Text("Online").foregroundStyle(.primary)
        case .offline:
            Text("Unreachable").foregroundStyle(.secondary)
        }
    }

    private var connectionRecoveryText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Couldn't refresh mint information.")
            Text("Showing saved information.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var connectionRetryButton: some View {
        Button { refreshID = UUID() } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                }
                Text(isLoading ? "Checking…" : "Retry")
            }
            .font(.subheadline.weight(.medium))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "Checking mint connection" : "Retry mint connection")
    }

    // MARK: - About / Message

    @ViewBuilder
    private var aboutSection: some View {
        let shortDesc = cdkInfo?.description ?? liveMint.description
        let longDesc = cdkInfo?.descriptionLong
        if (shortDesc?.isEmpty == false) || (longDesc?.isEmpty == false) {
            section("About") {
                VStack(alignment: .leading, spacing: 8) {
                    if let shortDesc, !shortDesc.isEmpty {
                        Text(shortDesc)
                            .font(.body)
                    }
                    if let longDesc, !longDesc.isEmpty {
                        Text(longDesc)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(aboutExpanded ? nil : 3)
                        if longDesc.count > 160 {
                            Button(aboutExpanded ? "Show less" : "Read more") {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                    aboutExpanded.toggle()
                                }
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var motdSection: some View {
        if let motd = cdkInfo?.motd, !motd.isEmpty {
            section("Message from the mint") {
                Text(motd)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Capabilities

    @ViewBuilder
    private var capabilitiesSection: some View {
        if let nuts = cdkInfo?.nuts {
            section("Capabilities") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(capabilityLines(nuts)) { capability in
                        HStack(spacing: 12) {
                            Image(systemName: capability.icon)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text(capability.text)
                                .font(.body)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                    }

                    nutDisclosure(nuts)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func nutDisclosure(_ nuts: Cdk.Nuts) -> some View {
        DisclosureGroup(
            isExpanded: $nutsExpanded.animation(
                reduceMotion ? nil : .easeInOut(duration: 0.2)
            )
        ) {
            VStack(spacing: 0) {
                nutRow("NUT-04", "Mint", true)
                nutRow("NUT-05", "Melt", true)
                nutRow("NUT-07", "Token state check", nuts.nut07Supported)
                nutRow("NUT-08", "Lightning fee return", nuts.nut08Supported)
                nutRow("NUT-09", "Restore from seed", nuts.nut09Supported)
                nutRow("NUT-10", "Spending conditions", nuts.nut10Supported)
                nutRow("NUT-11", "P2PK locking", nuts.nut11Supported)
                nutRow("NUT-12", "DLEQ proofs", nuts.nut12Supported)
                nutRow("NUT-14", "HTLCs", nuts.nut14Supported)
                nutRow("NUT-20", "WebSocket updates", nuts.nut20Supported)
            }
            .padding(.top, 4)
        } label: {
            Text("Technical details")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func nutRow(_ code: String, _ label: String, _ supported: Bool) -> some View {
        HStack(spacing: 10) {
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(label)
                .font(.caption)
                .foregroundStyle(supported ? .primary : .secondary)
            Spacer()
            Image(systemName: supported ? "checkmark" : "minus")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }

    // MARK: - Payment methods

    @ViewBuilder
    private var paymentMethodsSection: some View {
        if !receiveMethods.isEmpty || !sendMethods.isEmpty {
            section("Payment methods") {
                VStack(spacing: 0) {
                    if !receiveMethods.isEmpty {
                        paymentDirectionRow(icon: "arrow.down", label: "Receive", methods: receiveMethods)
                    }
                    if !sendMethods.isEmpty {
                        paymentDirectionRow(icon: "arrow.up", label: "Send", methods: sendMethods)
                    }
                }
            }
        }
    }

    private func paymentDirectionRow(icon: String, label: String, methods: [PaymentMethodKind]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(methods.map(\.displayName).joined(separator: " · "))
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    // MARK: - Contact

    @ViewBuilder
    private var contactSection: some View {
        if let contacts = cdkInfo?.contact, !contacts.isEmpty {
            section("Contact") {
                VStack(spacing: 0) {
                    ForEach(Array(contacts.enumerated()), id: \.offset) { index, contact in
                        if let url = contactURL(method: contact.method, info: contact.info) {
                            Link(destination: url) {
                                contactRow(method: contact.method, info: contact.info, tappable: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            contactRow(method: contact.method, info: contact.info, tappable: false)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func contactRow(method: String, info: String, tappable: Bool) -> some View {
        HStack {
            Label(method.capitalized, systemImage: contactIcon(method))
                .foregroundStyle(.secondary)
            Spacer()
            Text(info)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(tappable ? Color.accentColor : .primary)
        }
        .font(.body)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Details (software / units / ToS)

    @ViewBuilder
    private var detailsSection: some View {
        let version = cdkInfo?.version
        let showUnits = !liveMint.units.isEmpty
        let tosUrl = cdkInfo?.tosUrl.flatMap { URL(string: $0) }
        if version != nil || showUnits || tosUrl != nil {
            section("Details") {
                VStack(spacing: 0) {
                    if let version {
                        detailRow(icon: "shippingbox", label: "Software",
                                  value: "\(version.name) \(version.version)")
                    }
                    if showUnits {
                        detailRow(icon: "ruler",
                                  label: liveMint.units.count > 1 ? "Units" : "Unit",
                                  value: liveMint.units.joined(separator: ", ").uppercased())
                    }
                    if let tosUrl {
                        Link(destination: tosUrl) {
                            HStack {
                                Label("Terms of Service", systemImage: "doc.text")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.body)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.body)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    // MARK: - Footer + actions

    private var footerNote: some View {
        Text("Information reported by the mint.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 20)
    }

    private var actions: some View {
        VStack(spacing: 4) {
            if let actionError {
                InlineNotice(message: actionError, severity: .error)
                    .padding(.bottom, 8)
            }
            if !isDefaultMint {
                Button {
                    guard !isSettingDefault else { return }
                    isSettingDefault = true
                    actionError = nil
                    Task {
                        do {
                            try await walletManager.setActiveMint(liveMint)
                            ConfirmationToast.show("Default mint updated")
                        } catch {
                            actionError = error.userFacingWalletMessage
                        }
                        isSettingDefault = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Set as Default")
                        if isSettingDefault {
                            ProgressView().tint(.primary)
                        }
                    }
                }
                .glassButton()
                .disabled(isSettingDefault)
            }
            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Text("Remove mint")
                    if isRemovingMint {
                        ProgressView().tint(.red)
                    }
                }
                .font(.body)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .disabled(isRemovingMint)
        }
    }

    // MARK: - Section container

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .cashuText(.overline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            content()
        }
        .padding(.bottom, 24)
    }

    // MARK: - Capability mapping

    private struct Capability: Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    private func capabilityLines(_ nuts: Cdk.Nuts) -> [Capability] {
        var lines: [Capability] = []

        // Rails (Lightning / On-chain) live once, in the Payment methods section;
        // this section carries only the locking capability + Technical details.
        var locks: [String] = []
        if nuts.nut11Supported { locks.append("P2PK") }
        if nuts.nut14Supported { locks.append("HTLC") }
        if !locks.isEmpty {
            lines.append(Capability(icon: "lock.fill", text: "Locked ecash (\(locks.joined(separator: " · ")))"))
        }

        return lines
    }

    private func contactIcon(_ method: String) -> String {
        switch method.lowercased() {
        case "email": return "envelope"
        case "twitter", "x": return "at"
        case "nostr": return "key"
        case "website", "url", "web": return "globe"
        case "telegram": return "paperplane"
        default: return "person"
        }
    }

    private func contactURL(method: String, info: String) -> URL? {
        let trimmed = info.trimmingCharacters(in: .whitespacesAndNewlines)
        switch method.lowercased() {
        case "email":
            return URL(string: "mailto:\(trimmed)")
        case "website", "url", "web":
            return URL(string: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)")
        case "twitter", "x":
            if trimmed.hasPrefix("http") { return URL(string: trimmed) }
            let handle = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
            return URL(string: "https://twitter.com/\(handle)")
        case "telegram":
            if trimmed.hasPrefix("http") { return URL(string: trimmed) }
            let handle = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
            return URL(string: "https://t.me/\(handle)")
        default:
            return trimmed.hasPrefix("http") ? URL(string: trimmed) : nil
        }
    }

    // MARK: - Payment method helpers

    private var mintIconPlaceholder: some View {
        Image(systemName: "bitcoinsign.bank.building.fill")
            .font(.title)
            .foregroundStyle(.secondary)
            .frame(width: 72, height: 72)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Deduped receive rails. The live CDK info advertises one entry per
    /// (method, unit) pair, so collapse by method — the same canonical dedup
    /// used by `MintService.supportedMintPaymentMethods`.
    private var receiveMethods: [PaymentMethodKind] {
        let kinds = cdkInfo?.nuts.nut04.methods.compactMap { PaymentMethodKind.from($0.method) }
            ?? liveMint.supportedMintMethods
        return PaymentMethodKind.allCases.filter { kinds.contains($0) }
    }

    /// Deduped send rails (see `receiveMethods`).
    private var sendMethods: [PaymentMethodKind] {
        let kinds = cdkInfo?.nuts.nut05.methods.compactMap { PaymentMethodKind.from($0.method) }
            ?? liveMint.supportedMeltMethods
        return PaymentMethodKind.allCases.filter { kinds.contains($0) }
    }

    // MARK: - Actions

    private func copyUrl() {
        UIPasteboard.general.string = liveMint.url
        ConfirmationToast.show("Copied mint URL")
    }

    private func loadMintInfo() async {
        await infoLoader.load {
            try await walletManager.fetchFullMintInfo(mintUrl: mint.url)
        }
    }

    /// Durable account units remain visible when metadata removes a payment unit.
    private func loadUnitBalances() async {
        if let units = await walletManager.storedAccountUnits(mintURL: liveMint.url) { storedUnits = units }
        for unit in nonSatUnits {
            if let balance = await walletManager.unitBalance(mintURL: liveMint.url, unit: unit) {
                unitBalances[unit] = balance
            }
        }
    }

    private func removeMint() {
        Task {
            isRemovingMint = true
            actionError = nil
            let removed = await walletManager.removeMint(mint)
            isRemovingMint = false
            if removed {
                dismiss()
            } else if !Task.isCancelled {
                actionError = walletManager.errorMessage
                    ?? "The mint could not be removed. Keep it connected and try again."
            }
        }
    }
}

#Preview {
    NavigationStack {
        MintDetailView(mint: MintInfo(
            url: "https://mint.example.com",
            name: "Example Mint",
            description: "A test mint",
            isActive: true,
            balance: 1000
        ))
        .environmentObject(WalletManager())
    }
}
