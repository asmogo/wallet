import SwiftUI

struct PaymentRequestsSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payment requests")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)

            Text("Payment requests allow you to receive payments via Nostr relays.")
                .font(.caption)
                .foregroundColor(.cashuMutedText)

            Toggle(isOn: $settings.enablePaymentRequests.animation(.easeInOut(duration: 0.2))) {
                Text("Enable Payment Requests")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

            if settings.enablePaymentRequests {
                Toggle(isOn: $settings.receivePaymentRequestsAutomatically.animation(.easeInOut(duration: 0.2))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claim automatically")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Text("Receive incoming payments automatically.")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
            }
        }
        .padding(.vertical, 8)
    }
}
