import SwiftUI

struct ThemeSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        Group {
            Toggle(isOn: $settings.useBitcoinSymbol) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use \u{20bf} symbol")
                    Text("Use \u{20bf} symbol instead of sats.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
