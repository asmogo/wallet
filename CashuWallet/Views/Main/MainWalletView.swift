import CoreNFC
import SwiftUI

struct MainWalletView: View {
    /// Called when the user taps "View all activity" — switches the tab
    /// container to the History tab. Lives at the call-site so
    /// MainWalletView stays decoupled from the Tab enum.
    var onViewAllHistory: () -> Void = {}

    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var navigationManager: NavigationManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var priceService = PriceService.shared
    @ObservedObject private var requestStore = CashuRequestStore.shared

    @State private var activeSheet: WalletSheet?
    @State private var notification: (message: String, amount: UInt64?, fee: UInt64?)?
    @State private var showNotification = false
    @State private var receiveEcashDetent: PresentationDetent = .medium
    @State private var contactlessCoordinator = ContactlessPaymentCoordinator()
    @State private var selectedTransaction: WalletTransaction?
    @State private var selectedRequest: CashuRequest?
    @State private var topInsetHeight: CGFloat = 0
    @State private var isCheckingStatus: String? = nil

    private let recentRowCap = 5
    private let scrollFadeBand: CGFloat = 24

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Notification banner (in-flow at top, slides in/out)
                    if showNotification, let notif = notification {
                        NotificationBadgeView(
                            message: notif.message,
                            amount: notif.amount,
                            fee: notif.fee,
                            onDismiss: {
                                withAnimation { showNotification = false }
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .zIndex(100)
                    }

                    recentSection
                        .padding(.top, 8)
                        .padding(.horizontal, 16)

                    // Tail spacer so the last row can scroll under the
                    // Liquid Glass tab bar without sitting flush against it.
                    Color.clear.frame(height: 32)
                }
            }
            .scrollIndicators(.hidden)
            .mask(scrollFadeMask)
            .safeAreaInset(edge: .top, spacing: 0) {
                fixedTopSection
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TopInsetHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
            }
            .onPreferenceChange(TopInsetHeightKey.self) { topInsetHeight = $0 }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .scanner
                    } label: {
                        Image(systemName: "viewfinder")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Scan QR code")
                    .accessibilityHint("Opens the QR scanner")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                sheetView(for: sheet)
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
                    .environmentObject(walletManager)
            }
            .navigationDestination(item: $selectedRequest) { request in
                CashuRequestDetailView(request: request)
                    .environmentObject(walletManager)
            }
            .task { await walletManager.loadTransactions() }
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
        .onReceive(navigationManager.$pendingMeltInvoice.compactMap { $0 }) { invoice in
            activeSheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                activeSheet = .flow(.sendLightningWithInvoice(invoice))
                navigationManager.pendingMeltInvoice = nil
            }
        }
    }

    // MARK: - Fixed Top Section

    // Pinned above the scroll. Sits on the bare canvas so the masked scroll
    // content reads as floating beneath it.
    private var fixedTopSection: some View {
        VStack(spacing: 0) {
            balanceSection
                .padding(.top, 8)

            actionButtons
                .padding(.top, 28)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    // Fades scroll content to clear under the fixed top section so rows
    // visibly dissolve as they approach the buttons.
    private var scrollFadeMask: some View {
        GeometryReader { proxy in
            let total = max(proxy.size.height, 1)
            let inset = max(topInsetHeight, 1)
            let clearEnd = min(inset / total, 1)
            let opaqueAt = min((inset + scrollFadeBand) / total, 1)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: clearEnd),
                    .init(color: .black, location: opaqueAt),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Balance Section

    private var balanceSection: some View {
        VStack(spacing: 0) {
            mintChip

            // Primary balance — tap to toggle Bitcoin / Satoshi display
            VStack(spacing: 6) {
                Button(action: {
                    HapticFeedback.selection()
                    settings.useBitcoinSymbol.toggle()
                }) {
                    Text(formatBalanceWithUnit(walletManager.balance))
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: Double(walletManager.balance)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Balance: \(formatBalanceWithUnit(walletManager.balance))")
                .accessibilityHint("Tap to toggle between Bitcoin and Satoshi")

                if settings.showFiatBalance && priceService.btcPriceUSD > 0 {
                    Text(priceService.formatSatsAsFiat(walletManager.balance))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 18)
        }
    }

    // MARK: - Active Mint Chip

    @ViewBuilder
    private var mintChip: some View {
        if let active = walletManager.activeMint {
            Menu {
                ForEach(walletManager.mints) { mint in
                    Button {
                        HapticFeedback.selection()
                        Task { try? await walletManager.setActiveMint(mint) }
                    } label: {
                        if mint.id == active.id {
                            Label(mint.name, systemImage: "checkmark")
                        } else {
                            Text(mint.name)
                        }
                    }
                }

                Divider()

                Button {
                    activeSheet = .discoverMints
                } label: {
                    Label("Add Mint", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 8) {
                    mintChipIcon(url: active.iconUrl)
                    Text(active.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .liquidGlass(in: Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .accessibilityLabel("Active mint: \(active.name)")
            .accessibilityHint("Choose a different active mint")
        }
    }

    @ViewBuilder
    private func mintChipIcon(url: String?) -> some View {
        if let urlString = url, let imageURL = URL(string: urlString) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    mintChipIconPlaceholder
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(Circle())
        } else {
            mintChipIconPlaceholder
        }
    }

    private var mintChipIconPlaceholder: some View {
        Image(systemName: "bitcoinsign.bank.building.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
    }

    // MARK: - Action Buttons (Receive + Send)

    /// Scan moved to the toolbar; the action row is a two-button pair.
    /// Interactive glass lives inside `FullWidthCapsuleButtonStyle` (driven by
    /// `configuration.isPressed`), so a single gesture owns each button — no
    /// press-warp vs. tap-action conflict, hence no dropped first taps.
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button { activeSheet = .chooser(.receive) } label: {
                Text("Receive")
            }
            .glassButton()
            .accessibilityHint("Opens options to receive ecash or lightning payments")

            Button { activeSheet = .chooser(.send) } label: {
                Text("Send")
            }
            .glassButton()
            .accessibilityHint("Opens options to send ecash or pay lightning invoices")
        }
    }

    // MARK: - Recent Activity

    @ViewBuilder
    private var recentSection: some View {
        let items = recentItems
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Recent")

            if items.isEmpty {
                emptyRecentRow
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(for: item)

                    if index < items.count - 1 {
                        CanvasDivider()
                    }
                }

                Button(action: onViewAllHistory) {
                    HStack(spacing: 4) {
                        Text("View all activity")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Switches to the History tab")
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 16)
            .padding(.bottom, 14)
    }

    private var emptyRecentRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("No activity yet")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    // MARK: - Recent items pipeline (mirrors HistoryView, capped at 5)

    private enum HomeItem: Identifiable {
        case transaction(WalletTransaction)
        case request(CashuRequest)

        var id: String {
            switch self {
            case .transaction(let t): return "tx-\(t.id)"
            case .request(let r):     return "req-\(r.id)"
            }
        }

        var date: Date {
            switch self {
            case .transaction(let t): return t.date
            case .request(let r):     return r.createdAt
            }
        }
    }

    /// Suppress transactions that are already represented by a Cashu Request
    /// row, then merge requests + transactions, sort desc, cap.
    private var recentItems: [HomeItem] {
        let claimedTxIds = Set(requestStore.requests.flatMap { $0.receivedPayments.map(\.transactionId) })
        let txItems: [HomeItem] = walletManager.transactions
            .filter { !claimedTxIds.contains($0.id) }
            .map(HomeItem.transaction)
        let reqItems: [HomeItem] = requestStore.requests.map(HomeItem.request)
        return (txItems + reqItems)
            .sorted { $0.date > $1.date }
            .prefix(recentRowCap)
            .map { $0 }
    }

    @ViewBuilder
    private func row(for item: HomeItem) -> some View {
        switch item {
        case .transaction(let tx):
            transactionRow(transaction: tx)
        case .request(let req):
            cashuRequestRow(request: req)
        }
    }

    // MARK: - Transaction row (slimmer than HistoryView's variant)

    private func transactionRow(transaction: WalletTransaction) -> some View {
        Button {
            HapticFeedback.selection()
            selectedTransaction = transaction
        } label: {
            HStack(spacing: 14) {
                rowIcon(for: transaction)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(rowTitle(for: transaction))
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Text(formatRelativeDate(transaction.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                TransactionAmountColumn(
                    transaction: transaction,
                    isCheckingStatus: isCheckingStatus,
                    onRefresh: { Task { await refreshPendingTransaction(transaction) } }
                )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rowTitle(for: transaction)), \(formatAmount(transaction)) sats, \(transaction.status == .pending ? "pending" : "completed"), \(formatRelativeDate(transaction.date))")
        .accessibilityHint("Opens transaction details")
    }

    @ViewBuilder
    private func rowIcon(for transaction: WalletTransaction) -> some View {
        kindIcon(transaction.kind)
            .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private func kindIcon(_ kind: WalletTransaction.TransactionKind) -> some View {
        switch kind {
        case .ecash:
            EcashIcon()
        case .lightning:
            LightningIcon()
        case .onchain:
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
        }
    }

    private func rowTitle(for transaction: WalletTransaction) -> String {
        switch (transaction.kind, transaction.type) {
        case (.ecash,     .incoming): return "Received ecash"
        case (.ecash,     .outgoing): return "Sent ecash"
        case (.lightning, .incoming): return "Lightning received"
        case (.lightning, .outgoing): return "Lightning paid"
        case (.onchain,   .incoming): return "Bitcoin received"
        case (.onchain,   .outgoing): return "Bitcoin sent"
        }
    }

    private func formatAmount(_ transaction: WalletTransaction) -> String {
        let prefix = transaction.type == .incoming ? "+" : "−"
        return "\(prefix)\(settings.formatAmountShort(transaction.amount))"
    }

    // MARK: - Cashu Request row

    private func cashuRequestRow(request: CashuRequest) -> some View {
        let isReceived = !request.receivedPayments.isEmpty
        return Button {
            HapticFeedback.selection()
            selectedRequest = request
        } label: {
            HStack(spacing: 14) {
                EcashIcon()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cashu Request")
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Text(formatRelativeDate(request.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                CashuRequestAmountColumn(
                    request: request,
                    received: isReceived,
                    receivedAmount: totalReceived(for: request)
                )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cashu Request, \(isReceived ? "received" : "waiting for payment"), \(formatRelativeDate(request.createdAt))")
        .accessibilityHint("Opens request details")
    }

    private func totalReceived(for request: CashuRequest) -> UInt64 {
        let ids = Set(request.receivedPayments.map(\.transactionId))
        guard !ids.isEmpty else { return 0 }
        return walletManager.transactions
            .filter { ids.contains($0.id) }
            .reduce(UInt64(0)) { $0 + $1.amount }
    }

    // MARK: - Relative date

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let sameYearDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    private static let otherYearDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return f
    }()

    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "Now" }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            if delta < 3600 {
                let minutes = max(1, Int(delta / 60))
                return "\(minutes) min ago"
            }
            return Self.shortTimeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(Self.shortTimeFormatter.string(from: date))"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return (sameYear ? Self.sameYearDateFormatter : Self.otherYearDateFormatter).string(from: date)
    }

    // MARK: - Refresh pending transactions
    // Mirror of HistoryView so behavior matches across surfaces.

    private func refreshPendingTransaction(_ transaction: WalletTransaction) async {
        switch transaction.kind {
        case .ecash:
            await checkTransactionStatus(transaction)
        case .lightning, .onchain:
            isCheckingStatus = transaction.id
            defer { isCheckingStatus = nil }
            await walletManager.refreshPendingMintQuote(quoteId: transaction.id)
        }
    }

    private func checkTransactionStatus(_ transaction: WalletTransaction) async {
        guard let token = transaction.token else { return }
        isCheckingStatus = transaction.id
        defer { isCheckingStatus = nil }

        let isSpent = await walletManager.checkTokenSpendable(token: token, mintUrl: transaction.mintUrl)
        if isSpent {
            walletManager.removePendingToken(tokenId: transaction.id)
            await walletManager.loadTransactions()
        }
    }

    // MARK: - Helpers

    private func formatBalanceWithUnit(_ sats: UInt64) -> String {
        let formatted = settings.formatAmountBalance(sats)
        return settings.useBitcoinSymbol ? "₿\(formatted)" : "\(formatted) sat"
    }

    @ViewBuilder
    private func sheetView(for sheet: WalletSheet) -> some View {
        switch sheet {
        case .chooser(let action):
            WalletActionSheetView(
                action: action,
                onClose: { activeSheet = nil },
                onScan: { activeSheet = .scanner },
                onSelect: { flow in
                    if case .contactlessPay = flow {
                        activeSheet = nil
                        contactlessCoordinator.start(
                            walletManager: walletManager,
                            navigationManager: navigationManager
                        )
                    } else {
                        activeSheet = .flow(flow)
                    }
                }
            )
            .presentationDragIndicator(.visible)
            .modifier(ChooserSheetPresentation(height: action.detentHeight))
        case .scanner:
            ScannerWrapperView()
                .environmentObject(walletManager)
                .presentationDetents([.large])
        case .flow(let flow):
            flowView(for: flow)
        case .discoverMints:
            MintDiscoverySheet { url in
                Task { try? await walletManager.addMint(url: url) }
            }
            .environmentObject(walletManager)
        }
    }

    @ViewBuilder
    private func flowView(for flow: WalletFlow) -> some View {
        switch flow {
        case .receiveEcash:
            ReceiveEcashView(sheetDetent: $receiveEcashDetent)
                .environmentObject(walletManager)
                .presentationDetents([.medium, .large], selection: $receiveEcashDetent)
                .onAppear { receiveEcashDetent = .medium }
        case .receiveLightning:
            ReceiveLightningView()
                .environmentObject(walletManager)
                .presentationDetents([.large])
        case .sendEcash:
            SendView()
                .environmentObject(walletManager)
                .presentationDetents([.large])
        case .sendLightning:
            MeltView()
                .environmentObject(walletManager)
                .presentationDetents([.large])
        case .sendLightningWithInvoice(let invoice):
            MeltViewWithInvoice(invoice: invoice)
                .environmentObject(walletManager)
                .presentationDetents([.large])
        case .contactlessPay:
            EmptyView()
        }
    }
}

private enum WalletActionSheet: String, Identifiable {
    case receive
    case send

    var id: String { rawValue }

    var title: String {
        switch self {
        case .receive: return "Receive"
        case .send: return "Send"
        }
    }

    var primaryOption: WalletFlow {
        switch self {
        case .receive: return .receiveEcash
        case .send: return .sendEcash
        }
    }

    var secondaryOption: WalletFlow {
        switch self {
        case .receive: return .receiveLightning
        case .send: return .sendLightning
        }
    }

    var detentHeight: CGFloat {
        if self == .send, NFCNDEFReaderSession.readingAvailable {
            return 245
        }
        return 195
    }
}

private enum WalletFlow: Identifiable {
    case receiveEcash
    case receiveLightning
    case sendEcash
    case sendLightning
    case sendLightningWithInvoice(String)
    case contactlessPay

    var id: String {
        switch self {
        case .receiveEcash:
            return "receiveEcash"
        case .receiveLightning:
            return "receiveLightning"
        case .sendEcash:
            return "sendEcash"
        case .sendLightning:
            return "sendLightning"
        case .sendLightningWithInvoice(let invoice):
            return "sendLightningWithInvoice-\(invoice.prefix(64))"
        case .contactlessPay:
            return "contactlessPay"
        }
    }
}

private enum WalletSheet: Identifiable {
    case chooser(WalletActionSheet)
    case scanner
    case flow(WalletFlow)
    case discoverMints

    var id: String {
        switch self {
        case .chooser(let action):
            return "chooser-\(action.id)"
        case .scanner:
            return "scanner"
        case .flow(let flow):
            return "flow-\(flow.id)"
        case .discoverMints:
            return "discoverMints"
        }
    }
}

private struct WalletActionSheetView: View {
    let action: WalletActionSheet
    let onClose: () -> Void
    let onScan: () -> Void
    let onSelect: (WalletFlow) -> Void

    @State private var revealed = false

    private var secondaryOptionTitle: String {
        // Lightning + on-chain are both "Bitcoin" from the user's mental model;
        // the protocol choice happens inside the flow itself.
        "Bitcoin"
    }

    private struct Option: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let flow: WalletFlow
    }

    private var options: [Option] {
        var result: [Option] = [
            .init(title: "Ecash", icon: "banknote", flow: action.primaryOption),
            .init(title: secondaryOptionTitle, icon: "bitcoinsign.circle.fill", flow: action.secondaryOption),
        ]
        if action == .send, NFCNDEFReaderSession.readingAvailable {
            result.append(.init(title: "Contactless", icon: "wave.3.right.circle.fill", flow: .contactlessPay))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    optionButton(title: option.title, icon: option.icon, action: option.flow)
                        .opacity(revealed ? 1 : 0)
                        .offset(x: revealed ? 0 : -12)
                        .animation(
                            .smooth(duration: 0.32).delay(Double(index) * 0.07),
                            value: revealed
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onScan) {
                        Image(systemName: "viewfinder")
                    }
                    .accessibilityLabel("Scan")
                }
            }
        }
        .onAppear { revealed = true }
    }

    private func optionButton(title: String, icon: String, action flow: WalletFlow) -> some View {
        Button {
            HapticFeedback.selection()
            onSelect(flow)
        } label: {
            optionLabel(title: title, icon: icon)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func optionLabel(title: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.title3.weight(.medium))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
    }
}

private struct TopInsetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChooserSheetPresentation: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content.presentationDetents([.height(height)])
    }
}

#Preview {
    MainWalletView()
        .environmentObject(WalletManager())
        .environmentObject(NavigationManager())
}
