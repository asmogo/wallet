import SwiftUI

struct PrivacySettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var priceService = PriceService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Text("These settings affect your privacy and wallet responsiveness.")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)

                Toggle(isOn: $settings.checkIncomingInvoices) {
                    Text("Check incoming invoice")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

                Toggle(isOn: $settings.checkPendingOnStartup) {
                    Text("Check pending invoices on startup")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

                Toggle(isOn: $settings.periodicallyCheckIncomingInvoices) {
                    Text("Check all invoices")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
                .disabled(!settings.checkIncomingInvoices)
                .opacity(settings.checkIncomingInvoices ? 1.0 : 0.5)

                Toggle(isOn: $settings.checkSentTokens) {
                    Text("Check sent ecash")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

                Toggle(isOn: $settings.useWebsockets) {
                    Text("Use WebSockets")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
                .disabled(!settings.checkIncomingInvoices && !settings.checkSentTokens)
                .opacity((settings.checkIncomingInvoices || settings.checkSentTokens) ? 1 : 0.5)

                Toggle(isOn: $settings.autoPasteEcashReceive) {
                    Text("Paste ecash automatically")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $settings.showFiatBalance) {
                    Text("Get exchange rate from Coinbase")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

                if settings.showFiatBalance {
                    HStack {
                        Text("Fiat Currency")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                        Spacer()
                        Picker("Currency", selection: $settings.bitcoinPriceCurrency) {
                            ForEach(SettingsManager.supportedFiatCurrencies, id: \.self) { currency in
                                Text(currency).tag(currency)
                            }
                        }
                        .labelsHidden()
                        .tint(settings.accentColor)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BTC Price (\(settings.bitcoinPriceCurrency))")
                                .font(.caption)
                                .foregroundColor(.cashuMutedText)

                            if priceService.btcPriceUSD > 0 {
                                Text(formatBTCPrice(priceService.btcPriceUSD))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            } else {
                                Text("Loading...")
                                    .font(.subheadline)
                                    .foregroundColor(.cashuMutedText)
                            }
                        }

                        Spacer()

                        Button(action: {
                            Task { await priceService.fetchPrice() }
                        }) {
                            if priceService.isFetching {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(settings.accentColor)
                            }
                        }
                        .disabled(priceService.isFetching)
                    }

                    if let lastUpdated = priceService.lastUpdated {
                        Text("Updated \(formatRelativeTime(lastUpdated))")
                            .font(.caption2)
                            .foregroundColor(.cashuMutedText)
                    }

                    if let error = priceService.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.cashuError)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func formatBTCPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = settings.bitcoinPriceCurrency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "\(settings.bitcoinPriceCurrency) 0"
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
