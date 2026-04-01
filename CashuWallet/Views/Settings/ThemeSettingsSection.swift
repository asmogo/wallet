import SwiftUI

struct ThemeSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("On-screen keyboard")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Use the numeric keyboard for entering amounts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $settings.useNumericKeyboard) {
                    Text("Use numeric keyboard")
                        .font(.subheadline)
                }
                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Bitcoin symbol")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Use \u{20bf} symbol instead of sats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $settings.useBitcoinSymbol) {
                    Text("Use \u{20bf} symbol")
                        .font(.subheadline)
                }
                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
            }
        }
        .padding(.vertical, 8)
    }
}
