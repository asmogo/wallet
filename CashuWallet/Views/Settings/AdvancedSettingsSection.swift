import SwiftUI

struct AdvancedSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager

    @Binding var showDeleteConfirm: Bool

    var body: some View {
        Button(action: { showDeleteConfirm = true }) {
            HStack {
                Image(systemName: "trash")
                Text("Delete Wallet")
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
