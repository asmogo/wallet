import SwiftUI
import LocalAuthentication

struct ContentView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var navigationManager: NavigationManager
    @ObservedObject private var cashuRequestListener = CashuRequestListener.shared
    @ObservedObject private var appLock = AppLockManager.shared
    /// The flow cover on screen as of the last change, so a held-approval
    /// page closed without a decision can drop the prompt.
    @State private var lastPresentedCover: FlowCover?
    /// The onboarding→wallet ASCII handoff. Owned here — above the root gate —
    /// so the curtain survives the onboarding teardown it conceals.
    @StateObject private var handoff = OnboardingHandoffCoordinator()

    var body: some View {
        // ZStack (not Group) so the outgoing and incoming roots overlap and truly
        // cross-dissolve. The animation is value-scoped to `needsOnboarding` only,
        // so finishing onboarding/restore fades into the wallet, while the
        // cold-launch LoadingView → root swap stays instant for returning users.
        ZStack {
            if walletManager.isInitialized {
                if walletManager.needsOnboarding {
                    OnboardingView()
                        .transition(.opacity)
                } else {
                    MainTabView()
                        .transition(.opacity)
                }
            } else {
                LoadingView()
                    .transition(.opacity)
            }

            // The ASCII handoff curtain — onboarding's closing beat. While it
            // covers the screen the gate flips beneath it unseen.
            if let session = handoff.session {
                OnboardingHandoffOverlay(session: session, coordinator: handoff)
                    .zIndex(2)
            }
        }
        // Suppressed while a handoff session runs: the curtain is the
        // transition, and the root swap must be instant under its cover.
        // (`completeOnboarding` flips the flag with no `withAnimation`, so
        // this value-scoped modifier is the only animator of the swap.)
        .animation(
            handoff.session == nil ? .easeInOut(duration: 0.35) : nil,
            value: walletManager.needsOnboarding
        )
        // The one full-screen flow-page slot: token claims (scan, deep link,
        // paste-into-flow), scan-routed pay screens, held NUT-18 approvals.
        // `onDismiss` promotes any surface parked by `NavigationManager.present`.
        .fullScreenCover(
            item: $navigationManager.activeFlowCover,
            onDismiss: { navigationManager.coverDidDismiss() }
        ) { cover in
            coverView(for: cover)
        }
        .onChange(of: navigationManager.activeFlowCover?.id) { presentedCoverChanged() }
        .onChange(of: navigationManager.heldDeepLinkTokens) { presentInterruptsIfIdle() }
        .onChange(of: navigationManager.isFlowSurfaceOpen) { presentInterruptsIfIdle() }
        .onChange(of: walletManager.isRuntimeReady, initial: true) { presentInterruptsIfIdle() }
        .onChange(of: cashuRequestListener.heldForApproval) { presentInterruptsIfIdle() }
        .onChange(of: appLock.isLocked) { presentInterruptsIfIdle() }
        .onAppear { presentInterruptsIfIdle() }
        .environmentObject(handoff)
        .confirmationToastHost()
    }

    @ViewBuilder
    private func coverView(for cover: FlowCover) -> some View {
        switch cover {
        case .receiveToken(let token):
            // Full-screen page (not a sheet) so the confirm + success read as
            // a brand-new screen with nothing visible behind.
            ReceiveTokenDetailView(
                tokenString: token,
                onComplete: { navigationManager.activeFlowCover = nil }
            )
            .environmentObject(walletManager)
            .canvasSheetBackground()
        case .heldApproval(let pending):
            // Incoming NUT-18 payment that needs an explicit user decision (mint
            // not tracked yet, or auto-claim disabled) — presented on the standard
            // receive screen, whose built-in "New mint" caution notice covers the
            // trust warning when it applies. The prompt is one-shot: closing it
            // without deciding keeps the payment claimable from its History row.
            ReceiveTokenDetailView(
                tokenString: pending.token,
                onComplete: { navigationManager.activeFlowCover = nil },
                claim: { try await cashuRequestListener.claimHeldPayment(pending) },
                secondaryActionTitle: "Decline",
                onSecondaryAction: {
                    cashuRequestListener.declineHeldPayment(pending)
                    navigationManager.activeFlowCover = nil
                }
            )
            .environmentObject(walletManager)
            .canvasSheetBackground()
        case .melt(let request, let mode, let autoQuote, let explanation):
            MeltView(
                initialRequest: request,
                initialMode: mode,
                autoQuoteOnAppear: autoQuote,
                routeExplanation: explanation,
                onComplete: { navigationManager.activeFlowCover = nil }
            )
            .environmentObject(walletManager)
            .canvasSheetBackground()
        case .cashuRequestPay(let summary):
            CashuPaymentRequestPayView(
                request: summary,
                onComplete: { navigationManager.activeFlowCover = nil }
            )
            .environmentObject(walletManager)
            .canvasSheetBackground()
        }
    }

    private func presentedCoverChanged() {
        let current = navigationManager.activeFlowCover
        if case .heldApproval = lastPresentedCover, current == nil {
            // Screen closed without a decision ("not now"): drop the prompt.
            // The payment stays in the pending-receive store and History.
            cashuRequestListener.dismissHeldPayment()
        }
        lastPresentedCover = current
    }

    /// Present the next queued unprompted surface (deep-linked token, incoming
    /// NUT-18 approval) once every flow surface is idle — the iOS mirror of
    /// Android's shell idle gate. Nothing is dropped: skipped items re-present
    /// on the next idle transition, and a NUT-18 payment additionally stays
    /// claimable from History.
    private func presentInterruptsIfIdle() {
        guard walletManager.isRuntimeReady,
              !walletManager.needsOnboarding,
              !appLock.isLocked,
              !navigationManager.isFlowSurfaceOpen else { return }
        if let token = navigationManager.consumeHeldDeepLinkToken() {
            navigationManager.present(.cover(.receiveToken(token)))
        } else if let held = cashuRequestListener.heldForApproval {
            navigationManager.present(.cover(.heldApproval(held)))
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading Wallet...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var walletManager: WalletManager
    @State private var selectedTab: Tab = .wallet
    
    enum Tab {
        case wallet
        case history
        case mints
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MainWalletView(onViewAllHistory: { selectedTab = .history })
                .tabItem {
                    Label("Wallet", systemImage: "creditcard.fill")
                }
                .tag(Tab.wallet)
            
            tabContent(for: .history) {
                HistoryView()
            }
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(Tab.history)
            
            tabContent(for: .mints) {
                MintsListView()
            }
                .tabItem {
                    Label("Mints", systemImage: "bitcoinsign.bank.building.fill")
                }
                .tag(Tab.mints)
            
        }
    }

    @ViewBuilder
    private func tabContent<Content: View>(
        for tab: Tab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if selectedTab == tab {
            content()
        } else {
            Color.clear
        }
    }
}

