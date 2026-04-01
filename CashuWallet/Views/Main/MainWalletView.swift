import SwiftUI

struct MainWalletView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var navigationManager: NavigationManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var priceService = PriceService.shared
    @ObservedObject var npcService = NPCService.shared
    @ObservedObject var nostrService = NostrService.shared
    
    @State private var showReceiveOptions = false
    @State private var showSendOptions = false
    @State private var notification: (message: String, amount: UInt64?, fee: UInt64?)?
    @State private var showNotification = false
    @State private var isRefreshing = false
    @State private var copiedLightningAddress = false
    
    // Removed legacy state variables for tabs/history layout
    
    var body: some View {
        NavigationStack {
                VStack(spacing: 0) {
                    // Notification Badge
                    if showNotification, let notif = notification {
                        NotificationBadgeView(
                            message: notif.message,
                            amount: notif.amount,
                            fee: notif.fee,
                            onDismiss: {
                                withAnimation {
                                    showNotification = false
                                }
                            }
                        )
                        .padding(.top, 10)
                        .padding(.horizontal)
                        .zIndex(100)
                    }
                    
                    // Header section (always at top)
                    headerSection
                        .padding(.top, 40)
                    
                    // Spacer to center content
                    Spacer()
                    
                    // Action buttons
                    actionButtons
                        .padding(.bottom, 60)
                    
                    // Spacer for bottom
                    Spacer()
                }
            .sheet(isPresented: $showReceiveOptions) {
                ReceiveView()
                    .environmentObject(walletManager)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showSendOptions) {
                SendView()
                    .environmentObject(walletManager)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $navigationManager.showScannerSheet) {
                 ScannerWrapperView()
                    .environmentObject(walletManager)
                    .presentationDetents([.large])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cashuTokenReceived)) { notification in
            if let userInfo = notification.userInfo,
               let amount = userInfo["amount"] as? UInt64 {
                let fee = userInfo["fee"] as? UInt64
                
                withAnimation {
                    self.notification = (message: "Received", amount: amount, fee: fee)
                    self.showNotification = true
                }
                
                // Auto hide after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation {
                        self.showNotification = false
                    }
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 20) {
            // Unit toggle button (BTC/SAT)
            Button(action: {
                settings.useBitcoinSymbol.toggle()
            }) {
                Text(settings.unitLabel)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Display unit: \(settings.unitLabel)")
            .accessibilityHint("Toggles between Bitcoin and Satoshi display")
            
                // Main balance display
                VStack(spacing: 8) {
                    Text(formatBalanceWithUnit(walletManager.balance))
                        .font(.largeTitle.bold())
                        .minimumScaleFactor(0.5)
                        .accessibilityLabel("Balance: \(formatBalanceWithUnit(walletManager.balance))")
                        .accessibilityValue(formatBalanceWithUnit(walletManager.balance))

                    if settings.showFiatBalance && priceService.btcPriceUSD > 0 {
                        Text(priceService.formatSatsAsFiat(walletManager.balance))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Fiat value: \(priceService.formatSatsAsFiat(walletManager.balance))")
                    }
                }
                .padding(.vertical, 20)
            
            // Mint info section
            if let mint = walletManager.activeMint {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Mint:")
                            .foregroundStyle(.secondary)
                        Text(mint.name)
                    }
                    .font(.body)

                    HStack(spacing: 4) {
                        Text("Balance:")
                            .foregroundStyle(.secondary)
                        Text(formatBalanceWithUnit(mint.balance))
                            .fontWeight(.semibold)
                    }
                    .font(.body)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Active mint: \(mint.name), balance: \(formatBalanceWithUnit(mint.balance))")
            }
            
            // Pending indicator
            if walletManager.pendingBalance > 0 || !walletManager.pendingTokens.isEmpty {
                pendingBadge
                    .padding(.top, 12)
            }
            
            // Lightning address badge (when NPC is enabled)
            if npcService.isEnabled && npcService.isInitialized {
                lightningAddressBadge
                    .padding(.top, 12)
            }
        }
    }
    
    // MARK: - Lightning Address Badge
    
    private var lightningAddressBadge: some View {
        Button(action: copyLightningAddress) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .accessibilityHidden(true)
                Text(truncatedLightningAddress())
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                Image(systemName: copiedLightningAddress ? "checkmark" : "doc.on.doc")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Lightning address: \(npcService.lightningAddress)")
        .accessibilityHint("Copies lightning address to clipboard")
        .accessibilityValue(copiedLightningAddress ? "Copied" : "")
    }
    
    private func truncatedLightningAddress() -> String {
        let address = npcService.lightningAddress
        
        // Truncate hex pubkey addresses for display (show first 8 and last 4 characters before @)
        let parts = address.split(separator: "@")
        if parts.count == 2, let pubkey = parts.first, pubkey.count > 16 {
            let prefix = pubkey.prefix(10)
            let suffix = pubkey.suffix(4)
            return "\(prefix)...\(suffix)@\(parts[1])"
        }
        return address
    }
    
    private func copyLightningAddress() {
        let address = npcService.lightningAddress
        UIPasteboard.general.string = address
        
        withAnimation {
            copiedLightningAddress = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedLightningAddress = false
            }
        }
    }
    
    private var pendingBadge: some View {
        Label("Pending: \(formatPendingAmount())", systemImage: "arrow.triangle.2.circlepath")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Pending balance: \(formatPendingAmount())")
    }
    
    // MARK: - Formatting Helpers
    
    private func formatBalanceWithUnit(_ sats: UInt64) -> String {
        let formatted = settings.formatAmountBalance(sats)
        
        if settings.useBitcoinSymbol {
            return "₿\(formatted)"
        } else {
            return "\(formatted) sat"
        }
    }
    
    private func formatPendingAmount() -> String {
        // Calculate pending from pending tokens
        let pendingFromTokens = walletManager.pendingTokens.reduce(UInt64(0)) { $0 + $1.amount }
        let totalPending = max(walletManager.pendingBalance, pendingFromTokens)
        
        if settings.useBitcoinSymbol {
            return "₿\(totalPending)"
        } else {
            return "\(totalPending) SAT"
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Receive") { showReceiveOptions = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Opens options to receive ecash or lightning payments")

            Button(action: { navigationManager.showScannerSheet = true }) {
                Image(systemName: "viewfinder")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel("Scan QR code")
            .accessibilityHint("Opens camera to scan a QR code")

            Button("Send") { showSendOptions = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Opens options to send ecash or pay lightning invoices")
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Legacy content removed
    // The previous collapsible history/mints content has been moved to separate tabs
    // as per the redesign requirements.
    
    // MARK: - Helpers
    
    private func formatBalance(_ sats: UInt64) -> String {
        let formatted = settings.formatAmountBalance(sats)
        return "\(formatted) sat"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func refreshWallet() async {
        isRefreshing = true
        await walletManager.refreshBalance()
        await walletManager.loadTransactions()
        try? await Task.sleep(nanoseconds: 500_000_000)
        isRefreshing = false
    }
}

#Preview {
    MainWalletView()
        .environmentObject(WalletManager())
        .environmentObject(NavigationManager())
}
