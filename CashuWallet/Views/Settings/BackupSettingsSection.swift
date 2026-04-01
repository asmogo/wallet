import SwiftUI

struct BackupSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager

    @Binding var showBackup: Bool
    @Binding var showRestoreFlowAlert: Bool

    var body: some View {
        Button {
            showBackup = true
        } label: {
            Label("Backup seed phrase", systemImage: "key.fill")
        }
        Button {
            showRestoreFlowAlert = true
        } label: {
            Label("Restore ecash", systemImage: "arrow.counterclockwise.circle.fill")
        }
    }
}
