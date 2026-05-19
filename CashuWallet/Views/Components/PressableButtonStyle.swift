import SwiftUI

/// Subtle press feedback — scales to 0.97 on touch-down, springs back on release.
/// Asymmetric timing (faster compress than release) keeps the touch feeling immediate
/// while the release stays organic. No color or shadow change — the surface just
/// acknowledges the press.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                .snappy(duration: configuration.isPressed ? 0.09 : 0.18),
                value: configuration.isPressed
            )
    }
}
