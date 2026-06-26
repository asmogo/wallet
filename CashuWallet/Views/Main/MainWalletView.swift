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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeSheet: WalletSheet?
    @State private var receivedDelta: ReceivedDelta?
    @State private var deltaDismissTask: Task<Void, Never>?
    @State private var receiveEcashDetent: PresentationDetent = .medium
    @State private var contactlessCoordinator = ContactlessPaymentCoordinator()
    @State private var selectedTransaction: WalletTransaction?
    @State private var selectedRequest: CashuRequest?
    @State private var topInsetHeight: CGFloat = 0

    private let recentRowCap = 5
    private let scrollFadeBand: CGFloat = 24

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
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
            .refreshable {
                await walletManager.syncPendingMintQuotes()
                await walletManager.checkAllPendingTokens()
            }
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
            .sheet(item: $selectedRequest) { request in
                NavigationStack {
                    CashuRequestDetailView(request: request)
                        .environmentObject(walletManager)
                }
            }
            .task { await walletManager.loadTransactions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cashuTokenReceived)) { note in
            guard let amount = note.userInfo?["amount"] as? UInt64 else { return }
            let fee = note.userInfo?["fee"] as? UInt64
            showReceivedDelta(amount: amount, fee: fee)
        }
        .onDisappear { deltaDismissTask?.cancel() }
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

                // Status line under the balance: a transient green received-delta
                // beat takes over the fiat slot for 2.5s on receipt, then fiat
                // fades back. Same slot, so the swap doesn't reflow the balance.
                balanceStatusLine
            }
            .padding(.top, 18)
        }
    }

    // MARK: - Received Delta Beat

    /// The status line beneath the balance: the transient green received-delta
    /// beat while a payment just landed, otherwise the fiat sub-amount.
    @ViewBuilder
    private var balanceStatusLine: some View {
        if let delta = receivedDelta {
            receivedDeltaBeat(delta)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        } else if settings.showFiatBalance && priceService.btcPriceUSD > 0 {
            Text(priceService.formatSatsAsFiat(walletManager.balance))
                .font(.body)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    /// Green "✓ +2,500" beat. Grouped via the canonical formatter, no unit (the
    /// balance beside it carries it), no directional arrow (the down-arrow stays
    /// exclusive to row badges — One Green Rule). VoiceOver-hidden; the balance
    /// announces the new total.
    private func receivedDeltaBeat(_ delta: ReceivedDelta) -> some View {
        Label {
            Text("+\(settings.formatAmountShort(delta.amount))")
                .monospacedDigit()
        } icon: {
            receivedDeltaCheckmark(id: delta.id)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.green)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func receivedDeltaCheckmark(id: UUID) -> some View {
        let base = Image(systemName: "checkmark.circle.fill")
        if #available(iOS 17.0, *), !reduceMotion {
            base.symbolEffect(.bounce, value: id)
        } else {
            base
        }
    }

    /// Reuses the sanctioned payment-received celebration spring (Motion §6);
    /// reduce-motion collapses it to a plain opacity cross-fade.
    private var receivedDeltaAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.7)
    }

    /// Shows the beat and re-arms a 2.5s dismiss timer. Rapid receives coalesce
    /// to last-write-wins: the prior timer is cancelled and the new amount
    /// (fresh id) re-bounces the checkmark.
    private func showReceivedDelta(amount: UInt64, fee: UInt64?) {
        deltaDismissTask?.cancel()
        withAnimation(receivedDeltaAnimation) {
            receivedDelta = ReceivedDelta(amount: amount, fee: fee)
        }
        deltaDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(receivedDeltaAnimation) {
                receivedDelta = nil
            }
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
            CachedAsyncImage(url: imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                mintChipIconPlaceholder
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
    /// On iOS 26 these use Apple's native neutral Liquid Glass button style
    /// (`.buttonStyle(.glass)`), wrapped in a `GlassEffectContainer` so the two
    /// adjacent capsules sample light consistently. The native style owns its own
    /// interactive press/morph, so a single gesture drives each button. iOS 18–25
    /// falls back to the in-house `glassButton()` capsule.
    @ViewBuilder
    private var actionButtons: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    actionButton(
                        "Receive",
                        identifier: "wallet-action-receive",
                        hint: "Opens options to receive ecash or lightning payments"
                    ) { activeSheet = .chooser(.receive) }

                    actionButton(
                        "Send",
                        identifier: "wallet-action-send",
                        hint: "Opens options to send ecash or pay lightning invoices"
                    ) { activeSheet = .chooser(.send) }
                }
            }
        } else {
            HStack(spacing: 12) {
                Button { activeSheet = .chooser(.receive) } label: {
                    Text("Receive")
                }
                .glassButton()
                .accessibilityIdentifier("wallet-action-receive")
                .accessibilityHint("Opens options to receive ecash or lightning payments")

                Button { activeSheet = .chooser(.send) } label: {
                    Text("Send")
                }
                .glassButton()
                .accessibilityIdentifier("wallet-action-send")
                .accessibilityHint("Opens options to send ecash or pay lightning invoices")
            }
        }
    }

    /// A single home action button rendered with Apple's native neutral
    /// Liquid Glass style, sized to fill half the action row.
    @available(iOS 26, *)
    private func actionButton(
        _ title: String,
        identifier: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier(identifier)
        .accessibilityHint(hint)
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
        NativeEmptyState(
            title: "No activity yet",
            systemImage: "clock.arrow.circlepath",
            description: "Your activity will show up here.",
            style: .compact
        )
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

                TransactionAmountColumn(transaction: transaction)
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
        TransactionIcon(direction: transaction.type)
    }

    private func rowTitle(for transaction: WalletTransaction) -> String {
        transaction.displayTitle
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
                TransactionIcon(direction: .incoming)

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

    // MARK: - Helpers

    private func formatBalanceWithUnit(_ sats: UInt64) -> String {
        let formatted = settings.formatAmountBalance(sats)
        return settings.useBitcoinSymbol ? "₿\(formatted)" : "\(formatted) sat"
    }

    /// Detent for the action chooser. The Send chooser grows into a taller
    /// empty-state when there's nothing to send: no mints → the suggested-mints
    /// picker; mints but zero balance → the "receive first" prompt. Reactive to
    /// `mints`/`balance` so it shrinks once a mint is added (no mints → mints).
    private func chooserHeight(for action: WalletActionSheet) -> CGFloat {
        if action == .send, walletManager.balance == 0 {
            return walletManager.mints.isEmpty ? 470 : 260
        }
        return action.detentHeight
    }

    @ViewBuilder
    private func sheetView(for sheet: WalletSheet) -> some View {
        switch sheet {
        case .chooser(let action):
            WalletActionSheetView(
                action: action,
                onClose: { activeSheet = nil },
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
                },
                onReceive: { activeSheet = .chooser(.receive) },
                onAddCustomMint: { activeSheet = .discoverMints }
            )
            .environmentObject(walletManager)
            .presentationDragIndicator(.visible)
            .modifier(ChooserSheetPresentation(height: chooserHeight(for: action)))
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
    let onSelect: (WalletFlow) -> Void
    /// Open the Receive chooser (state B's CTA — the way out of an empty wallet).
    let onReceive: () -> Void
    /// Route to the custom-mint add surface (state A's "Add custom mint URL").
    let onAddCustomMint: () -> Void

    @EnvironmentObject private var walletManager: WalletManager
    @State private var revealed = false
    @State private var addingMintUrl: String?
    @State private var addMintError: String?

    /// Send is impossible with nothing to spend — intercept before the chooser.
    /// Receive is never gated (it's the cure), so this only fires for `.send`.
    private var isSendEmptyState: Bool {
        action == .send && walletManager.balance == 0
    }

    /// The single piece of state the sheet body switches on, so phase changes
    /// (e.g. connecting → "nothing to send yet") cross-fade rather than hard-cut.
    private enum SendEmptyPhase: Equatable { case options, connecting, noMints, noBalance }

    private var phase: SendEmptyPhase {
        guard isSendEmptyState else { return .options }
        if addingMintUrl != nil { return .connecting }
        return walletManager.mints.isEmpty ? .noMints : .noBalance
    }

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
            Group {
                switch phase {
                case .options:
                    optionsList.transition(.opacity)
                case .connecting:
                    connectingState.transition(.opacity)
                case .noMints:
                    noMintsState.transition(.opacity)
                case .noBalance:
                    noBalanceState.transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.35), value: phase)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Drop the "Send" title for the empty state — the headline carries it.
            .navigationTitle(isSendEmptyState ? "" : action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("wallet-chooser-close")
                }
            }
        }
        .onAppear { revealed = true }
    }

    // MARK: - Normal chooser (Ecash / Bitcoin / …)

    private var optionsList: some View {
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
    }

    // MARK: - Send empty states

    /// Transient state while a tapped suggested mint is being added. Held in its
    /// own phase so it cross-fades into state B once the mint connects.
    private var connectingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Connecting to \(displayHost(addingMintUrl ?? ""))…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// State A — no mints. Embeds the onboarding suggested-mints picker so the
    /// prerequisite is resolved in place; adding a mint auto-advances to state B.
    private var noMintsState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect a mint first")
                        .font(.title3.weight(.medium))
                    Text("Mints issue the ecash you send and receive. Add one to get started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                SuggestedMintsSection(
                    existingURLs: Set(walletManager.mints.map(\.url)),
                    onAdd: { addMint($0) }
                )

                if let addMintError {
                    Text(addMintError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                Button(action: onAddCustomMint) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add custom mint URL")
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .textLinkButton()
                .padding(.top, 4)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    /// State B — mints connected but zero balance. The way forward is funds.
    private var noBalanceState: some View {
        VStack(spacing: 16) {
            Image(systemName: "banknote")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Nothing to send yet")
                    .font(.title3.weight(.medium))
                Text("Receive some ecash before you can send.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Receive", action: onReceive)
                .glassButton()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private func addMint(_ url: String) {
        addMintError = nil
        addingMintUrl = url
        Task {
            do {
                try await walletManager.addMint(url: url)
            } catch {
                addMintError = "Couldn't connect to that mint. Try another."
            }
            addingMintUrl = nil
        }
    }

    private func displayHost(_ url: String) -> String {
        var host = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if host.hasSuffix("/") { host = String(host.dropLast()) }
        return host
    }

    private func optionButton(title: String, icon: String, action flow: WalletFlow) -> some View {
        Button {
            HapticFeedback.selection()
            onSelect(flow)
        } label: {
            optionLabel(title: title, icon: icon)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("wallet-flow-\(flow.id)")
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

/// A just-received amount, surfaced as the transient balance beat. The `id`
/// makes rapid successive receives re-trigger the entrance + checkmark bounce.
private struct ReceivedDelta: Identifiable, Equatable {
    let id = UUID()
    let amount: UInt64
    let fee: UInt64?
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
