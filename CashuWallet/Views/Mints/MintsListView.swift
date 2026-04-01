import SwiftUI

struct MintsListView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared  // used for useWebsockets
    @ObservedObject var discoveryManager = MintDiscoveryManager.shared
    
    @State private var showAddMint = false
    @State private var newMintUrl = ""
    @State private var newMintNickname = ""
    @State private var isAddingMint = false
    @State private var errorMessage: String?
    @State private var mintToRemove: MintInfo?
    @State private var showRemoveConfirmation = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                        // Existing mints
                        ForEach(walletManager.mints) { mint in
                            mintCard(mint: mint)
                        }
                        
                        // Discover mints button
                        Button(action: {
                            guard settings.useWebsockets else {
                                errorMessage = "Enable WebSocket connections in Settings to discover mints."
                                return
                            }
                            errorMessage = nil
                            Task {
                                await discoveryManager.discoverMints()
                            }
                        }) {
                            HStack {
                                if discoveryManager.isDiscovering {
                                    ProgressView()
                                        .tint(.black)
                                        .padding(.trailing, 4)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                }
                                Text(discoveryManager.isDiscovering ? "DISCOVERING..." : "DISCOVER MINTS")
                            }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityLabel("Discover mints from relays")
                        .padding(.top, 8)
                        
                        // Discovered Mints
                        if !discoveryManager.discoveredMints.isEmpty {
                            Text("Discovered Mints")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 16)
                            
                            ForEach(discoveryManager.discoveredMints) { mint in
                                discoveredMintCard(mint: mint)
                            }
                        }
                        
                        // Add mint section
                        Text("Add Mint")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)
                        
                        Text("Enter the URL of a Cashu mint to connect to it. This wallet is not affiliated with any mint.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // URL input
                        TextField("https://", text: $newMintUrl)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()

                        // Nickname input
                        TextField("Nickname (e.g. Testnet)", text: $newMintNickname)
                            .textFieldStyle(.roundedBorder)
                        
                        if let error = errorMessage {
                            ErrorBannerView(message: error, type: .error) {
                                errorMessage = nil
                            }
                        }
                        
                        // Add buttons
                        HStack(spacing: 16) {
                            Button(action: addMint) {
                                HStack {
                                    if isAddingMint {
                                        ProgressView()
                                            .tint(Color.accentColor)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "plus")
                                    }
                                    Text("ADD MINT")
                                }
                                .font(.caption)
                                .foregroundColor(newMintUrl.isEmpty ? .secondary : Color.accentColor)
                            }
                            .disabled(newMintUrl.isEmpty || isAddingMint)
                            
                            Spacer()
                            
                            Button(action: pasteMintUrlFromClipboard) {
                                HStack {
                                    Image(systemName: "doc.on.clipboard")
                                    Text("PASTE URL")
                                }
                                .font(.caption)
            .foregroundStyle(Color.accentColor)
                            }
                            .accessibilityLabel("Paste mint URL from clipboard")
                        }
                        .padding(.top, 8)
                        
                        Spacer(minLength: 100)
                    }
                    .padding()
                }
            .navigationTitle("Mints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Mints")
                        .font(.headline)
                }
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
    
    
    private func mintCard(mint: MintInfo) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "building.columns")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(mint.name)
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)

                            if walletManager.activeMint?.url == mint.url {
                                Text("Active")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .stroke(Color.accentColor, lineWidth: 1)
                                    )
                            }
                        }

                        Text(mint.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Menu {
                        Button(action: { setActive(mint) }) {
                            Label("Set as Active", systemImage: "checkmark.circle")
                        }
                        Button(role: .destructive, action: {
                            mintToRemove = mint
                            showRemoveConfirmation = true
                        }) {
                            Label("Remove", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }

                // Balance
                LabeledContent("Balance", value: "\(mint.balance) sat")
                    .font(.subheadline)
            }
        }
    }
    
    private func discoveredMintCard(mint: DiscoveredMint) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mint.name ?? "Unknown Mint")
                        .font(.subheadline)
                        .fontWeight(.bold)

                    Text(mint.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: {
                    newMintUrl = mint.url
                    addMint()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
    
    
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
        Task {
            try? await walletManager.setActiveMint(mint)
        }
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
