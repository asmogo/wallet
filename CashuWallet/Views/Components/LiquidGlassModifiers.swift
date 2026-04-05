import SwiftUI

// MARK: - Liquid Glass Adaptive Modifiers
// iOS 26+ Liquid Glass with graceful fallbacks for earlier versions.

extension View {
    /// Applies Liquid Glass on iOS 26+; falls back to `.quaternary` background.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.quaternary, in: shape)
        }
    }

    /// Applies Liquid Glass on iOS 26+; falls back to the given material.
    @ViewBuilder
    func liquidGlassMaterial<S: InsettableShape>(in shape: S, material: Material = .ultraThinMaterial) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(material, in: shape)
        }
    }

    /// Full-width capsule action button. Use for all primary and secondary CTAs.
    func glassButton(prominent: Bool = false) -> some View {
        self.buttonStyle(FullWidthCapsuleButtonStyle())
    }
}

// MARK: - Full Width Capsule Button Style

/// A button style that renders full-width with a capsule shape and subtle tinted background.
/// Adapts to light/dark mode automatically via semantic colors.
struct FullWidthCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.tertiary, in: Capsule())
            .foregroundStyle(.primary)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
