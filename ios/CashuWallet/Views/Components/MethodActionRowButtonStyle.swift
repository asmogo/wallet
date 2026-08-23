import SwiftUI

/// Restrained full-row feedback: immediate compression, a softer release, and
/// opacity feedback from the solid row surface. Reduce Motion keeps the row
/// stationary while retaining the native pressed-state fade.
struct MethodActionRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isEnabled && configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.38)
            .animation(
                reduceMotion
                    ? nil
                    : .snappy(duration: configuration.isPressed ? 0.09 : 0.18),
                value: configuration.isPressed
            )
    }
}
