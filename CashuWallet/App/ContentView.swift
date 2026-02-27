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
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        ZStack {
            Color.cashuBackground
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                    .scaleEffect(1.5)
                
                Text("Loading Wallet...")
                    .foregroundColor(settings.accentColor)
                    .font(.headline)
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
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
                    Label("Mints", systemImage: "building.columns.fill")
                }
                .tag(Tab.mints)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .tint(settings.accentColor)
        // Add a visual background to the tab bar if needed, though default iOS look is fine
    }
}

#Preview {
    ContentView()
        .environmentObject(WalletManager())
        .environmentObject(NavigationManager())
}
