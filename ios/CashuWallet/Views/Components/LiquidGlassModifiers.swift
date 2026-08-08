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
    /// ("Skip", "What is ecash?", "Copy", "Add by URL"). The single
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

    /// Measures a content-fit sheet's body for
    /// ``contentFitDetent(_:enabled:estimate:navigationBar:)``. Apply to the body
    /// itself — inside the `NavigationStack`, for the sheets that host one.
    ///
    /// The `ScrollView` is load-bearing, not decoration. A detent derived from a
    /// measurement taken inside that same sheet is a feedback loop — measured
    /// height → detent → sheet height → the height proposed back to the content.
    /// Since the chrome allowance is close to the real chrome, the loop is
    /// *neutrally stable*: it settles wherever the first layout pass left it,
    /// which during the presentation transition is roughly full-screen, and then
    /// never recovers. A `ScrollView` proposes `nil` height to its content, so
    /// the measured view always reports its **ideal** size no matter how tall the
    /// sheet currently is — which breaks the loop.
    ///
    /// Never hang `.onGeometryChange` off a bare view to drive a detent.
    func contentFitMeasured(_ onHeight: @escaping (CGFloat) -> Void) -> some View {
        ScrollView {
            self.onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                onHeight(newHeight)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Sizes a sheet to the height reported by ``contentFitMeasured(_:)``.
    /// Apply on the sheet root, *outside* any `NavigationStack` — detents can't
    /// be set from within the navigation content, which is why this is a pair.
    ///
    /// - Parameters:
    ///   - contentHeight: the measured body height; `0` until geometry lands.
    ///   - enabled: `false` falls through to `.large`, for steps that need the
    ///     full sheet (Send's keypad/confirm, mint discovery's scrolling list).
    ///   - estimate: first-frame stand-in before the measurement arrives, so the
    ///     sheet doesn't open tiny and then jump.
    ///   - navigationBar: whether the sheet hosts a `NavigationStack` with an
    ///     inline title. Pass `false` for a bare sheet, or its detent carries
    ///     44pt of chrome for a navigation bar that isn't there.
    func contentFitDetent(
        _ contentHeight: CGFloat,
        enabled: Bool = true,
        estimate: CGFloat = ContentFitSheetMetrics.bodyEstimate,
        navigationBar: Bool = true
    ) -> some View {
        modifier(ContentFitDetent(
            contentHeight: contentHeight,
            enabled: enabled,
            estimate: estimate,
            navigationBar: navigationBar
        ))
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

// MARK: - Content-Fit Sheet Detent

/// Pins the sheet to the newest computed height.
///
/// Handing `presentationDetents` a fresh single-element set is not enough. The
/// body's height can be reported more than once as layout settles — a transient
/// value, then the real one, milliseconds apart. UIKit resolves the new set but
/// keeps the sheet on whichever detent it had already selected, so a transient
/// measurement wins and the final one is silently ignored. Measured on an
/// iPhone 17 Pro: 0 → 469 → 241pt in 70ms, leaving the sheet stuck at the 547pt
/// detent instead of settling on 319pt.
///
/// Binding the selection alongside the set removes the race — the sheet is told
/// which detent to be on, not merely which are available.
private struct ContentFitDetent: ViewModifier {
    let contentHeight: CGFloat
    let enabled: Bool
    let estimate: CGFloat
    let navigationBar: Bool

    @State private var selection: PresentationDetent

    @MainActor
    init(contentHeight: CGFloat, enabled: Bool, estimate: CGFloat, navigationBar: Bool) {
        self.contentHeight = contentHeight
        self.enabled = enabled
        self.estimate = estimate
        self.navigationBar = navigationBar
        // Seed with a detent the set actually contains. `.large` is not one:
        // while `enabled`, the set holds a single `.height(…)`, so a `.large`
        // seed is an invalid selection and the sheet opens full-height until
        // `onAppear` replaces it. That is a race — the simulator usually wins
        // it, a device often loses — and losing it is what put the Send sheet's
        // no-mints face on a full-height sheet with its content stranded at the
        // top.
        _selection = State(initialValue: Self.detent(
            for: contentHeight,
            enabled: enabled,
            estimate: estimate,
            navigationBar: navigationBar
        ))
    }

    @MainActor
    private static func detent(
        for contentHeight: CGFloat,
        enabled: Bool,
        estimate: CGFloat,
        navigationBar: Bool
    ) -> PresentationDetent {
        guard enabled else { return .large }
        return .height(ContentFitSheetMetrics.detentHeight(
            for: contentHeight,
            estimate: estimate,
            hasNavigationBar: navigationBar
        ))
    }

    private var detent: PresentationDetent {
        Self.detent(
            for: contentHeight,
            enabled: enabled,
            estimate: estimate,
            navigationBar: navigationBar
        )
    }

    func body(content: Content) -> some View {
        content
            .presentationDetents([detent], selection: $selection)
            .onAppear { selection = detent }
            .onChange(of: detent) { _, newDetent in selection = newDetent }
    }
}

// MARK: - Content-Fit Sheet Metrics

/// The one place the content-fit sheet arithmetic lives. Every partial-height
/// sheet in the app — Send's compact input, Receive, Add mint, connect-a-mint,
/// onboarding's "What is ecash?" — hugs its content through
/// ``View/contentFitMeasured(_:)`` +
/// ``View/contentFitDetent(_:enabled:estimate:navigationBar:)``.
@MainActor
enum ContentFitSheetMetrics {
    /// Inline navigation bar — the only chrome that actually consumes layout
    /// height above the body.
    ///
    /// Notably absent: the drag indicator. `presentationDragIndicator` draws the
    /// grabber as an *overlay* over the content's own top padding, so reserving
    /// height for it doesn't move the content down — it just lands as dead space
    /// at the bottom of the sheet. Same for any "breathing room" fudge: each
    /// sheet's body already carries its own bottom padding, and the home
    /// indicator gets the safe-area inset below that.
    static let navigationBar: CGFloat = 44

    /// Chrome above the measured body. The bottom safe area is *not* folded in
    /// here — it's 34pt on Face ID devices and 0 on home-button ones, so it's
    /// resolved per device in ``detentHeight(for:estimate:hasNavigationBar:)``.
    static func chrome(hasNavigationBar: Bool) -> CGFloat {
        hasNavigationBar ? navigationBar : 0
    }

    /// First-frame stand-in before the geometry measurement lands.
    static let bodyEstimate: CGFloat = 220

    /// Ceiling as a fraction of the screen. Past this the body scrolls inside
    /// the sheet rather than the sheet growing — at accessibility text sizes an
    /// unclamped detent would silently pin the sheet to full height.
    static let maxScreenFraction: CGFloat = 0.9

    static func detentHeight(
        for contentHeight: CGFloat,
        estimate: CGFloat = bodyEstimate,
        hasNavigationBar: Bool = true
    ) -> CGFloat {
        let body = contentHeight > 0 ? contentHeight : estimate
        let window = activeWindow
        let wanted = body + chrome(hasNavigationBar: hasNavigationBar) + (window?.safeAreaInsets.bottom ?? 0)
        // Read the ceiling from the *screen*, never from the sheet's own
        // geometry — the latter would reintroduce the feedback loop this whole
        // mechanism exists to avoid.
        guard let screenHeight = window?.screen.bounds.height, screenHeight > 0 else { return wanted }
        return min(wanted, screenHeight * maxScreenFraction)
    }

    private static var activeWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? scene?.windows.first
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
/// "Add by URL"). The single canonical style for plain text links —
/// `.subheadline.weight(.medium)`, `.secondary`, with a press-dim and disabled
/// fade that match the rest of the button family. Layout (full-width, padding,
/// optional leading SF Symbol) stays at the call site, since text links vary
/// from inline ("Copy") to full-width ("Add by URL").
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
