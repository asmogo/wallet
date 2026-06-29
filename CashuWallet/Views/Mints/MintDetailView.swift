import SwiftUI
import Cdk

struct MintDetailView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared
    @Environment(\.dismiss) private var dismiss

    let mint: MintInfo

    @State private var cdkInfo: Cdk.MintInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showRemoveConfirmation = false
    @State private var copiedUrl = false
    @State private var nutsExpanded = false
    @State private var aboutExpanded = false
    @State private var showNavTitle = false

    private var isDefaultMint: Bool {
        walletManager.activeMint?.url == mint.url
    }

    private enum Connection { case checking, online, offline }

    private var connection: Connection {
        if cdkInfo != nil { return .online }
        if errorMessage != nil { return .offline }
        return .checking
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

                if let errorMessage {
                    ErrorBannerView(message: errorMessage, severity: .error)
                        .padding(.bottom, 12)
                }

                // Identity stats — available immediately from local mint data.
                VStack(spacing: 0) {
                    balanceRow
                    CanvasDivider()
                    connectionRow
                }
                .padding(.bottom, 24)

                // Remote metadata fills in after the fetch.
                if cdkInfo == nil && isLoading {
                    loadingRow
                } else {
                    aboutSection
                    motdSection
                    capabilitiesSection
                    paymentMethodsSection
                    contactSection
                    detailsSection
                }

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
                Text(mint.name)
                    .font(.headline)
                    .opacity(showNavTitle ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showNavTitle)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: mint.url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share mint")
            }
        }
        .task { await loadMintInfo() }
        .alert("Remove Mint", isPresented: $showRemoveConfirmation) {
            Button("Remove", role: .destructive) { removeMint() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(mint.name)? Any unspent ecash will need to be restored from your seed phrase.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            mintIcon
                .overlay(alignment: .bottomTrailing) {
                    if isDefaultMint { defaultDot }
                }
            Text(mint.name)
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
        if let iconUrl = cdkInfo?.iconUrl, let url = URL(string: iconUrl) {
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
                Text(mint.url)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: copiedUrl ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copiedUrl ? "Copied mint URL" : "Copy mint URL")
    }

    // MARK: - Identity stats

    private var balanceRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Balance", systemImage: "bitcoinsign")
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(AmountFormatter.sats(mint.balance, useBitcoinSymbol: settings.useBitcoinSymbol))
                    .monospacedDigit()
                if showFiat {
                    Text(priceService.formatSatsAsFiat(mint.balance))
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

    private var connectionRow: some View {
        HStack {
            Label("Connection", systemImage: "network")
                .foregroundStyle(.secondary)
            Spacer()
            switch connection {
            case .checking:
                Text("Checking…").foregroundStyle(.secondary)
            case .online:
                Text("Online").foregroundStyle(.primary)
            case .offline:
                Text("Offline").foregroundStyle(.red)
            }
        }
        .font(.body)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading mint info…")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 20)
    }

    // MARK: - About / Message

    @ViewBuilder
    private var aboutSection: some View {
        let shortDesc = cdkInfo?.description ?? mint.description
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
                                withAnimation(.easeInOut(duration: 0.2)) { aboutExpanded.toggle() }
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
        DisclosureGroup(isExpanded: $nutsExpanded.animation(.easeInOut(duration: 0.2))) {
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
        if !receiveMethodSummaries.isEmpty || !sendMethodSummaries.isEmpty {
            section("Payment methods") {
                VStack(spacing: 0) {
                    if !receiveMethodSummaries.isEmpty {
                        paymentDirectionRow(icon: "arrow.down", label: "Receive", methods: receiveMethodSummaries)
                    }
                    if !sendMethodSummaries.isEmpty {
                        if !receiveMethodSummaries.isEmpty { CanvasDivider() }
                        paymentDirectionRow(icon: "arrow.up", label: "Send", methods: sendMethodSummaries)
                    }
                }
            }
        }
    }

    private func paymentDirectionRow(icon: String, label: String, methods: [PaymentMethodSummary]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(methods) { summary in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(summary.method.displayName)
                        if let detail = summary.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
                        if index < contacts.count - 1 {
                            CanvasDivider()
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
        let showUnits = !mint.units.isEmpty
        let tosUrl = cdkInfo?.tosUrl.flatMap { URL(string: $0) }
        if version != nil || showUnits || tosUrl != nil {
            section("Details") {
                VStack(spacing: 0) {
                    if let version {
                        detailRow(icon: "shippingbox", label: "Software",
                                  value: "\(version.name) \(version.version)")
                    }
                    if showUnits {
                        if version != nil { CanvasDivider() }
                        detailRow(icon: "ruler",
                                  label: mint.units.count > 1 ? "Units" : "Unit",
                                  value: mint.units.joined(separator: ", ").uppercased())
                    }
                    if let tosUrl {
                        if version != nil || showUnits { CanvasDivider() }
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
            if !isDefaultMint {
                Button("Set as Default") {
                    Task { try? await walletManager.setActiveMint(mint) }
                }
                .glassButton()
            }
            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                Text("Remove Mint")
                    .font(.body)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Section container

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
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

        let allMethods = receiveMethodSummaries.map(\.method) + sendMethodSummaries.map(\.method)
        let hasLightning = allMethods.contains { $0 == .bolt11 || $0 == .bolt12 }
        let hasOnchain = allMethods.contains(.onchain)

        if hasLightning {
            lines.append(Capability(icon: "bolt.fill", text: "Send & receive over Lightning"))
        }
        if hasOnchain {
            lines.append(Capability(icon: "bitcoinsign", text: "On-chain Bitcoin deposits & withdrawals"))
        }

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

    private var receiveMethodSummaries: [PaymentMethodSummary] {
        if let cdkInfo {
            return cdkInfo.nuts.nut04.methods
                .compactMap { method in
                    guard let paymentMethod = PaymentMethodKind.from(method.method) else {
                        return nil
                    }

                    return PaymentMethodSummary(
                        method: paymentMethod,
                        minAmount: method.minAmount?.value,
                        maxAmount: method.maxAmount?.value,
                        detail: paymentMethodDetail(
                            method: paymentMethod,
                            minAmount: method.minAmount?.value,
                            maxAmount: method.maxAmount?.value,
                            confirmations: paymentMethod == .onchain ? mint.onchainMintConfirmations : nil
                        )
                    )
                }
                .sorted { $0.method.sortOrder < $1.method.sortOrder }
        }

        return mint.supportedMintMethods
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { method in
                PaymentMethodSummary(
                    method: method,
                    minAmount: nil,
                    maxAmount: nil,
                    detail: paymentMethodDetail(
                        method: method,
                        minAmount: nil,
                        maxAmount: nil,
                        confirmations: method == .onchain ? mint.onchainMintConfirmations : nil
                    )
                )
            }
    }

    private var sendMethodSummaries: [PaymentMethodSummary] {
        if let cdkInfo {
            return cdkInfo.nuts.nut05.methods
                .compactMap { method in
                    guard let paymentMethod = PaymentMethodKind.from(method.method) else {
                        return nil
                    }

                    return PaymentMethodSummary(
                        method: paymentMethod,
                        minAmount: method.minAmount?.value,
                        maxAmount: method.maxAmount?.value,
                        detail: paymentMethodDetail(
                            method: paymentMethod,
                            minAmount: method.minAmount?.value,
                            maxAmount: method.maxAmount?.value
                        )
                    )
                }
                .sorted { $0.method.sortOrder < $1.method.sortOrder }
        }

        return mint.supportedMeltMethods
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { method in
                PaymentMethodSummary(
                    method: method,
                    minAmount: nil,
                    maxAmount: nil,
                    detail: paymentMethodDetail(method: method, minAmount: nil, maxAmount: nil)
                )
            }
    }

    private func paymentMethodDetail(
        method: PaymentMethodKind,
        minAmount: UInt64?,
        maxAmount: UInt64?,
        confirmations: Int? = nil
    ) -> String? {
        var parts: [String] = []

        if let range = amountRange(minAmount: minAmount, maxAmount: maxAmount) {
            parts.append(range)
        }

        if method == .onchain, let confirmations {
            let suffix = confirmations == 1 ? "" : "s"
            parts.append("\(confirmations) confirmation\(suffix)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func amountRange(minAmount: UInt64?, maxAmount: UInt64?) -> String? {
        switch (minAmount, maxAmount) {
        case let (.some(minimum), .some(maximum)):
            return "\(minimum)-\(maximum) sat"
        case let (.some(minimum), nil):
            return "Min \(minimum) sat"
        case let (nil, .some(maximum)):
            return "Max \(maximum) sat"
        case (nil, nil):
            return nil
        }
    }

    // MARK: - Actions

    private func copyUrl() {
        UIPasteboard.general.string = mint.url
        copiedUrl = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedUrl = false
        }
    }

    private func loadMintInfo() async {
        do {
            cdkInfo = try await walletManager.fetchFullMintInfo(mintUrl: mint.url)
        } catch {
            errorMessage = error.userFacingWalletMessage
        }
        isLoading = false
    }

    private func removeMint() {
        Task {
            if let index = walletManager.mints.firstIndex(where: { $0.url == mint.url }) {
                await walletManager.removeMint(at: IndexSet(integer: index))
                dismiss()
            }
        }
    }
}

private struct PaymentMethodSummary: Identifiable {
    let method: PaymentMethodKind
    let minAmount: UInt64?
    let maxAmount: UInt64?
    let detail: String?

    var id: PaymentMethodKind { method }
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
