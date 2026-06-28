import SwiftUI
import AppIntents

@main
struct CashuWalletApp: App {
    @StateObject private var walletManager = WalletManager()
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var appLockManager = AppLockManager.shared
    @StateObject private var siriIntentHandoffStore = SiriIntentHandoffStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(walletManager)
                    .environmentObject(navigationManager)
                    .environmentObject(appLockManager)
                    .environmentObject(siriIntentHandoffStore)
                    .task {
                        SentryService.initialize()
                        siriIntentHandoffStore.restorePendingRequests()
                        await walletManager.initialize()
                        SiriIntentHandoffPersistence.saveWalletSnapshot(from: walletManager)
                        CashuWalletShortcuts.updateAppShortcutParameters()
                        CashuRequestListener.shared.attach(walletManager: walletManager)
                        await CashuRequestListener.shared.start()
                        await walletManager.checkAllPendingTokens()
                        SiriIntentHandoffPersistence.saveWalletSnapshot(from: walletManager)
                    }
                    .onOpenURL { url in
                        navigationManager.handleDeepLink(url: url)
                    }
                    .onChange(of: walletManager.balance) { _, _ in
                        SiriIntentHandoffPersistence.saveWalletSnapshot(from: walletManager)
                    }
                    .onChange(of: walletManager.pendingBalance) { _, _ in
                        SiriIntentHandoffPersistence.saveWalletSnapshot(from: walletManager)
                    }
                    .onChange(of: walletManager.mints) { _, _ in
                        SiriIntentHandoffPersistence.saveWalletSnapshot(from: walletManager)
                    }
                    .onChange(of: walletManager.activeMint) { _, _ in
                        SiriIntentHandoffPersistence.saveWalletSnapshot(from: walletManager)
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
                    siriIntentHandoffStore.restorePendingRequests()
                    Task { await CashuRequestListener.shared.start() }
                    Task {
                        await walletManager.checkAllPendingTokens()
                        SiriIntentHandoffPersistence.saveWalletSnapshot(from: walletManager)
                    }
                    Task {
                        await walletManager.syncPendingMintQuotesIfStale()
                        SiriIntentHandoffPersistence.saveWalletSnapshot(from: walletManager)
                    }
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
