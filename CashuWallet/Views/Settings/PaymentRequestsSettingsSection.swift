import SwiftUI

struct PaymentRequestsSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payment requests")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Payment requests allow you to receive payments via Nostr relays.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: $settings.enablePaymentRequests.animation(.easeInOut(duration: 0.2))) {
                Text("Enable Payment Requests")
                    .font(.subheadline)
            }
            .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))

            if settings.enablePaymentRequests {
                Toggle(isOn: $settings.receivePaymentRequestsAutomatically.animation(.easeInOut(duration: 0.2))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claim automatically")
                            .font(.subheadline)
                                Text("Receive incoming payments automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
            }
        }
        .padding(.vertical, 8)
    }
}
