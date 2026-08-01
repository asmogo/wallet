import SwiftUI

struct PrivacySettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        LazyVStack(spacing: 0) {
            SettingsSectionGroup(nil) {
                Toggle(isOn: $settings.checkIncomingInvoices) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check incoming invoices")
                        Text("Checks for incoming payments while the app is open, contacting the mint each time. Off, the wallet doesn't check on its own.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)

                Toggle(isOn: $settings.periodicallyCheckIncomingInvoices) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repeat checks on a timer")
                        Text("Every couple of minutes while the app is open, each check contacting the mint. Off, the wallet checks only once when it opens.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
                .disabled(!settings.checkIncomingInvoices)
                .opacity(settings.checkIncomingInvoices ? 1.0 : 0.5)

                Toggle(isOn: $settings.checkSentTokens) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check sent ecash")
                        Text("Asks the mint whether sent ecash was claimed, while the app is open. Off, the wallet stays quiet and you check manually instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

                Toggle(isOn: $settings.enablePaymentRequests) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listen for payment requests")
                        Text("Receives ecash sent to your Nostr key while the app is open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)

                Toggle(isOn: $settings.receivePaymentRequestsAutomatically) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Receive payments automatically")
                        Text("Payments from mints you already trust are claimed without asking. Off, you confirm each payment before it's received.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
                .disabled(!settings.enablePaymentRequests)
                .opacity(settings.enablePaymentRequests ? 1.0 : 0.5)

                Toggle(isOn: $settings.sentryEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send crash reports")
                        Text("Opt-in. Screenshots and view hierarchy are not attached. Reports can include technical error details and recent wallet actions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
            }

            SettingsSectionFooter {
                Text("Checks contact the mint over the network — more checks mean faster updates, fewer give the mint less to see.")
            }
        }
    }
}
