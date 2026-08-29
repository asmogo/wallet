import SwiftUI

/// Restrained full-row feedback for an otherwise background-free row. Reduce
/// Motion keeps the state change instant while retaining the pressed highlight.
struct MethodActionRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.primary.opacity(isEnabled && configuration.isPressed ? 0.08 : 0),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: configuration.isPressed ? 0.09 : 0.18),
                value: configuration.isPressed
            )
    }
}
