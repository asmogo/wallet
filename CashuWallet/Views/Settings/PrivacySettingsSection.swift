import SwiftUI

struct PrivacySettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        LazyVStack(spacing: 0) {
            SettingsSectionGroup(nil) {
                Toggle("Check incoming invoice", isOn: $settings.checkIncomingInvoices)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)

                Toggle("Check all invoices", isOn: $settings.periodicallyCheckIncomingInvoices)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)
                    .disabled(!settings.checkIncomingInvoices)
                    .opacity(settings.checkIncomingInvoices ? 1.0 : 0.5)

                Toggle("Check sent ecash", isOn: $settings.checkSentTokens)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)

                Toggle("Use WebSockets", isOn: $settings.useWebsockets)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)
                    .disabled(!settings.checkIncomingInvoices && !settings.checkSentTokens)
                    .opacity((settings.checkIncomingInvoices || settings.checkSentTokens) ? 1 : 0.5)

                Toggle("Paste ecash automatically", isOn: $settings.autoPasteEcashReceive)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)

                Toggle(isOn: $settings.sentryEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send anonymous crash reports")
                        Text("Helps improve the app. No personal data, wallet addresses, or amounts are ever sent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
            }

            SettingsSectionFooter {
                Text("These settings affect your privacy and wallet responsiveness.")
            }
        }
    }
}
