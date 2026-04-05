import SwiftUI

struct ContentView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var navigationManager: NavigationManager
    
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
        case settings
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MainWalletView()
                .tabItem {
                    Label("Wallet", systemImage: "creditcard.fill")
                }
                .tag(Tab.wallet)
            
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(Tab.history)
            
            MintsListView()
                .tabItem {
                    Label("Mints", systemImage: "bitcoinsign.bank.building.fill")
                }
                .tag(Tab.mints)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WalletManager())
        .environmentObject(NavigationManager())
}
