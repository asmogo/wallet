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
    @StateObject private var walletManager = WalletManager()
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var appLockManager = AppLockManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(walletManager)
                    .environmentObject(navigationManager)
                    .environmentObject(appLockManager)
                    .task {
                        await walletManager.initialize()
                        CashuRequestListener.shared.attach(walletManager: walletManager)
                        await CashuRequestListener.shared.start()
                        await walletManager.checkAllPendingTokens()
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
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    appLockManager.appBecameActive()
                    Task { await CashuRequestListener.shared.start() }
                    Task { await walletManager.checkAllPendingTokens() }
                    Task { await walletManager.syncPendingMintQuotesIfStale() }
                    // Re-arm the pollers stopped on `.background` (both are idempotent
                    // and self-gate on their enabled/connected state).
                    NPCService.shared.applyPollingPreferences()
                    if PriceService.shared.isEnabled {
                        PriceService.shared.startAutoRefresh()
                    }
                case .inactive:
                    // The app-switcher snapshot is taken here, before `.background`.
                    appLockManager.appResignedActive()
                case .background:
                    appLockManager.appResignedActive()
                    Task { await CashuRequestListener.shared.stop() }
                    // Quiesce the timers so no fresh mint network + wallet-DB write kicks
                    // off during the brief background-transition window before suspension.
                    NPCService.shared.stopBackgroundRefresh()
                    PriceService.shared.stopAutoRefresh()
                @unknown default:
                    break
                }
            }
        }
    }
}
