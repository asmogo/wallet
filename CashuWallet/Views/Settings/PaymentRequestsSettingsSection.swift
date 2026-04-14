import SwiftUI

struct PaymentRequestsSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        Group {
            Text("Payment requests allow you to receive payments via Nostr relays.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: $settings.enablePaymentRequests.animation(.easeInOut(duration: 0.2))) {
                Text("Enable Payment Requests")
            }

            if settings.enablePaymentRequests {
                Toggle(isOn: $settings.receivePaymentRequestsAutomatically.animation(.easeInOut(duration: 0.2))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claim automatically")
                        Text("Receive incoming payments automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
