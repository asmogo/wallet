import SwiftUI

struct BackupSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager

    @Binding var showBackup: Bool

    var body: some View {
        Button {
            showBackup = true
        } label: {
            backupRestoreRow(
                title: "Backup seed phrase",
                subtitle: "View and copy your 12 recovery words.",
                systemImage: "key.fill"
            )
        }

        NavigationLink {
            RestoreWalletView()
                .environmentObject(walletManager)
        } label: {
            backupRestoreRow(
                title: "Restore",
                subtitle: "Restore a wallet and recover ecash from mints.",
                systemImage: "arrow.counterclockwise.circle.fill"
            )
        }
    }

    private func backupRestoreRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
