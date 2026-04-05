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

    /// Full-width rounded button. Liquid glass on iOS 26+, bordered capsule on earlier.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
                .controlSize(.large)
        } else {
            self.buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        }
    }
}
