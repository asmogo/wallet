import SwiftUI
import LocalAuthentication

struct ContentView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var siriIntentHandoffStore: SiriIntentHandoffStore
    
    var body: some View {
        Group {
            if walletManager.isInitialized {
                if walletManager.needsOnboarding {
                    OnboardingView()
                } else {
                    MainTabView()
                }
            } else {
                LoadingView()
            }
        }
        .fullScreenCover(isPresented: $navigationManager.showReceiveTokenSheet) {
            if let token = navigationManager.pendingDeepLinkToken {
                ReceiveTokenDetailView(
                    tokenString: token,
                    onComplete: {
                        navigationManager.showReceiveTokenSheet = false
                        navigationManager.pendingDeepLinkToken = nil
                    }
                )
                .environmentObject(walletManager)
            }
        }
        .fullScreenCover(item: $siriIntentHandoffStore.pendingCreateTokenRequest) { request in
            SiriCreateEcashTokenView(
                request: request,
                onComplete: {
                    siriIntentHandoffStore.clearCreateTokenRequest()
                }
            )
            .environmentObject(walletManager)
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
    @EnvironmentObject var siriIntentHandoffStore: SiriIntentHandoffStore
    @State private var selectedTab: Tab = .wallet
    
    enum Tab {
        case wallet
        case history
        case mints
        case settings
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
            
            tabContent(for: .settings) {
                SettingsView()
            }
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .onReceive(siriIntentHandoffStore.$pendingWalletActionRequest.compactMap { $0 }) { request in
            routeSiriWalletAction(request)
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

    private func routeSiriWalletAction(_ request: SiriWalletActionRequest) {
        switch request.action {
        case .wallet:
            selectedTab = .wallet
            siriIntentHandoffStore.clearWalletActionRequest(request)
        case .showHistory:
            selectedTab = .history
            siriIntentHandoffStore.clearWalletActionRequest(request)
        case .showMints:
            selectedTab = .mints
            siriIntentHandoffStore.clearWalletActionRequest(request)
        case .showSettings:
            selectedTab = .settings
            siriIntentHandoffStore.clearWalletActionRequest(request)
        case .receiveEcash,
             .receiveLightning,
             .sendEcash,
             .payLightning,
             .scanQRCode,
             .contactlessPayment:
            selectedTab = .wallet
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
    @State private var didPrompt = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: Self.biometryGlyph)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: appLock.isAuthenticating)

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
