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

    /// Full-width Liquid Glass capsule. Used for all primary CTAs in the app.
    /// Matches the home-screen action row (Receive / Scan / Send) — neutral
    /// glass with a primary-color label, readable in both light and dark mode.
    func glassButton() -> some View {
        self.buttonStyle(FullWidthCapsuleButtonStyle())
    }

}

// MARK: - Canvas Divider

/// Hairline divider used between rows on the single-canvas screens
/// (Lightning Invoice, Pending Ecash, Settings groups, History rows, etc.).
/// Sits directly on the canvas with a subtle inset to the label baseline.
struct CanvasDivider: View {
    var inset: CGFloat = 28

    var body: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

// MARK: - Full Width Capsule Button Style

/// Full-width capsule rendered as subtly-frosted Liquid Glass on iOS 26+,
/// with a `.quaternary` fill fallback on iOS 18–25. The 15% primary-color
/// tint keeps the surface visible even when sitting over an empty dark
/// canvas (where untinted `.regular` glass would nearly disappear).
struct FullWidthCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(.primary)
            .contentShape(Capsule())

        return Group {
            if #available(iOS 26, *) {
                label.glassEffect(
                    .regular.tint(Color.primary.opacity(0.15)).interactive(),
                    in: Capsule()
                )
            } else {
                label.background(.quaternary, in: Capsule())
            }
        }
        .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
        .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
