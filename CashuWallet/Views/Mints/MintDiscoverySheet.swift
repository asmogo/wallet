import SwiftUI

struct MintDiscoverySheet: View {
    let addMint: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @ObservedObject private var discoveryManager = MintDiscoveryManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var searchText = ""
    @State private var addedURLsThisSession: Set<String> = []

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Discover Mints")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .onDisappear { discoveryManager.clearDiscoveredMints() }
    }

    @ViewBuilder
    private var content: some View {
        if !settings.useWebsockets {
            NativeEmptyState(
                title: "WebSockets Required",
                systemImage: "antenna.radiowaves.left.and.right.slash",
                description: "Enable WebSocket connections in Settings to discover mints over Nostr."
            )
        } else {
            List {
                if discoveryManager.isDiscovering {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Discovering mints…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !addedMints.isEmpty {
                    Section {
                        ForEach(addedMints) { mint in
                            addedRow(for: mint)
                        }
                    } header: {
                        Text("Added")
                    }
                }

                if !discoverableMints.isEmpty {
                    Section {
                        ForEach(discoverableMints) { mint in
                            discoverableRow(for: mint)
                        }
                    } header: {
                        Text("Discovered")
                    }
                } else if addedMints.isEmpty && !discoveryManager.isDiscovering {
                    Section {
                        if searchText.isEmpty {
                            NativeEmptyState(
                                title: "No Mints Found",
                                systemImage: "magnifyingglass",
                                description: "Pull down to retry.",
                                style: .section
                            )
                        } else {
                            NativeEmptyState(
                                title: "No Results",
                                systemImage: "magnifyingglass",
                                description: "No mint matches \"\(searchText)\".",
                                style: .section
                            )
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .animation(.default, value: addedURLsThisSession)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search mints")
            .refreshable { await discoveryManager.discoverMints() }
            .task {
                if discoveryManager.discoveredMints.isEmpty {
                    await discoveryManager.discoverMints()
                }
            }
        }
    }

    private var filteredMints: [DiscoveredMint] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return discoveryManager.discoveredMints }
        return discoveryManager.discoveredMints.filter { mint in
            (mint.name?.localizedCaseInsensitiveContains(query) ?? false)
                || mint.url.localizedCaseInsensitiveContains(query)
        }
    }

    private var addedMints: [DiscoveredMint] {
        filteredMints.filter { isAlreadyAdded($0) }
    }

    private var discoverableMints: [DiscoveredMint] {
        filteredMints.filter { !isAlreadyAdded($0) }
    }

    private func isAlreadyAdded(_ mint: DiscoveredMint) -> Bool {
        addedURLsThisSession.contains(mint.url)
            || walletManager.mints.contains(where: { $0.url == mint.url })
    }

    @ViewBuilder
    private func addedRow(for mint: DiscoveredMint) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name ?? "Unknown Mint")
                    .font(.body)
                Text(mint.url)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)

            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .symbolEffect(.bounce, value: addedURLsThisSession.contains(mint.url))
                .accessibilityLabel("Added")
        }
        .foregroundStyle(.secondary)
        .opacity(0.7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func discoverableRow(for mint: DiscoveredMint) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name ?? "Unknown Mint")
                    .font(.body)
                Text(mint.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)

            Button {
                withAnimation {
                    addedURLsThisSession.insert(mint.url)
                }
                addMint(mint.url)
                HapticFeedback.selection()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(mint.name ?? "mint")")
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MintDiscoverySheet(addMint: { _ in })
        .environmentObject(WalletManager())
}
