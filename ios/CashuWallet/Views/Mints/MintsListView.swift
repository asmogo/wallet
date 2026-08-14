import SwiftUI

struct MintsListView: View {
    @EnvironmentObject var walletManager: WalletManager

    @State private var mintToRemove: MintInfo?
    @State private var showRemoveConfirmation = false
    @State private var showAddMintSheet = false
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
                        showAddMintSheet = true
                    } label: {
                        actionRow(title: "Add mint", systemImage: "plus")
                    }
                    .accessibilityIdentifier("mints-add-button")

                    Button {
                        showDiscoverySheet = true
                    } label: {
                        actionRow(title: "Discover mints", systemImage: "magnifyingglass")
                    }
                }
            }
            .navigationTitle("Mints")
            .sheet(isPresented: $showAddMintSheet) {
                // Detents live inside AddMintSheet so it hugs the form.
                AddMintSheet()
                    .environmentObject(walletManager)
            }
            .sheet(isPresented: $showDiscoverySheet) {
                MintDiscoverySheet()
                    .environmentObject(walletManager)
                    .canvasSheetBackground()
            }
            .task {
                await walletManager.refreshMintInfo()
            }
            .alert("Remove Mint", isPresented: $showRemoveConfirmation) {
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
        .accessibilityIdentifier("mints-screen")
    }

    private func actionRow(title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
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
                }
                Spacer()
                Text("\(mint.balance) sat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // The green dot marks the default mint by colour alone; surface the
            // same state to VoiceOver so it isn't encoded by colour only
            // (DESIGN.md — never encode state with colour alone).
            .accessibilityElement(children: .combine)
            .accessibilityValue(isActive(mint) ? "Default mint" : "")
        }
        .contextMenu {
            Button { setActive(mint) } label: {
                Label("Set as Default", systemImage: "checkmark.circle")
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
                    Label("Set as Default", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
        }
    }

    @ViewBuilder
    private func mintIcon(for mint: MintInfo) -> some View {
        if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
            CachedAsyncImage(url: url) { image in
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

    // MARK: - Actions

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
