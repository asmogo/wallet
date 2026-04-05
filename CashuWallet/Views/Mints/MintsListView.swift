import SwiftUI

struct MintsListView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var discoveryManager = MintDiscoveryManager.shared

    @State private var newMintUrl = ""
    @State private var newMintNickname = ""
    @State private var isAddingMint = false
    @State private var errorMessage: String?
    @State private var mintToRemove: MintInfo?
    @State private var showRemoveConfirmation = false

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
                        guard settings.useWebsockets else {
                            errorMessage = "Enable WebSocket connections in Settings to discover mints."
                            return
                        }
                        errorMessage = nil
                        Task { await discoveryManager.discoverMints() }
                    } label: {
                        HStack {
                            Label(
                                discoveryManager.isDiscovering ? "Discovering..." : "Discover Mints",
                                systemImage: "magnifyingglass"
                            )
                            if discoveryManager.isDiscovering {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(discoveryManager.isDiscovering)

                    ForEach(discoveryManager.discoveredMints) { mint in
                        discoveredMintRow(mint: mint)
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
                    Button(action: addMint) {
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

    private func mintRow(mint: MintInfo) -> some View {
        NavigationLink(destination: MintDetailView(mint: mint)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(mint.name)
                            .font(.body)
                        if walletManager.activeMint?.url == mint.url {
                            Text("Active")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(mint.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
    }

    private func discoveredMintRow(mint: DiscoveredMint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name ?? "Unknown Mint")
                    .font(.body)
                Text(mint.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                newMintUrl = mint.url
                addMint()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
        }
    }

    // MARK: - Actions

    private func addMint() {
        guard !newMintUrl.isEmpty else { return }
        isAddingMint = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await walletManager.addMint(url: newMintUrl)
                newMintUrl = ""
                newMintNickname = ""
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
