import SwiftUI

// MARK: - Onboarding Handoff

/// The closing beat of onboarding: a full-screen ASCII terrain curtain that
/// sweeps down over the last onboarding screen, holds for one center bloom
/// while the root gate flips beneath it, then slides down and dissolves onto
/// the wallet already in place. Defined under the onboarding motion exemption
/// and owned by onboarding — ContentView only mounts it; nothing here is
/// referenced by wallet-proper code.
///
/// Choreography (T = a completion call site firing `begin`):
///   T+0        curtain reveals top → bottom (0.45s, soft 30%-height edge)
///   T+450ms    gate flip under full cover — the root swap is invisible
///   T+480ms    lens bloom fires at screen center (existing warp envelopes)
///   T+750ms    overlay slides down 20pt and fades out (0.5s)
///   T+1250ms   session ends, overlay unmounts
///
/// Under Reduce Motion or disabled-animation test runs the overlay never
/// mounts and completion runs immediately — ContentView's plain 0.35s
/// crossfade is the entire transition (opacity-or-nothing).

/// One completion handoff. Owns the programmatic lens touch and the closure
/// that flips the root gate; dies with the overlay.
@MainActor
final class OnboardingHandoffSession: Identifiable {
    let id = UUID()
    /// Drives the center bloom on the overlay's terrain — the same warp a
    /// finger drives on the welcome band, fired once by the app itself.
    let touch = AsciiFieldWarpTouch()
    /// `completeOnboarding()` / `completeRestore()`. Runs exactly once, at
    /// full cover.
    let complete: @MainActor () async -> Void
    var didComplete = false

    init(complete: @escaping @MainActor () async -> Void) {
        self.complete = complete
    }
}

/// Owned by ContentView (mounted above the root gate) and handed to
/// OnboardingView through the environment. `begin` is the single entry point
/// for all four completion paths.
@MainActor
final class OnboardingHandoffCoordinator: ObservableObject {
    @Published private(set) var session: OnboardingHandoffSession?

    func begin(reduceMotion: Bool, complete: @escaping @MainActor () async -> Void) {
        guard session == nil else { return }
        if reduceMotion || IntegrationTestConfig.shouldDisableAnimations {
            Task { @MainActor in await complete() }
            return
        }
        session = OnboardingHandoffSession(complete: complete)
    }

    /// The gate flip, run under full cover. Idempotent.
    func completeIfNeeded() async {
        guard let session, !session.didComplete else { return }
        session.didComplete = true
        await session.complete()
    }

    func end() {
        session = nil
    }

    /// Backgrounding escape hatch: run the flip if it hasn't happened and drop
    /// the overlay with no animation, so a mid-sweep exit can never strand the
    /// user in a half-finished handoff.
    func finishImmediately() {
        guard let active = session else { return }
        session = nil
        guard !active.didComplete else { return }
        active.didComplete = true
        Task { @MainActor in await active.complete() }
    }
}

/// The curtain itself: an opaque scrim plus full-bleed drifting terrain,
/// revealed by a sweeping mask. Blocks all input while it runs — the
/// half-born wallet beneath must not be tappable.
struct OnboardingHandoffOverlay: View {
    let session: OnboardingHandoffSession
    let coordinator: OnboardingHandoffCoordinator

    @Environment(\.scenePhase) private var scenePhase
    /// 0 → 1: the mask column (screen height + soft edge) slides from fully
    /// above the window to fully covering it.
    @State private var sweepProgress: CGFloat = 0
    @State private var dissolved = false

    /// Same deterministic-evidence hook as the onboarding band: freezes the
    /// terrain (and skips the bloom) for screenshot runs.
    private static let staticTime: Double? =
        ProcessInfo.processInfo.environment["ASCII_FIELD_STATIC_TIME"].flatMap(Double.init)

    /// Soft leading edge of the sweep, as a fraction of screen height —
    /// mirrors the band's `AsciiFieldLayout.maskFade`.
    private static let sweepEdge: CGFloat = 0.30

    var body: some View {
        GeometryReader { geo in
            let maskHeight = geo.size.height * (1 + Self.sweepEdge)
            ZStack {
                Color(.systemBackground)
                // Full-bleed, no band geometry: the sweep is the only mask.
                AsciiFieldView(
                    staticTime: Self.staticTime,
                    active: true,
                    touchOverride: session.touch
                )
                .allowsHitTesting(false)
            }
            .compositingGroup()
            .mask(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 1 / (1 + Self.sweepEdge)),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: maskHeight)
                .offset(y: (sweepProgress - 1) * maskHeight)
            }
            .offset(y: dissolved ? 20 : 0)
            .opacity(dissolved ? 0 : 1)
            .task(id: session.id) { await run(size: geo.size) }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { coordinator.finishImmediately() }
        }
    }

    private func run(size: CGSize) async {
        withAnimation(.smooth(duration: 0.45)) { sweepProgress = 1 }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        await coordinator.completeIfNeeded()

        try? await Task.sleep(for: .milliseconds(30))
        guard !Task.isCancelled else { return }
        // Bloom only when the field's frame clock can actually render it —
        // under Low Power or a frozen evidence frame the press would sit
        // invisible and release stale.
        let canBloom = Self.staticTime == nil && !ProcessInfo.processInfo.isLowPowerModeEnabled
        if canBloom {
            session.touch.pressOrMove(
                at: CGPoint(x: size.width / 2, y: size.height / 2),
                now: CACurrentMediaTime()
            )
        }

        try? await Task.sleep(for: .milliseconds(270))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.5)) { dissolved = true }

        try? await Task.sleep(for: .milliseconds(10))
        guard !Task.isCancelled else { return }
        if canBloom { session.touch.release(now: CACurrentMediaTime()) }

        try? await Task.sleep(for: .milliseconds(490))
        guard !Task.isCancelled else { return }
        coordinator.end()
    }
}
