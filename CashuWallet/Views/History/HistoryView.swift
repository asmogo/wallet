import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var requestStore = CashuRequestStore.shared

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
    @State private var selectedTransaction: WalletTransaction?
    @State private var selectedRequest: CashuRequest?
    @State private var requestPendingDeletion: CashuRequest?
    @State private var isCheckingStatus: String? = nil
    @State private var transactionUpdateRevision = 0
    @State private var hasAppearedOnce = false

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

    // Cap stagger so a full page enters in ~300ms regardless of row count.
    private let maxStaggerIndex = 8
    private let staggerDelay: Double = 0.035
    private let rowHorizontalPadding: CGFloat = 4
    private let rowVerticalPadding: CGFloat = 10

    var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search history")
            .onChange(of: filter) { _, _ in
                visibleCount = pageStep
                scrollResetToken &+= 1
                HapticFeedback.selection()
            }
            .onChange(of: searchText) { _, _ in
                visibleCount = pageStep
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
                    .environmentObject(walletManager)
            }
            .navigationDestination(item: $selectedRequest) { request in
                CashuRequestDetailView(request: request)
                    .environmentObject(walletManager)
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
            .task {
                await walletManager.loadTransactions()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cashuTransactionsUpdated)) { _ in
                transactionUpdateRevision += 1
                visibleCount = min(visibleCount, max(pageStep, filteredItems.count))
            }
        }
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(sectionsWithOffsets, id: \.group.title) { entry in
                        sectionHeader(entry.group.title)

                        ForEach(Array(entry.group.items.enumerated()), id: \.element.id) { index, item in
                            let globalIndex = entry.startIndex + index
                            row(for: item, staggerIndex: globalIndex)
                                .id(item.id)
                                .onAppear {
                                    if globalIndex >= visibleCount - prefetchLead {
                                        extendWindow()
                                    }
                                }

                            if index < entry.group.items.count - 1 {
                                CanvasDivider()
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .refreshable {
                await walletManager.syncPendingMintQuotes()
                await walletManager.checkAllPendingTokens()
            }
            .onAppear { hasAppearedOnce = true }
            .onChange(of: scrollResetToken) { _, _ in
                if let firstId = visibleItems.first?.id {
                    withAnimation(.snappy(duration: 0.25)) {
                        proxy.scrollTo(firstId, anchor: .top)
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func row(for item: HistoryItem, staggerIndex: Int) -> some View {
        switch item {
        case .transaction(let tx):
            transactionRow(transaction: tx, staggerIndex: staggerIndex)
        case .request(let req):
            cashuRequestRow(request: req, staggerIndex: staggerIndex)
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        switch item {
        case .transaction(let tx):
            if rowTitle(for: tx).lowercased().contains(query) { return true }
            if "\(tx.amount)".contains(query) { return true }
            return false
        case .request(let req):
            if "cashu request".contains(query) { return true }
            if let amount = req.amount, "\(amount)".contains(query) { return true }
            let received = totalReceived(for: req)
            if received > 0, "\(received)".contains(query) { return true }
            return false
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
                title: "Nothing here",
                systemImage: "line.3.horizontal.decrease.circle",
                description: "No transactions match this filter."
            )
        } else {
            NativeEmptyState(
                title: "No activity yet",
                systemImage: "clock.arrow.circlepath",
                description: "Your first payment will show up here."
            )
        }
    }

    // MARK: - Cashu Request Row

    private func cashuRequestRow(request: CashuRequest, staggerIndex: Int) -> some View {
        let clampedIndex = min(staggerIndex, maxStaggerIndex)
        let delay = Double(clampedIndex) * staggerDelay
        let isReceived = !request.receivedPayments.isEmpty
        return Button {
            HapticFeedback.selection()
            selectedRequest = request
        } label: {
            HStack(spacing: 14) {
                requestRowIcon(received: isReceived)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
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
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hasAppearedOnce ? 1 : 0)
        .offset(y: hasAppearedOnce ? 0 : 6)
        .animation(.smooth(duration: 0.32).delay(delay), value: hasAppearedOnce)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cashu Request, \(isReceived ? "received" : "waiting for payment"), \(formatRelativeDate(request.createdAt))")
        .accessibilityHint("Opens request details")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                requestPendingDeletion = request
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func requestRowIcon(received: Bool) -> some View {
        EcashIcon()
            .frame(width: 36, height: 36)
    }


    // MARK: - Transaction Row

    private func transactionRow(transaction: WalletTransaction, staggerIndex: Int) -> some View {
        let clampedIndex = min(staggerIndex, maxStaggerIndex)
        let delay = Double(clampedIndex) * staggerDelay
        return Button {
            HapticFeedback.selection()
            selectedTransaction = transaction
        } label: {
            HStack(spacing: 14) {
                rowIcon(for: transaction)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
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
            .padding(.horizontal, rowHorizontalPadding)
            .padding(.vertical, rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hasAppearedOnce ? 1 : 0)
        .offset(y: hasAppearedOnce ? 0 : 6)
        .animation(.smooth(duration: 0.32).delay(delay), value: hasAppearedOnce)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rowTitle(for: transaction)), \(formatAmount(transaction)) sats, \(transaction.status == .pending ? transaction.displayStatusText.lowercased() : "completed"), \(formatRelativeDate(transaction.date))")
        .accessibilityHint("Opens transaction details")
    }

    // MARK: - Row content

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

    // MARK: - Formatting

    private func formatAmount(_ transaction: WalletTransaction) -> String {
        let prefix = transaction.type == .incoming ? "+" : "−"
        return "\(prefix)\(settings.formatAmountShort(transaction.amount))"
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

    // MARK: - Actions

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
            await walletManager.markTokenAsClaimed(token: token)
        }
    }


}

#Preview {
    HistoryView()
        .environmentObject(WalletManager())
}
