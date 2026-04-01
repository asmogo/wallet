import SwiftUI

@main
struct CashuWalletApp: App {
    @StateObject private var walletManager = WalletManager()
    @StateObject private var navigationManager = NavigationManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(walletManager)
                .environmentObject(navigationManager)
                // Removed forced dark mode — respects system appearance setting
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
                }
                .onOpenURL { url in
                    // Handle cashu: deep links
                    navigationManager.handleDeepLink(url: url)
                }
        }
    }
}
