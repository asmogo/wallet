import SwiftUI

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
                case .inactive:
                    // The app-switcher snapshot is taken here, before `.background`.
                    appLockManager.appResignedActive()
                case .background:
                    appLockManager.appResignedActive()
                    Task { await CashuRequestListener.shared.stop() }
                @unknown default:
                    break
                }
            }
        }
    }
}
