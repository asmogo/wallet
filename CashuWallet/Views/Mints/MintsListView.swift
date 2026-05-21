import SwiftUI

struct MintsListView: View {
    @EnvironmentObject var walletManager: WalletManager

    @State private var newMintUrl = ""
    @State private var newMintNickname = ""
    @State private var isAddingMint = false
    @State private var errorMessage: String?
    @State private var mintToRemove: MintInfo?
    @State private var showRemoveConfirmation = false
    @State private var showDiscoverySheet = false

    var body: some View {
        NavigationStack {
            List {
                if !walletManager.mints.isEmpty {
                    Section {
                        ForEach(walletManager.mints) { mint in
                            mintRow(mint: mint)
                        }
                    }
                }

                Section {
                    Button {
                        errorMessage = nil
                        showDiscoverySheet = true
                    } label: {
                        HStack {
                            Label("Discover Mints", systemImage: "magnifyingglass")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    TextField("Mint URL (https://...)", text: $newMintUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Nickname (optional)", text: $newMintNickname)
                } header: {
                    Text("Add Mint")
                } footer: {
                    Text("Enter the URL of a Cashu mint to connect to it. This wallet is not affiliated with any mint.")
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        addMint()
                    } label: {
                        HStack {
                            Text("Add Mint")
                            if isAddingMint {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(newMintUrl.isEmpty || isAddingMint)

                    Button("Paste URL from Clipboard", action: pasteMintUrlFromClipboard)
                }
            }
            .navigationTitle("Mints")
            .sheet(isPresented: $showDiscoverySheet) {
                MintDiscoverySheet { url in addMint(url: url) }
                    .environmentObject(walletManager)
            }
            .confirmationDialog(
                "Remove Mint",
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let mint = mintToRemove {
                        removeMint(mint)
                    }
                    mintToRemove = nil
                }
                Button("Cancel", role: .cancel) {
                    mintToRemove = nil
                }
            } message: {
                if let mint = mintToRemove {
                    Text("Remove \(mint.name)? Any unspent ecash on this mint will need to be restored from your seed phrase.")
                }
            }
        }
    }

    private var isActive: (MintInfo) -> Bool {
        { mint in walletManager.activeMint?.url == mint.url }
    }

    private func mintRow(mint: MintInfo) -> some View {
        NavigationLink(destination: MintDetailView(mint: mint)) {
            HStack(spacing: 12) {
                mintIcon(for: mint)
                    .overlay(alignment: .bottomTrailing) {
                        if isActive(mint) {
                            Circle()
                                .fill(.green)
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle().stroke(Color(.systemBackground), lineWidth: 2)
                                )
                                .offset(x: 2, y: 2)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(mint.name)
                        .font(.body)
                    Text(mint.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    let featuredMethods = featuredPaymentMethods(for: mint)
                    if !featuredMethods.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(featuredMethods, id: \.self) { method in
                                HStack(spacing: 4) {
                                    Text(method.symbol)
                                    Text(method.displayName)
                                }
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(methodBadgeColor(method).opacity(0.12), in: Capsule())
                                .foregroundStyle(methodBadgeColor(method))
                            }
                        }
                    }
                }
                Spacer()
                Text("\(mint.balance) sat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button { setActive(mint) } label: {
                Label("Set as Active", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                mintToRemove = mint
                showRemoveConfirmation = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                mintToRemove = mint
                showRemoveConfirmation = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isActive(mint) {
                Button {
                    setActive(mint)
                } label: {
                    Label("Set Active", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
        }
    }

    @ViewBuilder
    private func mintIcon(for mint: MintInfo) -> some View {
        if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                mintIconPlaceholder
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            mintIconPlaceholder
        }
    }

    private var mintIconPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: "bitcoinsign.bank.building")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
    }

    private func featuredPaymentMethods(for mint: MintInfo) -> [PaymentMethodKind] {
        Array(Set(mint.supportedMintMethods + mint.supportedMeltMethods))
            .filter { $0 == .bolt12 || $0 == .onchain }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func methodBadgeColor(_ method: PaymentMethodKind) -> Color {
        switch method {
        case .bolt11:
            return .yellow
        case .bolt12:
            return .accentColor
        case .onchain:
            return .orange
        }
    }

    // MARK: - Actions

    private func addMint(url: String? = nil) {
        let urlToAdd = url ?? newMintUrl
        guard !urlToAdd.isEmpty else { return }
        let clearForm = (url == nil)
        isAddingMint = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await walletManager.addMint(url: urlToAdd)
                if clearForm {
                    newMintUrl = ""
                    newMintNickname = ""
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isAddingMint = false
        }
    }

    private func pasteMintUrlFromClipboard() {
        guard let clipboardContent = UIPasteboard.general.string,
              !clipboardContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Clipboard is empty."
            return
        }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        let candidates = clipboardContent.components(separatedBy: separators).filter { !$0.isEmpty }
        for rawCandidate in candidates {
            var candidate = rawCandidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !candidate.hasPrefix("http://") && !candidate.hasPrefix("https://") {
                candidate = "https://" + candidate
            }
            if candidate.hasSuffix("/") {
                candidate = String(candidate.dropLast())
            }
            if let url = URL(string: candidate), url.host != nil {
                newMintUrl = candidate
                errorMessage = nil
                return
            }
        }
        errorMessage = "No valid mint URL found in clipboard."
    }

    private func setActive(_ mint: MintInfo) {
        Task { try? await walletManager.setActiveMint(mint) }
    }

    private func removeMint(_ mint: MintInfo) {
        Task {
            if let index = walletManager.mints.firstIndex(where: { $0.url == mint.url }) {
                await walletManager.removeMint(at: IndexSet(integer: index))
            }
        }
    }
}

#Preview {
    MintsListView()
        .environmentObject(WalletManager())
}
