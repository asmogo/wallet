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

    /// Canonical borderless text-link button for tertiary actions
    /// ("Skip", "What is ecash?", "Copy", "Add custom mint URL"). The single
    /// text-link vocabulary in the app — see `TextLinkButtonStyle`.
    func textLinkButton() -> some View {
        self.buttonStyle(TextLinkButtonStyle())
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

// MARK: - Settings Canvas Components

/// Section grouping on a single-canvas Settings screen. Renders an
/// uppercase tracking-spaced title above its content; matches the
/// shape used by the root `SettingsView` so detail screens read as
/// the same family.
struct SettingsSectionGroup<Content: View>: View {
    let title: String?
    let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .padding(.horizontal, 4)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            } else {
                Color.clear.frame(height: 8)
            }

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 4)
        }
    }
}

/// Section footer text on a single-canvas Settings screen. Visual
/// weight matches an iOS Form section footer without nesting cards.
struct SettingsSectionFooter<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 12)
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
                // iOS 26's `.interactive()` glass supplies its own press squish;
                // the fallback surface gets a scale-on-press so the tactile
                // feedback is at parity below iOS 26.
                label.background(.quaternary, in: Capsule())
                    .scaleEffect(isEnabled && configuration.isPressed ? 0.97 : 1)
            }
        }
        .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
        .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Text Link Button Style

/// Borderless, text-only tertiary action ("Skip", "What is ecash?", "Copy",
/// "Add custom mint URL"). The single canonical style for plain text links —
/// `.subheadline.weight(.medium)`, `.secondary`, with a press-dim and disabled
/// fade that match the rest of the button family. Layout (full-width, padding,
/// optional leading SF Symbol) stays at the call site, since text links vary
/// from inline ("Copy") to full-width ("Add custom mint URL").
struct TextLinkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
