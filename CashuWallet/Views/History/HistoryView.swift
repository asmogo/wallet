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

    var body: some View {
        NavigationStack {
            Group {
                if filteredTransactions.isEmpty && requestStore.requests.isEmpty {
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
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                if !requestStore.requests.isEmpty {
                    sectionHeader("Cashu Requests")
                    VStack(spacing: 0) {
                        ForEach(Array(requestStore.requests.enumerated()), id: \.element.id) { index, request in
                            cashuRequestRow(request: request)
                            if index < requestStore.requests.count - 1 {
                                CanvasDivider()
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                }

                ForEach(sectionsWithOffsets, id: \.group.title) { entry in
                    Section {
                        ForEach(Array(entry.group.items.enumerated()), id: \.element.id) { index, item in
                            let globalIndex = entry.startIndex + index
                            row(for: item, staggerIndex: globalIndex)
                                .id(item.id)
                                .onAppear {
                                    if globalIndex >= visibleCount - prefetchLead {
                                        extendWindow()
                                    }
                                }
                        }
                    } header: {
                        Text(entry.group.title)
                    }
                }
            }
            .listStyle(.plain)
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
        Set(requestStore.requests.flatMap { req in
            req.receivedPayments.map { $0.transactionId }
        })
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
            if req.totalReceived > 0, "\(req.totalReceived)".contains(query) { return true }
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
            ContentUnavailableView.search(text: searchText)
        } else if filter != .all {
            ContentUnavailableView(
                "Nothing here",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("No transactions match this filter.")
            )
        } else {
            ContentUnavailableView {
                Label("No activity yet", systemImage: "bolt.fill")
                    .symbolEffect(.pulse, options: .repeating)
            } description: {
                Text("Your first payment will show up here.")
            }
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

                requestTrailingAmount(request: request, received: isReceived)
            }
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
        ZStack(alignment: .bottomTrailing) {
            EcashIcon()
                .frame(width: 36, height: 36)

            Image(systemName: received ? "arrow.down.circle.fill" : "clock.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(received ? Color.green : Color.orange)
                .background(Color(.systemBackground), in: Circle())
                .offset(x: 4, y: 4)
                .contentTransition(.symbolEffect(.replace.downUp))
                .animation(.snappy(duration: 0.28), value: received)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func requestTrailingAmount(request: CashuRequest, received: Bool) -> some View {
        if received {
            Text("+\(settings.formatAmountShort(request.totalReceived))")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.green)
                .contentTransition(.numericText(value: Double(request.totalReceived)))
        } else if let amount = request.amount, amount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2.weight(.semibold))
                Text(settings.formatAmountShort(amount))
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
        }
        // Any-amount + waiting: no trailing element.
    }

    // MARK: - Cashu Request Row

    private func cashuRequestRow(request: CashuRequest) -> some View {
        NavigationLink {
            CashuRequestDetailView(request: request)
                .environmentObject(walletManager)
                .navigationBarBackButtonHidden(false)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color.secondary.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cashu Request")
                        .font(.subheadline.weight(.medium))
                    Text(requestSubtitle(request))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(request.createdAt.formatted(.relative(presentation: .numeric)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cashu Request, \(requestSubtitle(request))")
    }

    private func requestSubtitle(_ request: CashuRequest) -> String {
        let count = request.receivedPaymentIds.count
        if count == 0 { return "Waiting for payment" }
        if count == 1 { return "1 payment received" }
        return "\(count) payments received"
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

                Text(formatAmount(transaction))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(amountColor(transaction))
                    .contentTransition(.numericText(value: Double(transaction.amount)))

                if transaction.status == .pending {
                    Button {
                        Task { await refreshPendingTransaction(transaction) }
                    } label: {
                        if isCheckingStatus == transaction.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isCheckingStatus == transaction.id ? "Checking status" : "Refresh status")
                    .accessibilityHint(refreshHint(for: transaction))
                }
            }
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

    /// Icon stack: leading kind icon with a small direction-overlay bubble in
    /// the bottom-trailing corner. Family-style.
    @ViewBuilder
    private func rowIcon(for transaction: WalletTransaction) -> some View {
        ZStack(alignment: .bottomTrailing) {
            kindIcon(transaction.kind)
                .frame(width: 36, height: 36)

            Image(systemName: badgeSymbol(for: transaction))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(badgeColor(for: transaction))
                .background(Color(.systemBackground), in: Circle())
                .offset(x: 4, y: 4)
                .contentTransition(.symbolEffect(.replace.downUp))
                .animation(.snappy(duration: 0.28), value: transaction.status)
                .animation(.snappy(duration: 0.28), value: transaction.type)
                .accessibilityHidden(true)
        }
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

    private func amountColor(_ transaction: WalletTransaction) -> Color {
        if transaction.status == .pending { return .secondary }
        if transaction.status == .completed { return .green }
        return .primary
    }

    private func badgeSymbol(for transaction: WalletTransaction) -> String {
        if transaction.status == .pending { return "clock.circle.fill" }
        return transaction.type == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }

    private func badgeColor(for transaction: WalletTransaction) -> Color {
        if transaction.status == .pending { return .orange }
        return transaction.type == .incoming ? .green : .primary
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
            walletManager.removePendingToken(tokenId: transaction.id)
            await walletManager.loadTransactions()
        }
    }

    private func refreshHint(for transaction: WalletTransaction) -> String {
        switch transaction.kind {
        case .ecash:                return "Checks if this pending token has been claimed"
        case .lightning, .onchain:  return "Refreshes this pending receive request"
        }
    }

}

#Preview {
    HistoryView()
        .environmentObject(WalletManager())
}
