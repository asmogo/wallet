import SwiftUI

struct BackupSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager

    @Binding var showBackup: Bool
    @Binding var showRestoreFlowAlert: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingButton(
                icon: "key.fill",
                title: "Backup seed phrase",
                subtitle: "Your seed phrase can restore your wallet. Keep it safe and private."
            ) {
                showBackup = true
            }
            settingButton(
                icon: "arrow.counterclockwise.circle.fill",
                title: "Restore ecash",
                subtitle: "Open the restore wizard to recover ecash from another mnemonic seed phrase."
            ) {
                showRestoreFlowAlert = true
            }
        }
        .padding(.vertical, 8)
    }

    private func settingButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        }
    }
}
