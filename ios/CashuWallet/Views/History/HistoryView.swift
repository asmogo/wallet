import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared
    @ObservedObject private var requestStore = CashuRequestStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum FilterMode: String, CaseIterable, Identifiable {
        case all
        case pending
        case completed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:       return "All transactions"
            case .pending:   return "Pending only"
            case .completed: return "Completed only"
            }
        }
    }

    @State private var filter: FilterMode = .all
    @State private var searchText: String = ""
    /// System search is mounted only while active so the inactive drawer never
    /// sits under the large title. Mount with `isSearchPresented == true` so
    /// search takes over the top chrome; unmount as soon as it dismisses so
    /// we never flash the idle under-title bar (that flicker).
    @State private var isSearchMounted = false
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @State private var selectedTransaction: WalletTransaction?
    @State private var selectedRequest: CashuRequest?
    @State private var isSheetDismissing = false
    @State private var requestPendingDeletion: CashuRequest?
    @State private var receiveTokenPendingDeletion: WalletTransaction?
    /// Unclaimed incoming token being claimed (rows open the claim flow
    /// directly — one Receive tap, no intermediate detail sheet).
    @State private var claimReceiveToken: PendingReceiveToken?
    @State private var transactionUpdateRevision = 0
    @State private var didInitialLoad = false

    // Unified timeline item — Cashu Requests and transactions share a sort key
    // and live in the same date-grouped sections.
    private enum HistoryItem: Identifiable {
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

    @State private var visibleCount: Int = 30
    @State private var scrollResetToken: UInt = 0
    private let pageStep: Int = 30
    private let prefetchLead: Int = 5

    private let rowHorizontalPadding: CGFloat = 4
    // Match MainWalletView's recent-list row metrics so spacing reads the
    // same from Home → History (16pt vertical padding, 4pt title/time gap).
    private let rowVerticalPadding: CGFloat = 16

    private var isBottomSheetPresented: Bool {
        selectedTransaction != nil || selectedRequest != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty {
                    // Don't show the empty state until the first load finishes:
                    // rendering it during the (fast, local) initial load made it
                    // swoop in for a beat before a populated list arrived. The
                    // pre-load branch must be a placeholder view, not nothing —
                    // an empty Group detaches every modifier below, including
                    // the .task that performs the initial load, deadlocking a
                    // fresh wallet on a blank screen.
                    if didInitialLoad {
                        emptyStateView
                    } else {
                        Color.clear
                    }
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .toolbar {
                // Search left of Filter — same trailing action order as Android.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        toggleSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel(isSearchPresented ? "Hide search" : "Search history")

                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(FilterMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease"
                              : "line.3.horizontal.decrease.circle.fill")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel("Filter transactions")
                    .accessibilityValue(filter.label)
                }
            }
            // Mount `.searchable` only while searching (see `isSearchMounted`).
            .modifier(HistorySearchMount(
                isMounted: isSearchMounted,
                text: $searchText,
                isPresented: $isSearchPresented,
                isFocused: $isSearchFocused
            ))
            .onChange(of: filter) { _, _ in
                visibleCount = pageStep
                scrollResetToken &+= 1
                HapticFeedback.selection()
            }
            .onChange(of: searchText) { _, _ in
                visibleCount = pageStep
            }
            .onChange(of: isSearchPresented) { _, presented in
                if presented {
                    isSearchFocused = true
                } else {
                    searchText = ""
                    visibleCount = pageStep
                    // Unmount immediately so we never land on the inactive
                    // drawer-under-title state (that flash is what made the
                    // large title flicker on dismiss).
                    isSearchMounted = false
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
                    .environmentObject(walletManager)
                    .observeBottomSheetDismissal { isSheetDismissing = $0 }
            }
            // Claim flow for an unclaimed incoming token. `item:` captures the
            // pending token at presentation, so the content stays stable while
            // the claim removes it from the store (a live lookup here would go
            // nil mid-flow and blank the screen).
            .fullScreenCover(item: $claimReceiveToken) { pending in
                ReceiveTokenDetailView(
                    tokenString: pending.token,
                    onComplete: { claimReceiveToken = nil },
                    claim: { try await walletManager.claimPendingReceiveToken(pending) }
                )
                .environmentObject(walletManager)
            }
            .sheet(item: $selectedRequest) { request in
                NavigationStack {
                    CashuRequestDetailView(request: request)
                        .environmentObject(walletManager)
                }
                .compactBottomSheetSurface()
                .observeBottomSheetDismissal { isSheetDismissing = $0 }
            }
            .confirmationDialog(
                "Remove this Cashu Request from history?",
                isPresented: Binding(
                    get: { requestPendingDeletion != nil },
                    set: { if !$0 { requestPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: requestPendingDeletion
            ) { request in
                Button("Remove", role: .destructive) {
                    requestStore.delete(id: request.id)
                    requestPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    requestPendingDeletion = nil
                }
            } message: { _ in
                Text("The QR and any pending payment routing stay valid; this only removes the row from your history.")
            }
            .confirmationDialog(
                "Remove this unclaimed ecash?",
                isPresented: Binding(
                    get: { receiveTokenPendingDeletion != nil },
                    set: { if !$0 { receiveTokenPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: receiveTokenPendingDeletion
            ) { transaction in
                Button("Remove", role: .destructive) {
                    walletManager.removePendingReceiveToken(tokenId: transaction.id)
                    receiveTokenPendingDeletion = nil
                    Task { await walletManager.loadTransactions() }
                }
                Button("Cancel", role: .cancel) {
                    receiveTokenPendingDeletion = nil
                }
            } message: { _ in
                Text("This ecash hasn't been claimed. Removing it discards the token — only the sender can re-issue it.")
            }
            .task {
                // Show the current ledger immediately, then quietly re-check
                // pending mint quotes (throttled) so a paid BOLT12 offer lands
                // in history just by opening the tab — no pull-to-refresh.
                await walletManager.loadTransactions()
                didInitialLoad = true
                await walletManager.syncPendingMintQuotesIfStale()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cashuTransactionsUpdated)) { _ in
                transactionUpdateRevision += 1
                visibleCount = min(visibleCount, max(pageStep, filteredItems.count))
            }
        }
        .accessibilityIdentifier("history-screen")
        .bottomSheetBackdrop(
            isPresented: isBottomSheetPresented && !isSheetDismissing
        )
        .onChange(of: isBottomSheetPresented) { _, presented in
            if presented { isSheetDismissing = false }
        }
    }

    // MARK: - History List

    private func toggleSearch() {
        if isSearchPresented || isSearchMounted {
            isSearchFocused = false
            isSearchPresented = false
        } else {
            // Present before mount so searchable appears already active —
            // search takes over the top; no inactive bar under the title.
            isSearchPresented = true
            isSearchMounted = true
        }
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            // A `List` (not a hand-built ScrollView) is what `.searchable` and
            // `.refreshable` are designed to coordinate with — it owns the
            // UISearchController/refresh-control plumbing so pull-to-refresh
            // stays stable while search is presented. Section headers stay as
            // plain rows (not `Section` headers) to keep them non-pinned, and
            // native separators are hidden so activity rows flow on the canvas.
            List {
                ForEach(sectionsWithOffsets, id: \.group.title) { entry in
                    sectionHeader(entry.group.title)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    ForEach(Array(entry.group.items.enumerated()), id: \.element.id) { index, item in
                        let globalIndex = entry.startIndex + index
                        VStack(spacing: 0) {
                            row(for: item)
                        }
                        .id(item.id)
                        .onAppear {
                            if globalIndex >= visibleCount - prefetchLead {
                                extendWindow()
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .refreshable {
                await walletManager.syncPendingMintQuotes(force: true)
                await walletManager.syncPendingMeltQuotes()
                await walletManager.checkAllPendingTokens()
            }
            .onChange(of: scrollResetToken) { _, _ in
                if let firstId = visibleItems.first?.id {
                    if reduceMotion {
                        proxy.scrollTo(firstId, anchor: .top)
                    } else {
                        withAnimation(.snappy(duration: 0.25)) {
                            proxy.scrollTo(firstId, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func extendWindow() {
        guard visibleCount < filteredItems.count else { return }
        visibleCount = min(visibleCount + pageStep, filteredItems.count)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .cashuText(.overline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func row(for item: HistoryItem) -> some View {
        switch item {
        case .transaction(let tx):
            transactionRow(transaction: tx)
        case .request(let req):
            cashuRequestRow(request: req)
        }
    }

    private struct SectionWithOffset {
        let group: HistoryGroup
        let startIndex: Int
    }

    /// groupedSections paired with a running row offset, so each row can be
    /// assigned a continuous "global index" for the entrance stagger.
    private var sectionsWithOffsets: [SectionWithOffset] {
        var result: [SectionWithOffset] = []
        var offset = 0
        for g in groupedSections {
            result.append(.init(group: g, startIndex: offset))
            offset += g.items.count
        }
        return result
    }

    // MARK: - Grouping

    private struct HistoryGroup {
        let title: String
        let items: [HistoryItem]
    }

    private var groupedSections: [HistoryGroup] {
        let items = visibleItems
        guard !items.isEmpty else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfYesterday
        let startOfThisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? startOfThisWeek

        var today: [HistoryItem] = []
        var yesterday: [HistoryItem] = []
        var thisWeek: [HistoryItem] = []
        var thisMonth: [HistoryItem] = []
        var earlier: [HistoryItem] = []

        for item in items {
            let d = item.date
            if d >= startOfToday {
                today.append(item)
            } else if d >= startOfYesterday {
                yesterday.append(item)
            } else if d >= startOfThisWeek {
                thisWeek.append(item)
            } else if d >= startOfThisMonth {
                thisMonth.append(item)
            } else {
                earlier.append(item)
            }
        }

        var groups: [HistoryGroup] = []
        if !today.isEmpty     { groups.append(.init(title: "Today",      items: today)) }
        if !yesterday.isEmpty { groups.append(.init(title: "Yesterday",  items: yesterday)) }
        if !thisWeek.isEmpty  { groups.append(.init(title: "This Week",  items: thisWeek)) }
        if !thisMonth.isEmpty { groups.append(.init(title: "This Month", items: thisMonth)) }
        if !earlier.isEmpty   { groups.append(.init(title: "Earlier",    items: earlier)) }
        return groups
    }

    // MARK: - Computed Properties

    /// Set of CDK transaction ids that are claimed by some Cashu Request.
    /// These are suppressed from the timeline because the request row
    /// represents the same money event.
    private var requestClaimedTxIds: Set<String> {
        Set(requestStore.requests.flatMap { $0.receivedPayments.map(\.transactionId) })
    }

    /// Sum of wallet-transaction amounts attached to this request.
    private func totalReceived(for request: CashuRequest) -> UInt64 {
        let ids = Set(request.receivedPayments.map(\.transactionId))
        guard !ids.isEmpty else { return 0 }
        return walletManager.transactions
            .filter { ids.contains($0.id) }
            .reduce(UInt64(0)) { $0 + $1.amount }
    }

    /// Surviving transactions (not claimed by any Cashu Request) merged with
    /// every Cashu Request, then filtered by toolbar mode and search text.
    private var filteredItems: [HistoryItem] {
        let claimed = requestClaimedTxIds
        let txItems: [HistoryItem] = walletManager.transactions
            .filter { !claimed.contains($0.id) }
            .filter { matchesFilter(transaction: $0) }
            .map(HistoryItem.transaction)

        let reqItems: [HistoryItem] = requestStore.requests
            .filter { matchesFilter(request: $0) }
            .map(HistoryItem.request)

        let combined = (txItems + reqItems).sorted { $0.date > $1.date }
        return combined.filter { matchesSearch($0) }
    }

    private func matchesFilter(transaction: WalletTransaction) -> Bool {
        switch filter {
        case .all:       return true
        case .pending:   return transaction.status == .pending
        case .completed: return transaction.status == .completed
        }
    }

    private func matchesFilter(request: CashuRequest) -> Bool {
        switch filter {
        case .all:       return true
        case .pending:   return request.receivedPayments.isEmpty
        case .completed: return !request.receivedPayments.isEmpty
        }
    }

    private func matchesSearch(_ item: HistoryItem) -> Bool {
        switch item {
        case .transaction(let tx):
            return HistorySearch.matches(query: searchText, transaction: tx)
        case .request(let req):
            return HistorySearch.matches(
                query: searchText,
                request: req,
                receivedTotal: totalReceived(for: req)
            )
        }
    }

    private var visibleItems: [HistoryItem] {
        Array(filteredItems.prefix(visibleCount))
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        if !searchText.isEmpty {
            NativeEmptyState(
                title: "No Results",
                systemImage: "magnifyingglass",
                description: "No activity matches \"\(searchText)\"."
            )
        } else if filter != .all {
            NativeEmptyState(
                title: "Nothing Here",
                systemImage: "line.3.horizontal.decrease.circle",
                description: "No transactions match this filter."
            )
        } else {
            // Shares the Wallet empty state's size + centered placement (one
            // component), but keeps its own clock icon and history-specific
            // copy so the two screens read as deliberate siblings, not
            // accidental duplicates.
            NativeEmptyState(
                title: "No Activity Yet",
                systemImage: "clock.arrow.circlepath",
                description: "Your first payment will show up here."
            )
        }
    }

    // MARK: - Cashu Request Row

    private func cashuRequestRow(request: CashuRequest) -> some View {
        let isReceived = !request.receivedPayments.isEmpty
        let receivedAmount = totalReceived(for: request)
        return Button {
            HapticFeedback.selection()
            isSearchFocused = false
            selectedRequest = request
        } label: {
            HStack(spacing: 14) {
                TransactionIcon(direction: .incoming)

                VStack(alignment: .leading, spacing: 4) {
                    Text(request.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Text(formatRelativeDate(request.createdAt))
                        .cashuText(.metadata)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                CashuRequestAmountColumn(
                    request: request,
                    received: isReceived,
                    receivedAmount: receivedAmount
                )
            }
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            cashuRequestAccessibilityLabel(
                request: request,
                received: isReceived,
                receivedAmount: receivedAmount
            )
        )
        .accessibilityHint("Opens request details")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                requestPendingDeletion = request
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func cashuRequestAccessibilityLabel(
        request: CashuRequest,
        received: Bool,
        receivedAmount: UInt64
    ) -> String {
        let amount = received ? receivedAmount : (request.amount ?? 0)
        let amountPart: String
        if amount == 0 {
            amountPart = "any amount"
        } else {
            let display = AmountFormatter.displayMintUnitAmount(
                amount: amount,
                unit: request.unit,
                preferredPrimary: settings.homeBalancePrimary,
                showFiat: settings.showFiatBalance,
                btcPrice: priceService.btcPriceUSD,
                currencyCode: settings.bitcoinPriceCurrency,
                useBitcoinSymbol: settings.useBitcoinSymbol
            )
            amountPart = [display.primary, display.secondary]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
        return "\(request.displayTitle), \(amountPart), \(received ? "received" : "waiting for payment"), \(formatRelativeDate(request.createdAt))"
    }

    // MARK: - Transaction Row

    private func transactionRow(transaction: WalletTransaction) -> some View {
        return Button {
            HapticFeedback.selection()
            isSearchFocused = false
            // Unclaimed incoming ecash goes straight to the claim flow — the
            // receive screen already shows amount, fee, mint, and memo, so an
            // intermediate detail sheet would just add a second Receive tap.
            if transaction.isPendingReceiveToken,
               let pending = walletManager.pendingReceiveTokens.first(where: { $0.tokenId == transaction.id }) {
                claimReceiveToken = pending
            } else {
                selectedTransaction = transaction
            }
        } label: {
            HStack(spacing: 14) {
                rowIcon(for: transaction)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(rowTitle(for: transaction))
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Text(formatRelativeDate(transaction.date))
                        .cashuText(.metadata)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                TransactionAmountColumn(transaction: transaction)
            }
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rowTitle(for: transaction)), \(formatAmount(transaction)), \(transaction.status == .completed ? "completed" : transaction.displayStatusText.lowercased()), \(formatRelativeDate(transaction.date))")
        .accessibilityHint(
            transaction.isPendingReceiveToken
                ? "Opens receive review"
                : "Opens transaction details"
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if transaction.isPendingReceiveToken {
                Button(role: .destructive) {
                    receiveTokenPendingDeletion = transaction
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Row content

    @ViewBuilder
    private func rowIcon(for transaction: WalletTransaction) -> some View {
        TransactionIcon(direction: transaction.type)
    }

    private func rowTitle(for transaction: WalletTransaction) -> String {
        transaction.displayTitle
    }

    // MARK: - Formatting

    // Mirrors TransactionAmountColumn: the sign is a settled-ledger signal, so a
    // pending row reads as a bare amount in VoiceOver too (status is announced
    // separately).
    private func formatAmount(_ transaction: WalletTransaction) -> String {
        let value = AmountFormatter.displayMintUnitAmount(
            amount: transaction.amount,
            unit: transaction.unit,
            preferredPrimary: settings.homeBalancePrimary,
            showFiat: settings.showFiatBalance,
            btcPrice: priceService.btcPriceUSD,
            currencyCode: settings.bitcoinPriceCurrency,
            useBitcoinSymbol: settings.useBitcoinSymbol
        ).primary
        guard !transaction.isUnsettled else { return value }
        return transaction.type == .incoming ? "+\(value)" : value
    }

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

    /// Smart relative date: <1 min → "Now", <1 h → "X min ago",
    /// same day → time, yesterday → "Yesterday HH:MM", older → "MMM d" (or +year).
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

}

/// History search matching, extracted from HistoryView so it is unit-testable.
/// Title and memo match case-insensitively; amounts match as substrings of the
/// raw value (Android `unifiedFiltered` parity — memos included for both
/// transactions and Cashu Requests).
enum HistorySearch {
    static func matches(query: String, transaction: WalletTransaction) -> Bool {
        let query = normalized(query)
        guard !query.isEmpty else { return true }
        if transaction.displayTitle.lowercased().contains(query) { return true }
        if "\(transaction.amount)".contains(query) { return true }
        if let memo = transaction.displayDescription, memo.lowercased().contains(query) { return true }
        return false
    }

    static func matches(query: String, request: CashuRequest, receivedTotal: UInt64) -> Bool {
        let query = normalized(query)
        guard !query.isEmpty else { return true }
        if request.displayTitle.lowercased().contains(query) { return true }
        if let amount = request.amount, "\(amount)".contains(query) { return true }
        if receivedTotal > 0, "\(receivedTotal)".contains(query) { return true }
        if let memo = request.displayDescription, memo.lowercased().contains(query) { return true }
        return false
    }

    private static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Mounts system `.searchable` only while History search is active. Keeping it
/// permanently attached parks an inactive drawer under the large title; mounting
/// with `isPresented == true` already set lets search take over the top chrome
/// without that idle bar.
private struct HistorySearchMount: ViewModifier {
    let isMounted: Bool
    @Binding var text: String
    @Binding var isPresented: Bool
    var isFocused: FocusState<Bool>.Binding

    @ViewBuilder
    func body(content: Content) -> some View {
        if isMounted {
            content
                .searchable(text: $text, isPresented: $isPresented, prompt: "Search history")
                .searchFocused(isFocused)
        } else {
            content
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(WalletManager())
}
