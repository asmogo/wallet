import SwiftUI

struct AdvancedSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared

    @Binding var showDeleteConfirm: Bool

    var body: some View {
        Button(action: { showDeleteConfirm = true }) {
            HStack {
                Image(systemName: "trash")
                Text("Delete Wallet")
            }
            .foregroundColor(.cashuError)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
