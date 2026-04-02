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
                            withAnimation { showNotification = false }
                        }
                    )
                    .padding(.top, 10)
                    .padding(.horizontal)
                    .zIndex(100)
                }

                Spacer()

                // Balance area
                balanceSection

                Spacer()

                // Action buttons pinned near bottom
                actionButtons
                    .padding(.bottom, 40)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation { self.showNotification = false }
                }
            }
        }
    }

    // MARK: - Balance Section

    private var balanceSection: some View {
        VStack(spacing: 24) {
            // Unit toggle
            Button(action: { settings.useBitcoinSymbol.toggle() }) {
                Text(settings.unitLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .liquidGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Display unit: \(settings.unitLabel)")
            .accessibilityHint("Toggles between Bitcoin and Satoshi display")

            // Primary balance
            VStack(spacing: 6) {
                Text(formatBalanceWithUnit(walletManager.balance))
                    .font(.title.bold())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityLabel("Balance: \(formatBalanceWithUnit(walletManager.balance))")

                if settings.showFiatBalance && priceService.btcPriceUSD > 0 {
                    Text(priceService.formatSatsAsFiat(walletManager.balance))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Mint info
            if let mint = walletManager.activeMint {
                Text("\(mint.name)  ·  \(formatBalanceWithUnit(mint.balance))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Status badges
            VStack(spacing: 8) {
                if walletManager.pendingBalance > 0 || !walletManager.pendingTokens.isEmpty {
                    pendingBadge
                }
                if npcService.isEnabled && npcService.isInitialized {
                    lightningAddressBadge
                }
            }
        }
    }

    // MARK: - Pending Badge

    private var pendingBadge: some View {
        Label("Pending: \(formatPendingAmount())", systemImage: "arrow.triangle.2.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Pending balance: \(formatPendingAmount())")
    }

    // MARK: - Lightning Address Badge

    private var lightningAddressBadge: some View {
        Button(action: copyLightningAddress) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(truncatedLightningAddress())
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(1)
                Image(systemName: copiedLightningAddress ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lightning address: \(npcService.lightningAddress)")
        .accessibilityHint("Copies lightning address to clipboard")
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 12) {
                    actionButtonsContent
                }
            } else {
                actionButtonsContent
            }
        }
        .padding(.horizontal, 24)
    }

    private var actionButtonsContent: some View {
        HStack(spacing: 12) {
            Button { showReceiveOptions = true } label: {
                Text("Receive")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .liquidGlass(in: Capsule(), interactive: true)
            }
            .accessibilityHint("Opens options to receive ecash or lightning payments")

            Button { navigationManager.showScannerSheet = true } label: {
                Image(systemName: "viewfinder")
                    .font(.body)
                    .padding(14)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Scan QR code")

            Button { showSendOptions = true } label: {
                Text("Send")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .liquidGlass(in: Capsule(), interactive: true)
            }
            .accessibilityHint("Opens options to send ecash or pay lightning invoices")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Helpers

    private func truncatedLightningAddress() -> String {
        let address = npcService.lightningAddress
        let parts = address.split(separator: "@")
        if parts.count == 2, let pubkey = parts.first, pubkey.count > 16 {
            return "\(pubkey.prefix(8))…\(pubkey.suffix(4))@\(parts[1])"
        }
        return address
    }

    private func copyLightningAddress() {
        UIPasteboard.general.string = npcService.lightningAddress
        withAnimation { copiedLightningAddress = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copiedLightningAddress = false }
        }
    }

    private func formatBalanceWithUnit(_ sats: UInt64) -> String {
        let formatted = settings.formatAmountBalance(sats)
        return settings.useBitcoinSymbol ? "₿\(formatted)" : "\(formatted) sat"
    }

    private func formatPendingAmount() -> String {
        let pendingFromTokens = walletManager.pendingTokens.reduce(UInt64(0)) { $0 + $1.amount }
        let totalPending = max(walletManager.pendingBalance, pendingFromTokens)
        return settings.useBitcoinSymbol ? "₿\(totalPending)" : "\(totalPending) sat"
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
