import SwiftUI

struct ThemeSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("On-screen keyboard")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Text("Use the numeric keyboard for entering amounts.")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)

                Toggle(isOn: $settings.useNumericKeyboard) {
                    Text("Use numeric keyboard")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Bitcoin symbol")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Text("Use \u{20bf} symbol instead of sats.")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)

                Toggle(isOn: $settings.useBitcoinSymbol) {
                    Text("Use \u{20bf} symbol")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Text("Change how your wallet looks.")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                    ForEach(Array(SettingsManager.themeColors.enumerated()), id: \.element.id) { index, theme in
                        themeColorButton(theme: theme, index: index)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Theme Color Button

    private func themeColorButton(theme: ThemeColor, index: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.selectedThemeIndex = index
            }
        }) {
            ZStack {
                Circle()
                    .fill(theme.color)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.black.opacity(0.3))
                    )

                if settings.selectedThemeIndex == index {
                    Circle()
                        .stroke(theme.color, lineWidth: 3)
                        .frame(width: 46, height: 46)
                }
            }
        }
    }
}
