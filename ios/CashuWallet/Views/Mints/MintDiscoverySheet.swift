import SwiftUI

/// The Nostr-relay discovery list, without chrome of its own — hosts supply the
/// navigation container and title. The list owns add execution and row state so
/// every host gets the same success/failure behavior.
struct MintDiscoveryList: View {
    var onMintAdded: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var walletManager: WalletManager
    @ObservedObject private var discoveryManager = MintDiscoveryManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var searchText = ""
    @State private var addStates: [String: MintDiscoveryAddState] = [:]

    var body: some View {
        content
            .onDisappear { discoveryManager.clearDiscoveredMints() }
    }

    @ViewBuilder
    private var content: some View {
        if !settings.useWebsockets {
            NativeEmptyState(
                title: "WebSockets Required",
                systemImage: "antenna.radiowaves.left.and.right.slash",
                description: "Discovery uses Nostr relays over WebSockets. Enable them in Settings → Privacy."
            )
        } else {
            List {
                if !addedMints.isEmpty {
                    Section {
                        ForEach(addedMints) { mint in addedRow(for: mint) }
                    } header: {
                        Text("Added")
                    }
                }

                if !discoverableMints.isEmpty {
                    Section {
                        ForEach(discoverableMints) { mint in discoverableRow(for: mint) }
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
            .listSectionSpacing(8)
            .contentMargins(.top, 0, for: .scrollContent)
            .safeAreaInset(edge: .top, spacing: 0) {
                if discoveryManager.isDiscovering {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Discovering mints…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: addStates)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search mints"
            )
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
            mint.displayName.localizedCaseInsensitiveContains(query)
                || mint.url.localizedCaseInsensitiveContains(query)
        }
    }

    private var addedMints: [DiscoveredMint] {
        filteredMints.filter(isAlreadyAdded)
    }

    private var discoverableMints: [DiscoveredMint] {
        filteredMints.filter { !isAlreadyAdded($0) }
    }

    private func isAlreadyAdded(_ mint: DiscoveredMint) -> Bool {
        addStates[mint.url] == .added
            || walletManager.mints.contains(where: {
                canonicalDiscoveredMintURL($0.url) == mint.url
            })
    }

    @ViewBuilder
    private func addedRow(for mint: DiscoveredMint) -> some View {
        HStack(spacing: 12) {
            MintAvatarView(iconUrl: mint.iconUrl, name: mint.displayName, size: 36)
                .accessibilityHidden(true)
            mintIdentity(mint)
            Spacer(minLength: 8)
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .symbolEffect(.bounce, value: reduceMotion ? false : addStates[mint.url] == .added)
                .accessibilityLabel("Added")
        }
        .foregroundStyle(.secondary)
        .opacity(0.7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func discoverableRow(for mint: DiscoveredMint) -> some View {
        let state = addStates[mint.url]
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                MintAvatarView(iconUrl: mint.iconUrl, name: mint.displayName, size: 36)
                    .accessibilityHidden(true)
                mintIdentity(mint)
                Spacer(minLength: 8)

                if state == .adding {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Adding \(mint.displayName)")
                } else {
                    Button { add(mint) } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        state?.failureMessage == nil
                            ? "Add \(mint.displayName)"
                            : "Retry adding \(mint.displayName)"
                    )
                }
            }

            if let message = state?.failureMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 48)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func mintIdentity(_ mint: DiscoveredMint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(mint.displayName)
                    .font(.body)
                    .lineLimit(1)
                MintMethodIcons(methods: mint.methods)
                    .layoutPriority(1)
            }
            Text(mint.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func add(_ mint: DiscoveredMint) {
        guard addStates[mint.url] != .adding, addStates[mint.url] != .added else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            addStates[mint.url] = .adding
        }
        Task { @MainActor in
            do {
                try await walletManager.addMint(url: mint.url)
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                    addStates[mint.url] = .added
                }
                HapticFeedback.notification(.success)
                onMintAdded()
            } catch is CancellationError {
                addStates[mint.url] = nil
            } catch {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                    addStates[mint.url] = .failed(error.userFacingWalletMessage)
                }
                HapticFeedback.notification(.error)
            }
        }
    }
}

enum MintDiscoveryAddState: Equatable {
    case adding
    case added
    case failed(String)

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Standalone presentation from the Mints list and the mint-chip menu.
struct MintDiscoverySheet: View {
    var onMintAdded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MintDiscoveryList(onMintAdded: onMintAdded)
                .navigationTitle("Discover mints")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}

#Preview {
    MintDiscoverySheet()
        .environmentObject(WalletManager())
}
