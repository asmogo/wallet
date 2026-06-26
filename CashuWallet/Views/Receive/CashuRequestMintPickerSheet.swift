import SwiftUI

struct CashuRequestMintPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager

    /// The currently-selected mint URL for the request, or `nil` for "Any mint".
    let currentMintUrl: String?
    /// Called with the new mint URL on selection (`nil` = Any mint). Sheet dismisses afterwards.
    let onSelect: (String?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button(action: { select(nil) }) {
                    HStack(spacing: 12) {
                        anyMintIcon
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Any mint")
                                .font(.body.weight(.medium))
                            Text("Sender chooses the mint")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if currentMintUrl == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .buttonStyle(.plain)

                ForEach(walletManager.mints) { mint in
                    Button(action: { select(mint.url) }) {
                        HStack(spacing: 12) {
                            mintIcon(for: mint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mint.name)
                                    .font(.body.weight(.medium))
                                Text(SettingsManager.shared.formatAmountBalance(mint.balance) + " sat")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if currentMintUrl == mint.url {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Mint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private func select(_ mintUrl: String?) {
        HapticFeedback.selection()
        onSelect(mintUrl)
        dismiss()
    }

    // MARK: - Icons

    private var anyMintIcon: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "infinity")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            )
    }

    @ViewBuilder
    private func mintIcon(for mint: MintInfo) -> some View {
        if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
            CachedAsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                mintIconPlaceholder
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            mintIconPlaceholder
        }
    }

    private var mintIconPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "bitcoinsign.bank.building")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
    }
}
