import SwiftUI
import UIKit

// MARK: - Liquid Glass Adaptive Modifiers
// iOS 26+ Liquid Glass with graceful fallbacks for earlier versions.

extension EnvironmentValues {
    /// Identifies the presentation surface shared controls are rendered on.
    /// Compact sheets use an explicit tonal hierarchy; large flat sheets retain
    /// their existing semantic fills, and the wallet canvas keeps Liquid Glass.
    @Entry var bottomSheetSurfaceStyle: BottomSheetSurfaceStyle = .glass
}

enum BottomSheetSurfaceStyle {
    case glass
    case flat
    case compact
}

enum CompactSheetPalette {
    static func sheet(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
            : Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
    }

    static func control(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255)
            : Color(red: 237 / 255, green: 237 / 255, blue: 237 / 255)
    }

    static func iconInset(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black : .white
    }
}

extension View {
    /// Applies Liquid Glass on iOS 26+; falls back to `.quaternary` background.
    func liquidGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(AdaptiveGlassSurface(shape: shape, interactive: interactive))
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
    func liquidGlassMaterial<S: InsettableShape>(in shape: S, material: Material = .ultraThinMaterial) -> some View {
        modifier(AdaptiveGlassSurface(shape: shape, interactive: false, fallbackMaterial: material))
    }

    /// Full-width CTA capsule. Outside a flat bottom sheet it matches the
    /// home-screen's neutral Liquid Glass action; inside one it becomes a
    /// solid inverse-ink primary action.
    ///
    /// Pass `prominent: true` for the inverted-ink fill (black in light / white
    /// in dark) used by the enabled primary action — matches Android
    /// `PrimaryButton`.
    func glassButton(prominent: Bool = false) -> some View {
        self.buttonStyle(FullWidthCapsuleButtonStyle(prominent: prominent))
    }

