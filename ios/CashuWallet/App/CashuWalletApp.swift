import SwiftUI
import UIKit

/// Holds a UIKit background-task assertion across an async wallet-DB write so iOS grants a
/// short grace window to finish instead of suspending the app mid-write. A SQLite lock held
/// across suspension is the classic trigger for a `0xdead10cc` termination (which testers
/// experience as a crash). The assertion is always ended via `defer`, including on throw.
@MainActor
func withBackgroundWriteAssertion<T>(
    _ name: String,
    _ work: () async throws -> T
) async rethrows -> T {
    let app = UIApplication.shared
    var taskId: UIBackgroundTaskIdentifier = .invalid
    taskId = app.beginBackgroundTask(withName: name) {
        if taskId != .invalid {
            app.endBackgroundTask(taskId)
            taskId = .invalid
        }
    }
    defer {
        if taskId != .invalid {
            app.endBackgroundTask(taskId)
            taskId = .invalid
        }
    }
    return try await work()
}

@main
struct CashuWalletApp: App {
    @StateObject private var walletManager: WalletManager
    @StateObject private var navigationManager: NavigationManager
    @StateObject private var appLockManager: AppLockManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Repair stdout/stderr before anything can touch the CDK FFI, so a broken
        // stderr can't turn a Rust log write into a bogus "failed printing to stderr"
        // panic that masks the real error. See AppLogger for the full rationale.
        AppLogger.redirectStandardStreamsIfNeeded()
        if IntegrationTestConfig.shouldDisableAnimations {
            UIView.setAnimationsEnabled(false)
        }
        _walletManager = StateObject(wrappedValue: WalletManager())
        _navigationManager = StateObject(wrappedValue: NavigationManager())
        _appLockManager = StateObject(wrappedValue: AppLockManager.shared)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if IntegrationTestConfig.shouldShowComponentCatalog {
                ComponentCatalogView(
                    page: .init(rawValue: IntegrationTestConfig.componentCatalogPage)
                )
                .environmentObject(walletManager)
            } else {
                root
            }
            #else
            root
            #endif
        }
    }

    /// The real app root. Extracted so the debug catalog can stand in for it
    /// without branching inside `some Scene`, where the opaque type won't unify.
    @ViewBuilder
    private var root: some View {
            ZStack {
                ContentView()
                    .environmentObject(walletManager)
                    .environmentObject(navigationManager)
                    .environmentObject(appLockManager)
                    .task {
                        if !IntegrationTestConfig.shouldUseDeterministicUIRuntime {
                            SentryService.initialize()
                        }
                        await walletManager.initialize()
                        guard !IntegrationTestConfig.shouldUseDeterministicUIRuntime else { return }
                        CashuRequestListener.shared.attach(walletManager: walletManager)
                        CashuRequestListener.shared.requestStart()
                        if SettingsManager.shared.checkSentTokens {
                            await walletManager.checkAllPendingTokens()
                        }
                    }
                    .onOpenURL { url in
                        navigationManager.handleDeepLink(url: url)
                    }

                // App-switcher privacy cover (no lock yet). Sits above sheets so
                // backgrounding mid-presentation never leaks content.
                if appLockManager.isObscured && !appLockManager.isLocked {
                    PrivacyCoverView()
                }

                // Lock gate. Window-level so it covers ContentView's full-screen
                // covers and MainTabView's sheets too.
                if appLockManager.isLocked {
                    AppLockView()
                        .environmentObject(appLockManager)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appLockManager.isLocked)
            .transaction { transaction in
                if IntegrationTestConfig.shouldDisableAnimations {
                    transaction.disablesAnimations = true
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard !IntegrationTestConfig.shouldUseDeterministicUIRuntime else { return }
                switch newPhase {
                case .active:
                    appLockManager.appBecameActive()
                    CashuRequestListener.shared.requestStart()
                    if SettingsManager.shared.checkSentTokens {
                        Task { await walletManager.checkAllPendingTokens() }
                    }
                    Task { await walletManager.syncPendingMintQuotesIfStale() }
                    Task { await walletManager.syncPendingMeltQuotes() }
                    Task { await NWCManager.shared.startIfEnabled() }
                    // Re-arm the pollers stopped on `.background` (both are idempotent
                    // and self-gate on their enabled/connected state).
                    NPCService.shared.applyPollingPreferences()
                    if PriceService.shared.isEnabled {
                        PriceService.shared.startAutoRefresh()
                    }
                    walletManager.startPendingQuoteForegroundPolling()
                case .inactive:
                    // The app-switcher snapshot is taken here, before `.background`.
                    appLockManager.appResignedActive()
                case .background:
                    appLockManager.appResignedActive()
                    CashuRequestListener.shared.requestStop()
                    // Quiesce the timers so no fresh mint network + wallet-DB write kicks
                    // off during the brief background-transition window before suspension.
                    NPCService.shared.stopBackgroundRefresh()
                    PriceService.shared.stopAutoRefresh()
                    walletManager.stopPendingQuoteForegroundPolling()
                @unknown default:
                    break
                }
            }
    }
}
