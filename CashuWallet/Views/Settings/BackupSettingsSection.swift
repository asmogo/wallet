import SwiftUI

struct BackupSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager

    @Binding var showBackup: Bool

    var body: some View {
        LazyVStack(spacing: 0) {
            SettingsSectionGroup(nil) {
                Button {
                    showBackup = true
                } label: {
                    backupRestoreRow(
                        title: "Backup seed phrase",
                        subtitle: "View and copy your 12 recovery words.",
                        systemImage: "key.fill"
                    )
                }
                .buttonStyle(.plain)

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
                .buttonStyle(.plain)

                NavigationLink {
                    ICloudBackupSettingsView()
                        .environmentObject(walletManager)
                } label: {
                    backupRestoreRow(
                        title: "iCloud Backup",
                        subtitle: walletManager.iCloudBackupEnabled
                            ? "On · Seed phrase synced to iCloud Keychain."
                            : "Auto-backup your seed phrase and mints.",
                        systemImage: "icloud"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func backupRestoreRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemName: systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