// MARK: - App Lock

/// Owns the biometric/passcode app-lock gate. A UI gate only — it never touches
/// the Keychain or token storage, so funds can't be bricked by a failed unlock.
@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    /// Drives the full-screen lock gate.
    @Published private(set) var isLocked: Bool
    /// True while a biometric/passcode evaluation is in flight.
    @Published private(set) var isAuthenticating = false
    /// Drives the app-switcher privacy cover, independent of `isLocked`.
    @Published private(set) var isObscured = false

    /// Wall-clock time the app last resigned active; consumed on return.
    private var backgroundedAt: Date?
    /// Quick app-switches shorter than this don't re-lock.
    private let gracePeriod: TimeInterval = 30

    private var isEnabled: Bool { SettingsManager.shared.appLockEnabled }

    private init() {
        // Cold launch: start locked only if enabled AND we can actually
        // authenticate. Fail open — never strand the user behind a gate we
        // can't open.
        isLocked = SettingsManager.shared.appLockEnabled && Self.canEvaluate()
    }

    /// Whether `deviceOwnerAuthentication` (biometrics OR passcode) is available.
    /// False only when no device passcode is set at all.
    static func canEvaluate() -> Bool {
        var error: NSError?
        let ok = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        if !ok {
            AppLogger.security.warning("App lock unavailable: \(error?.localizedDescription ?? "unknown")")
        }
        return ok
    }

    /// Runs one biometric/passcode evaluation. Returns `true` on success.
    @discardableResult
    func authenticate(reason: String = "Unlock your wallet") async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        // A fresh context per evaluation is mandatory: reusing one short-circuits
        // auth and caches stale enrollment / biometryType.
        let context = LAContext()
        context.localizedFallbackTitle = ""

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            // Capability gap (no passcode) → fail open so funds are never bricked.
            AppLogger.security.warning("Auth unavailable, unlocking: \(policyError?.localizedDescription ?? "unknown")")
            unlock()
            return true
        }

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success { unlock() }
            return success
        } catch {
            // User cancelled / failed → stay locked; the lock view offers a retry.
            AppLogger.security.info("Authentication not completed")
            return false
        }
    }

    private func unlock() {
        isLocked = false
        isObscured = false
        backgroundedAt = nil
    }

    // MARK: Scene phase

    /// Call on `.inactive` and `.background`. Raises the privacy cover and starts
    /// the grace clock. Ignored while we're driving our own auth sheet.
    func appResignedActive() {
        guard isEnabled, !isAuthenticating else { return }
        if backgroundedAt == nil { backgroundedAt = Date() }
        isObscured = true
    }

    /// Call on `.active`. Locks if the grace window elapsed; otherwise drops the
    /// cover. Ignored while our own auth sheet is up (it also cycles scene phase).
    func appBecameActive() {
        guard isEnabled, !isAuthenticating else { return }
        if isLocked { isObscured = true; return }

        if let backgroundedAt, Date().timeIntervalSince(backgroundedAt) >= gracePeriod {
            isLocked = true
            isObscured = true
        } else {
            isObscured = false
        }
        backgroundedAt = nil
    }

    /// Called when the Settings toggle flips. Disabling clears any active gate.
    func setEnabled(_ enabled: Bool) {
        if !enabled { unlock() }
    }
}

/// Full-screen gate shown while the wallet is locked. Auto-prompts once on
/// appear and offers a manual retry if the user cancels.
struct AppLockView: View {
    @EnvironmentObject private var appLock: AppLockManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didPrompt = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: Self.biometryGlyph)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: appLock.isAuthenticating && !reduceMotion)

                Text("Wallet Locked")
                    .font(.title3.weight(.semibold))

                Text("Authenticate to continue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: { Task { await appLock.authenticate() } }) {
                    Text("Unlock")
                }
                .glassButton()
                .disabled(appLock.isAuthenticating)
                .opacity(appLock.isAuthenticating ? 0.5 : 1)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .transition(.opacity)
        .task {
            guard !didPrompt else { return }
            didPrompt = true
            await appLock.authenticate()
        }
    }

    private static var biometryGlyph: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.fill"
        }
    }
}

/// Opaque cover painted while the app is inactive/backgrounded, so balances
/// don't leak into the app-switcher snapshot.
struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ContentView()
        .environmentObject(WalletManager())
        .environmentObject(NavigationManager())
}