    /// A quiet, filled action for the secondary slot beside a sheet's single
    /// primary CTA (for example, Add Mint's Paste action).
    func flatSheetSecondaryButton() -> some View {
        self.buttonStyle(FlatSheetSecondaryButtonStyle())
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

    /// Gives an app-designed bottom sheet the same opaque, adaptive surface as
    /// the mint selector. The environment flag also converts shared glass
    /// controls contained by this presentation into quiet semantic fills.
    func flatBottomSheetSurface() -> some View {
        self
            .environment(\.bottomSheetSurfaceStyle, .flat)
            .presentationBackground(Color(uiColor: .systemBackground))
    }

    /// Opaque, elevated surface for content-fit and fixed-height sheets. The
    /// perimeter catches a restrained amount of light without replacing the
    /// native sheet's shape, detents, dimming, or gesture behavior.
    func compactBottomSheetSurface() -> some View {
        self
            .environment(\.bottomSheetSurfaceStyle, .compact)
            .presentationBackground {
                CompactSheetBackground()
            }
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
        modifier(ContentFitMeasure(onHeight: onHeight))
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
    ///   - step: identity of the face that currently owns the height. Only
    ///     meaningful alongside `stepResize`.
    ///   - stepResize: how long the sheet takes to change height when `step`
    ///     changes; `nil` (the default) snaps. A duration rather than an
    ///     `Animation` because the modifier has to know when the move is over,
    ///     not only how to start it.
    func contentFitDetent(
        _ contentHeight: CGFloat,
        enabled: Bool = true,
        estimate: CGFloat = ContentFitSheetMetrics.bodyEstimate,
        navigationBar: Bool = true,
        step: AnyHashable? = nil,
        stepResize: Duration? = nil
    ) -> some View {
        modifier(ContentFitDetent(
            contentHeight: contentHeight,
            enabled: enabled,
            estimate: estimate,
            navigationBar: navigationBar,
            step: step,
            stepResize: stepResize
        ))
    }

    /// Dissolves scroll content into the chrome at one or both edges, so rows
    /// fade out as they approach a pinned header or CTA instead of cutting
    /// against it.
    ///
    /// `top` / `bottom` are the distances from each edge at which the content is
    /// still fully clear — pass the measured height of whatever chrome sits
    /// there. The `band` above/below that inset is the gradient itself. `nil`
    /// leaves that edge alone, which is why `0` has to stay meaningful: it means
    /// "fade right at the container's own edge", the case where the chrome is a
    /// sibling rather than an overlay.
    ///
    /// One mask with one stop list, never two stacked masks — overlapping masks
    /// multiply their alpha and the shared band comes out twice as dark as
    /// either edge alone. Android mirrors this in `Modifier.scrollEdgeFade`.
    func scrollEdgeFade(
        top: CGFloat? = nil,
        bottom: CGFloat? = nil,
        band: CGFloat = ScrollFadeMetrics.band
    ) -> some View {
        mask {
            GeometryReader { proxy in
                LinearGradient(
                    stops: ScrollFadeMetrics.stops(
                        total: proxy.size.height,
                        top: top,
                        bottom: bottom,
                        band: band
                    ),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

}

/// Shared implementation for the legacy glass modifiers. Bottom sheets opt
/// into an opaque surface vocabulary through the environment; all other views
/// retain their existing iOS 26 Liquid Glass behavior and earlier-OS fallback.
private struct AdaptiveGlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.bottomSheetSurfaceStyle) private var bottomSheetSurfaceStyle
    @Environment(\.colorScheme) private var colorScheme

    let shape: S
    let interactive: Bool
    var fallbackMaterial: Material?

    @ViewBuilder
    func body(content: Content) -> some View {
        if bottomSheetSurfaceStyle == .compact {
            content.background(CompactSheetPalette.control(for: colorScheme), in: shape)
        } else if bottomSheetSurfaceStyle == .flat {
            content.background(Color.primary.opacity(0.11), in: shape)
        } else if #available(iOS 26, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else if let fallbackMaterial {
            content.background(fallbackMaterial, in: shape)
        } else {
            content.background(.quaternary, in: shape)
        }
    }
}

struct CompactSheetBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var rimMultiplier: Double {
        colorSchemeContrast == .increased ? 1.35 : 1
    }

    private var rimColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var rimOpacities: (top: Double, middle: Double, bottom: Double) {
        colorScheme == .dark ? (0.24, 0.10, 0.04) : (0.16, 0.07, 0.03)
    }

    var body: some View {
        CompactSheetPalette.sheet(for: colorScheme)
            .overlay {
                ContainerRelativeShape()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: rimColor.opacity(min(rimOpacities.top * rimMultiplier, 1)),
                                    location: 0
                                ),
                                .init(
                                    color: rimColor.opacity(min(rimOpacities.middle * rimMultiplier, 1)),
                                    location: 0.45
                                ),
                                .init(
                                    color: rimColor.opacity(min(rimOpacities.bottom * rimMultiplier, 1)),
                                    location: 1
                                ),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.5
                    )
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Scroll Edge Fade

enum ScrollFadeMetrics {
    /// Distance over which content dissolves. Android holds the same value in
    /// `ScrollEdgeFade.kt` — the two fades are meant to be indistinguishable, so
    /// this number only ever moves in both places at once.
    static let band: CGFloat = 24

    /// Mask stops for ``SwiftUI/View/scrollEdgeFade(top:bottom:band:)``.
    ///
    /// Locations are forced non-decreasing on the way out. On a short container
    /// the two bands can otherwise cross, and a `LinearGradient` handed
    /// out-of-order stops renders a hard seam rather than clamping.
    static func stops(
        total rawTotal: CGFloat,
        top: CGFloat?,
        bottom: CGFloat?,
        band: CGFloat
    ) -> [Gradient.Stop] {
        let total = max(rawTotal, 1)
        var stops: [Gradient.Stop] = []

        if let top {
            stops.append(.init(color: .clear, location: 0))
            stops.append(.init(color: .clear, location: top / total))
            stops.append(.init(color: .black, location: (top + band) / total))
        } else {
            stops.append(.init(color: .black, location: 0))
        }

        if let bottom {
            stops.append(.init(color: .black, location: 1 - (bottom + band) / total))
            stops.append(.init(color: .clear, location: 1 - bottom / total))
            stops.append(.init(color: .clear, location: 1))
        } else {
            stops.append(.init(color: .black, location: 1))
        }

        var highWater: CGFloat = 0
        return stops.map { stop in
            highWater = max(highWater, min(max(stop.location, 0), 1))
            return .init(color: stop.color, location: highWater)
        }
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

// MARK: - Shared Axis

/// Material 3 shared axis X — the same spec Android's `TwoFaceScreen` uses, so a
/// step swap reads identically on both platforms: both faces travel 30pt in one
/// direction over 300ms while the outgoing fades out and the incoming fades in.
///
/// This exists because a `NavigationStack` push cannot be used where the sheet's
/// height changes with the step. For the length of a UIKit push or pop the
/// arriving page is laid out at the *departing* page's height, so a sheet that
/// resizes with the transition delivers that page clipped — measured on an
/// iPhone 17 Pro, the mint shortlist came back cut through a row with ~158pt of
/// empty sheet under it. Holding the resize until the transition ends trades the
/// clip for a sheet that lands, pauses, then grows. Swapping the faces in place
/// has neither problem: the slide is ours, nothing is laid out against a stale
/// height, and the detent animates on the same beat.
///
/// The cost is the interactive back-swipe, which belongs to the push being given
/// up; callers draw a back control instead, exactly as Android does.
enum SharedAxis {
    static let duration: Duration = .seconds(0.3)
    private static let slide: CGFloat = 30
    private static let outgoingFade: TimeInterval = 0.09
    private static let incomingFade: TimeInterval = 0.21

    static func transition(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        // The fades are staged, not crossed: the outgoing face is gone in 90ms
        // and the incoming one only starts after that. A plain symmetric
        // cross-dissolve leaves both legible at once and the two sets of rows
        // read as a double exposure. The travel keeps the full duration, so the
        // motion stays continuous underneath the swap.
        let travel = Animation.smooth(duration: 0.3)
        let out = Animation.easeIn(duration: outgoingFade)
        let incoming = Animation.easeOut(duration: incomingFade).delay(outgoingFade)
        return .asymmetric(
            insertion: .offset(x: forward ? slide : -slide).animation(travel)
                .combined(with: .opacity.animation(incoming)),
            removal: .offset(x: forward ? -slide : slide).animation(travel)
                .combined(with: .opacity.animation(out))
        )
    }

    /// Drives the swap — the content transition *and* the sheet detent moving
    /// alongside it, so they are one motion rather than two.
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3)
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

// MARK: - Content-Fit Sheet Measurement

/// Reports the body's ideal height, but only from a layout pass that has actually
/// happened. See ``View/contentFitMeasured(_:)``.
///
/// The first pass after a sheet is presented reports garbage. Measured on an
/// iPhone 17 Pro presenting Send's no-mints face: the content comes back
/// **139.7 × 1032.3** while the enclosing `ScrollView` is still **139.7 × 0** —
/// the sheet has no laid-out geometry yet, so the body is measured at a third of
/// its real width, every line of text wraps about three times over, and the ideal
/// height is nearly triple the truth. The real pass, 402 × 368.3, lands
/// immediately after.
///
/// Passed straight through, that first number sets the detent to
/// `min(1032 + chrome, 90% of the screen)` — a full-height sheet with the content
/// stranded at the top, the exact bug this file's detent machinery kept being
/// blamed for. Recovery then depends on the corrected measurement arriving *and*
/// UIKit honouring it; a simulator wins that, a device need not.
///
/// So nothing is published until the container has a real height, and the last
/// measurement is re-published when it gets one. Gating on the container rather
/// than on the number itself keeps genuinely tall content — accessibility text
/// sizes — free to exceed the screen and scroll, which is what the ceiling in
/// ``ContentFitSheetMetrics/maxScreenFraction`` is for.
private struct ContentFitMeasure: ViewModifier {
    let onHeight: (CGFloat) -> Void

    @State private var bodyHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0

    func body(content: Content) -> some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                bodyHeight = newHeight
                publish()
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Fires *after* the body's own measurement on the pass that gives the
        // sheet its geometry, which is why the republish here is load-bearing:
        // the real body height is already known by then and would otherwise
        // never be reported.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            containerHeight = newHeight
            publish()
        }
    }

    private func publish() {
        guard containerHeight > 0, bodyHeight > 0 else { return }
        onHeight(bodyHeight)
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
    let step: AnyHashable?
    let stepResize: Duration?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: PresentationDetent
    /// The step `selection` was last chosen for, so a height change can be told
    /// apart from a step change. See ``apply(_:)``.
    @State private var lastStep: AnyHashable?
    /// Each step's last-known height, and whether a step resize is in flight.
    /// Both exist to keep ``detents`` right for the length of a move.
    @State private var knownPerStep: [AnyHashable?: PresentationDetent] = [:]
    @State private var moving = false
    @State private var moves = 0

    @MainActor
    init(
        contentHeight: CGFloat,
        enabled: Bool,
        estimate: CGFloat,
        navigationBar: Bool,
        step: AnyHashable?,
        stepResize: Duration?
    ) {
        self.contentHeight = contentHeight
        self.enabled = enabled
        self.estimate = estimate
        self.navigationBar = navigationBar
        self.step = step
        self.stepResize = stepResize
        // Seeded, not left nil: the first measurement to land after presentation
        // belongs to the step the sheet opened on, not a move to a new one.
        _lastStep = State(initialValue: step)
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

    /// The height being moved to, plus the one currently selected.
    ///
    /// At rest those are the same value, so this is a one-element set and the
    /// sheet is not user-draggable. They differ for exactly one update — a new
    /// measurement lands, `body` re-runs with the new `detent`, and `onChange`
    /// has not yet moved `selection` onto it — and that single update is the
    /// whole bug: a `selection` the set does not contain is invalid, and UIKit
    /// answers an invalid selection by opening the sheet **full height**.
    ///
    /// Seeding `selection` in `init` (see there) narrowed that window but cannot
    /// close it, because the set is recomputed from the live `contentHeight`
    /// while `selection` is frozen at the value from first construction. Whether
    /// the window is ever observed is pure timing — the same commit that never
    /// reproduced under XCUITest on a simulator reproduced every launch from
    /// Xcode, on Send's no-mints face. Keeping the old selection a member removes
    /// the race rather than narrowing it: the sheet holds its current height for
    /// that one update, then `onChange` converges it.
    ///
    /// Mid-resize the set additionally keeps every step's last-known height. A
    /// selection change only animates if the set holds the height the sheet is
    /// *currently* at for the whole animation; let a member drop the moment the
    /// selection lands and UIKit resizes on the spot, abandoning the animation a
    /// frame in. Measured: one intermediate height instead of twenty-plus.
    private var detents: Set<PresentationDetent> {
        guard stepResize != nil, moving else { return [detent, selection] }
        return Set(knownPerStep.values).union([detent, selection])
    }

    func body(content: Content) -> some View {
        content
            .presentationDetents(detents, selection: $selection)
            .onAppear { apply(detent) }
            .onChange(of: detent) { _, newDetent in apply(newDetent) }
            // Keyed on the move counter so a second push/pop cancels the first
            // one's settle instead of pruning the set out from under it.
            .task(id: moves) {
                guard moving, let stepResize else { return }
                try? await Task.sleep(for: stepResize + .milliseconds(120))
                moving = false
            }
    }

    /// Snaps by default. A caller that opted into `stepResize` gets an animated
    /// move, but only when the *step* changes: the height also changes as one
    /// step's measurement settles, and that arrives while the sheet is still
    /// sliding up, so animating it would make every content-fit sheet in the app
    /// visibly grow as it opens.
    private func apply(_ newDetent: PresentationDetent) {
        defer {
            lastStep = step
            if stepResize != nil { knownPerStep[step] = newDetent }
        }
        guard let stepResize, step != lastStep, !reduceMotion else {
            selection = newDetent
            return
        }
        moving = true
        moves += 1
        withAnimation(.smooth(duration: stepResize.seconds)) { selection = newDetent }
    }
}

private extension Duration {
    /// `Animation` still speaks in seconds.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
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
        let bottomInset: CGFloat
        if #available(iOS 26, *) {
            // iOS 26's floating glass sheets already rest above the home
            // indicator, so the window's bottom inset no longer applies to
            // sheet content — folding it in lands as dead space under the
            // sheet's own bottom padding (visible under onboarding's "Got it").
            bottomInset = 0
        } else {
            bottomInset = window?.safeAreaInsets.bottom ?? 0
        }
        let wanted = body + chrome(hasNavigationBar: hasNavigationBar) + bottomInset
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
/// with a `.quaternary` fill fallback on iOS 18–25. In a flat bottom sheet,
/// the same control becomes opaque inverse ink so its commit action remains
/// unmistakable against the quiet sheet surface.
///
/// `prominent` swaps to inverted ink — pure black fill / white label in light
/// mode, pure white fill / black label in dark — matching Android
/// `PrimaryButton`. Absolute colors (not `Color.primary` /
/// `systemBackground`) so sheets don't resolve to elevated greys.
struct FullWidthCapsuleButtonStyle: ButtonStyle {
    var prominent: Bool = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bottomSheetSurfaceStyle) private var bottomSheetSurfaceStyle

    func makeBody(configuration: Configuration) -> some View {
        let ink = colorScheme == .dark ? Color.white : Color.black
        let onInk = colorScheme == .dark ? Color.black : Color.white

        let label = configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(prominent || bottomSheetSurfaceStyle != .glass ? onInk : Color.primary)
            .contentShape(Capsule())

        return Group {
            if prominent || bottomSheetSurfaceStyle != .glass {
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
        // Asymmetric, matching PressableButtonStyle: feedback belongs on
        // touch-down and has to feel immediate, while the release is the system
        // responding and can settle.
        .animation(
            .snappy(duration: configuration.isPressed ? 0.09 : 0.18),
            value: configuration.isPressed
        )
    }
}

/// Equal-weight secondary companion to the solid primary sheet CTA. This is
/// intentionally opaque and quiet: sheets use it for a reversible helper
/// action, never to compete with the committing action alongside it.
struct FlatSheetSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(0.11), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(isEnabled && configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .animation(
                .snappy(duration: configuration.isPressed ? 0.09 : 0.18),
                value: configuration.isPressed
            )
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
            .animation(
                .snappy(duration: configuration.isPressed ? 0.09 : 0.18),
                value: configuration.isPressed
            )
    }
}

// MARK: - Materialize transition (DESIGN.md §6 carve-out)

extension AnyTransition {
    /// Blur-to-sharp "materialize": content resolves from blur → sharp as it
    /// enters, riding whatever curve the caller animates with. It makes an
    /// element come *into focus* rather than merely scaling in. DESIGN.md §6
    /// carve-out — confirmation glyphs plus the onboarding stage and headline
    /// swaps (pre-wallet exemption), never money values; callers gate it
    /// behind `!reduceMotion` (this composes only onto non-reduce-motion
    /// branches).
    static var materializeBlur: AnyTransition { materializeBlur(radius: 4) }

    /// Parameterized variant: onboarding's stage swap enters at radius 6 and
    /// its chassis headline at 3 (onboarding-restyle-brief §5).
    static func materializeBlur(radius: CGFloat) -> AnyTransition {
        .modifier(
            active: BlurMaterializeModifier(radius: radius),
            identity: BlurMaterializeModifier(radius: 0)
        )
    }
}

private struct BlurMaterializeModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
