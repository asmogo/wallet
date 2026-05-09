import SwiftUI
import CashuDevKit

struct MintDetailView: View {
    @EnvironmentObject var walletManager: WalletManager
    let mint: MintInfo

    @State private var cdkInfo: CashuDevKit.MintInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showRemoveConfirmation = false
    @State private var copiedUrl = false

    var body: some View {
        List {
            headerSection
            aboutSection
            motdSection
            contactSection
            softwareSection
            paymentMethodsSection
            nutsSection
            walletSection
            tosSection
            actionsSection
        }
        .listStyle(.plain)
        .navigationTitle(mint.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMintInfo() }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .confirmationDialog("Remove Mint", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { removeMint() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(mint.name)? Any unspent ecash will need to be restored from your seed phrase.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                if let iconUrl = cdkInfo?.iconUrl, let url = URL(string: iconUrl) {
                    AsyncImage(url: url) { image in
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

                Text(mint.name)
                    .font(.title2.weight(.semibold))

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

                if let pubkey = cdkInfo?.pubkey, !pubkey.isEmpty {
                    Text(truncatePubkey(pubkey))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        let description = cdkInfo?.description ?? mint.description
        if description != nil || cdkInfo?.descriptionLong != nil {
            Section("About") {
                if let desc = description {
                    Text(desc)
                        .listRowSeparator(.hidden)
                }
                if let longDesc = cdkInfo?.descriptionLong {
                    Text(longDesc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    @ViewBuilder
    private var motdSection: some View {
        if let motd = cdkInfo?.motd, !motd.isEmpty {
            Section("Message of the Day") {
                Label(motd, systemImage: "megaphone")
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var contactSection: some View {
        if let contacts = cdkInfo?.contact, !contacts.isEmpty {
            Section("Contact") {
                ForEach(contacts, id: \.method) { contact in
                    LabeledContent(contact.method.capitalized, value: contact.info)
                        .font(.subheadline)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    @ViewBuilder
    private var softwareSection: some View {
        if let version = cdkInfo?.version {
            Section("Software") {
                LabeledContent("Name", value: version.name)
                    .listRowSeparator(.hidden)
                LabeledContent("Version", value: version.version)
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var paymentMethodsSection: some View {
        if !receiveMethodSummaries.isEmpty || !sendMethodSummaries.isEmpty {
            Section("Payment Methods") {
                if !receiveMethodSummaries.isEmpty {
                    paymentMethodGroup(title: "Receive", methods: receiveMethodSummaries)
                        .listRowSeparator(.hidden)
                }
                if !sendMethodSummaries.isEmpty {
                    paymentMethodGroup(title: "Send", methods: sendMethodSummaries)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    @ViewBuilder
    private var nutsSection: some View {
        if let nuts = cdkInfo?.nuts {
            Section("Supported NUTs") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                    nutBadge("NUT-04", label: "Mint", supported: true)
                    nutBadge("NUT-05", label: "Melt", supported: true)
                    nutBadge("NUT-07", label: "State", supported: nuts.nut07Supported)
                    nutBadge("NUT-08", label: "Fee Return", supported: nuts.nut08Supported)
                    nutBadge("NUT-09", label: "Restore", supported: nuts.nut09Supported)
                    nutBadge("NUT-10", label: "Conditions", supported: nuts.nut10Supported)
                    nutBadge("NUT-11", label: "P2PK", supported: nuts.nut11Supported)
                    nutBadge("NUT-12", label: "DLEQ", supported: nuts.nut12Supported)
                    nutBadge("NUT-14", label: "HTLC", supported: nuts.nut14Supported)
                    nutBadge("NUT-20", label: "WebSocket", supported: nuts.nut20Supported)
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var walletSection: some View {
        Section("Wallet") {
            LabeledContent("Balance", value: "\(mint.balance) sat")
                .listRowSeparator(.hidden)
            LabeledContent("Status", value: walletManager.activeMint?.url == mint.url ? "Active" : "Inactive")
                .listRowSeparator(.hidden)
            if !mint.units.isEmpty {
                LabeledContent("Units", value: mint.units.joined(separator: ", "))
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var tosSection: some View {
        if let tosUrl = cdkInfo?.tosUrl, let url = URL(string: tosUrl) {
            Section {
                Link("Terms of Service", destination: url)
                    .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            if walletManager.activeMint?.url != mint.url {
                Button("Set as Active") {
                    Task { try? await walletManager.setActiveMint(mint) }
                }
                .listRowSeparator(.hidden)
            }
            Button("Remove Mint", role: .destructive) {
                showRemoveConfirmation = true
            }
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - Helpers

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

    private func paymentMethodGroup(title: String, methods: [PaymentMethodSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(methods) { summary in
                    HStack(alignment: .top, spacing: 12) {
                        Text(summary.method.symbol)
                            .font(.headline)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.method.displayName)
                                .font(.subheadline.weight(.semibold))

                            if let detail = summary.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func nutBadge(_ nut: String, label: String, supported: Bool) -> some View {
        VStack(spacing: 2) {
            Text(nut)
                .font(.caption2.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(supported ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
        .foregroundStyle(supported ? .green : .secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func truncatePubkey(_ key: String) -> String {
        guard key.count > 16 else { return key }
        return "\(key.prefix(8))...\(key.suffix(8))"
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
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @Environment(\.dismiss) private var dismiss

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
