import SwiftUI

struct MintsListView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var discoveryManager = MintDiscoveryManager.shared
    @ObservedObject var priceService = PriceService.shared
    
    @State private var showAddMint = false
    @State private var newMintUrl = ""
    @State private var newMintNickname = ""
    @State private var isAddingMint = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
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
                        .buttonStyle(CashuPrimaryButtonStyle(isDisabled: discoveryManager.isDiscovering))
                        .accessibilityLabel("Discover mints from relays")
                        .padding(.top, 8)
                        
                        // Discovered Mints
                        if !discoveryManager.discoveredMints.isEmpty {
                            sectionHeader("DISCOVERED MINTS")
                            
                            ForEach(discoveryManager.discoveredMints) { mint in
                                discoveredMintCard(mint: mint)
                            }
                        }
                        
                        // Add mint section
                        sectionHeader("ADD MINT")
                        
                        Text("Enter the URL of a Cashu mint to connect to it. This wallet is not affiliated with any mint.")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // URL input
                        TextField("https://", text: $newMintUrl)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.cashuCardBackground)
                            )
                        
                        // Nickname input
                        TextField("Nickname (e.g. Testnet)", text: $newMintNickname)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.cashuCardBackground)
                            )
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.cashuError)
                        }
                        
                        // Add buttons
                        HStack(spacing: 16) {
                            Button(action: addMint) {
                                HStack {
                                    if isAddingMint {
                                        ProgressView()
                                            .tint(settings.accentColor)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "plus")
                                    }
                                    Text("ADD MINT")
                                }
                                .font(.caption)
                                .foregroundColor(newMintUrl.isEmpty ? .cashuMutedText : settings.accentColor)
                            }
                            .disabled(newMintUrl.isEmpty || isAddingMint)
                            
                            Spacer()
                            
                            Button(action: pasteMintUrlFromClipboard) {
                                HStack {
                                    Image(systemName: "doc.on.clipboard")
                                    Text("PASTE URL")
                                }
                                .font(.caption)
                                .foregroundColor(settings.accentColor)
                            }
                            .accessibilityLabel("Paste mint URL from clipboard")
                        }
                        .padding(.top, 8)
                        
                        Spacer(minLength: 100)
                    }
                    .padding()
                }
            }
            .navigationTitle("Mints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Mints")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Rectangle()
                .fill(Color.cashuBorder)
                .frame(height: 1)
            
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.cashuMutedText)
                .tracking(2)
            
            Rectangle()
                .fill(Color.cashuBorder)
                .frame(height: 1)
        }
        .padding(.top, 24)
    }
    
    private func mintCard(mint: MintInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Mint icon
                Circle()
                    .fill(Color.cashuCardBackground)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "building.columns")
                            .foregroundColor(settings.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(mint.name)
                            .font(.headline)
                            .foregroundColor(settings.accentColor)
                        
                        if walletManager.activeMint?.url == mint.url {
                            Text("Active")
                                .font(.caption2)
                                .foregroundColor(settings.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .stroke(settings.accentColor, lineWidth: 1)
                                )
                        }
                    }
                    
                    Text(mint.url)
                        .font(.caption)
                        .foregroundColor(.cashuMutedText)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Menu {
                    Button(action: { setActive(mint) }) {
                        Label("Set as Active", systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive, action: { removeMint(mint) }) {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.cashuMutedText)
                        .padding(8)
                }
            }
            
            // Balance pills
            HStack(spacing: 8) {
                balancePill(settings.formatAmount(mint.balance))

                if settings.showFiatBalance {
                    balancePill(mintFiatLabel(for: mint.balance))
                }

                if !mint.units.isEmpty {
                    balancePill(mint.units.map { $0.uppercased() }.joined(separator: ", "))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(settings.accentColor, lineWidth: 1)
        )
    }
    
    private func discoveredMintCard(mint: DiscoveredMint) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.cashuCardBackground)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "globe")
                        .foregroundColor(.cashuMutedText)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name ?? "Unknown Mint")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(mint.url)
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {
                newMintUrl = mint.url
                addMint()
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(settings.accentColor)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cashuCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.cashuBorder, lineWidth: 1)
                )
        )
    }
    
    private func balancePill(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.cashuCardBackground)
            )
    }
    
    private func addMint() {
        guard !newMintUrl.isEmpty else { return }
        
        isAddingMint = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                let nickname = newMintNickname.trimmingCharacters(in: .whitespacesAndNewlines)
                try await walletManager.addMint(
                    url: newMintUrl,
                    nickname: nickname.isEmpty ? nil : nickname
                )
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

    private func mintFiatLabel(for sats: UInt64) -> String {
        guard priceService.btcPriceUSD > 0 else { return "Fiat loading..." }
        return priceService.formatSatsAsFiat(sats)
    }
}

#Preview {
    MintsListView()
        .environmentObject(WalletManager())
}
