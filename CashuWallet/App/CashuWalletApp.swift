import SwiftUI

@main
struct CashuWalletApp: App {
    @StateObject private var walletManager = WalletManager()
    @StateObject private var navigationManager = NavigationManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletManager)
                .environmentObject(navigationManager)
                .task {
                    await walletManager.initialize()
                    let (shouldCheckPending, shouldTrackSentTokens) = await MainActor.run {
                        (
                            SettingsManager.shared.checkPendingOnStartup,
                            SettingsManager.shared.checkSentTokens
                        )
                    }
                    if shouldCheckPending && shouldTrackSentTokens {
                        await walletManager.checkAllPendingTokens()
                    }
                    CashuRequestListener.shared.attach(walletManager: walletManager)
                    await CashuRequestListener.shared.start()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        Task { await CashuRequestListener.shared.start() }
                    case .background:
                        Task { await CashuRequestListener.shared.stop() }
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    navigationManager.handleDeepLink(url: url)
                }
        }
    }
}
