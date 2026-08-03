import SwiftUI
import UIKit

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

    /// Liquid Glass treatment for text-entry containers. The semantic separator
    /// adds a hairline edge that adapts with the system appearance and increased
    /// contrast settings without changing the field's layout or hit testing.
    func liquidGlassInput<S: InsettableShape>(in shape: S) -> some View {
        self
            .liquidGlass(in: shape)
            .overlay {
                shape
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    .allowsHitTesting(false)
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
    ///
    /// Pass `prominent: true` for the inverted-ink fill (black in light / white
    /// in dark) used by the enabled primary action — matches Android
    /// `PrimaryButton`.
    func glassButton(prominent: Bool = false) -> some View {
        self.buttonStyle(FullWidthCapsuleButtonStyle(prominent: prominent))
    }

    /// Canonical borderless text-link button for tertiary actions
    /// ("Skip", "What is ecash?", "Copy", "Add custom mint URL"). The single
    /// text-link vocabulary in the app — see `TextLinkButtonStyle`.
    func textLinkButton() -> some View {
        self.buttonStyle(TextLinkButtonStyle())
    }

    /// Make a presented sheet/cover read as the same flat canvas as the home
    /// screen — base `systemBackground` (pure black in dark, white in light) —
    /// instead of iOS's default elevated-gray modal background. Apply to the
    /// content of every `.sheet`/`.fullScreenCover` (frosted HUDs excluded).
    func canvasSheetBackground() -> some View {
        modifier(CanvasSheetBackground())
    }

    /// Applies ``canvasSheetBackground()`` only to sheets that fill the screen.
    ///
    /// A full-height sheet replaces the background, so matching the canvas is
    /// right. A sheet that hugs its content floats *over* the canvas and must
    /// keep the system's elevated background to read as a separate layer —
    /// forcing the canvas colour there resolves to the same black as the screen
    /// behind it in dark mode, leaving only a rounded corner to separate them.
    func canvasSheetBackground(whenFillingScreen fillsScreen: Bool) -> some View {
        modifier(ConditionalCanvasSheetBackground(fillsScreen: fillsScreen))
    }

    /// One-shot, opacity-only fade for a full screen's content on entry. Plays
    /// once when the modified view first appears — not on internal state swaps —
    /// with zero positional or scale movement (the presenting sheet/cover owns the
    /// large motion). reduceMotion → instant, fully opaque, no animation.
    func screenEntryFade() -> some View {
        modifier(ScreenEntryFade())
    }

}

// MARK: - Sheet Close Button

/// Close ("xmark") button for sheet / full-screen-cover chrome with a full
/// 44×44pt tap target. A Button whose label is a bare SF Symbol is only
/// hit-testable on the glyph itself (~17pt), which made the sheet close
/// buttons feel broken — near-misses did nothing. Font and color propagate
/// from the call site (`.font`, `.foregroundStyle`), so styled headers can
/// use it too. Defaults to dismissing the enclosing presentation.
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            if let action { action() } else { dismiss() }
        } label: {
            Image(systemName: "xmark")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Close")
    }
}

extension View {
    /// Expands an icon-only toolbar button's label to the HIG-minimum 44×44pt
    /// tap target. Apply inside the label, on the `Image`.
    func toolbarIconTapTarget() -> some View {
        self
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Screen Entry Fade

/// A subtle opacity-only entrance for a screen's content. Because it carries its
/// own `entered` state and its own `.animation(value:)`, it fires exactly once on
/// appear and never interferes with a sibling `.animation(value:)` (e.g. a
/// confirm→success phase morph), which keys on a different value.
private struct ScreenEntryFade: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || entered ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: entered)
            .onAppear { entered = true }
    }
}

// MARK: - Canvas Sheet Background

/// Pins a modal's presentation background to the *base*-elevation `systemBackground`.
/// Inside a sheet the plain semantic resolves to the elevated gray, so we resolve it
/// at base level (for the current color scheme) to match the home canvas exactly.
private struct ConditionalCanvasSheetBackground: ViewModifier {
    let fillsScreen: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if fillsScreen {
            content.canvasSheetBackground()
        } else {
            content
        }
    }
}

private struct CanvasSheetBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.presentationBackground {
            Color(uiColor: UIColor.systemBackground.resolvedColor(
                with: UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
                    UITraitCollection(userInterfaceLevel: .base),
                ])
            ))
            .ignoresSafeArea()
        }
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

// MARK: - Settings Row Icon

/// Leading glyph for settings rows: a plain monochrome SF Symbol (no tile or
/// box), fixed-width so row titles align down a common column. Monochrome
/// (`.secondary` by default, `.red` for the lone destructive row).
struct SettingsRowIcon: View {
    let systemName: String
    var tint: Color = .secondary

    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 28)
            .accessibilityHidden(true)
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
                    .cashuText(.overline)
                    .foregroundStyle(.secondary)
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
///
/// `prominent` swaps to inverted ink — pure black fill / white label in light
/// mode, pure white fill / black label in dark — matching Android
/// `PrimaryButton`. Absolute colors (not `Color.primary` /
/// `systemBackground`) so sheets don't resolve to elevated greys.
struct FullWidthCapsuleButtonStyle: ButtonStyle {
    var prominent: Bool = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let ink = colorScheme == .dark ? Color.white : Color.black
        let onInk = colorScheme == .dark ? Color.black : Color.white

        let label = configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(prominent ? onInk : Color.primary)
            .contentShape(Capsule())

        return Group {
            if prominent {
                label
                    .background(ink, in: Capsule())
                    .scaleEffect(isEnabled && configuration.isPressed ? 0.97 : 1)
            } else if #available(iOS 26, *) {
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
