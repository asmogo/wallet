import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared

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
    @State private var selectedTransaction: WalletTransaction?
    @State private var isCheckingStatus: String? = nil
    @State private var transactionUpdateRevision = 0
    @State private var hasAppearedOnce = false

    // Pagination — kept for now (visual polish only; structural overhaul deferred)
    @State private var currentPage: Int = 1
    private let pageSize: Int = 10

    // Cap stagger so a full page enters in ~300ms regardless of row count.
    private let maxStaggerIndex = 8
    private let staggerDelay: Double = 0.035

    var body: some View {
        NavigationStack {
            Group {
                if filteredTransactions.isEmpty {
                    emptyStateView
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
            .onChange(of: filter) { _, _ in
                currentPage = 1
                HapticFeedback.selection()
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
                    .environmentObject(walletManager)
            }
            .task {
                await walletManager.loadTransactions()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cashuTransactionsUpdated)) { _ in
                transactionUpdateRevision += 1
                currentPage = min(currentPage, maxPages)
            }
        }
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(sectionsWithOffsets, id: \.group.title) { entry in
                    sectionHeader(entry.group.title)

                    VStack(spacing: 0) {
                        ForEach(Array(entry.group.transactions.enumerated()), id: \.element.id) { index, transaction in
                            transactionRow(transaction: transaction, staggerIndex: entry.startIndex + index)
                            if index < entry.group.transactions.count - 1 {
                                CanvasDivider()
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                }

                if maxPages > 1 {
                    paginationControls
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .animation(.snappy(duration: 0.25), value: filter)
            .animation(.snappy(duration: 0.25), value: currentPage)
        }
        .refreshable {
            await walletManager.syncPendingMintQuotes()
            await walletManager.checkAllPendingTokens()
        }
        .onAppear { hasAppearedOnce = true }
    }

    private struct SectionWithOffset {
        let group: TransactionGroup
        let startIndex: Int
    }

    /// groupedSections paired with a running row offset, so each row can be
    /// assigned a continuous "global index" for the entrance stagger.
    private var sectionsWithOffsets: [SectionWithOffset] {
        var result: [SectionWithOffset] = []
        var offset = 0
        for g in groupedSections {
            result.append(.init(group: g, startIndex: offset))
            offset += g.transactions.count
        }
        return result
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

    // MARK: - Grouping

    private struct TransactionGroup {
        let title: String
        let transactions: [WalletTransaction]
    }

    private var groupedSections: [TransactionGroup] {
        let txns = paginatedTransactions
        guard !txns.isEmpty else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfYesterday
        let startOfThisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? startOfThisWeek

        // Buckets in display order
        var today: [WalletTransaction] = []
        var yesterday: [WalletTransaction] = []
        var thisWeek: [WalletTransaction] = []
        var thisMonth: [WalletTransaction] = []
        var earlier: [WalletTransaction] = []

        for t in txns {
            if t.date >= startOfToday {
                today.append(t)
            } else if t.date >= startOfYesterday {
                yesterday.append(t)
            } else if t.date >= startOfThisWeek {
                thisWeek.append(t)
            } else if t.date >= startOfThisMonth {
                thisMonth.append(t)
            } else {
                earlier.append(t)
            }
        }

        var groups: [TransactionGroup] = []
        if !today.isEmpty     { groups.append(.init(title: "Today",      transactions: today)) }
        if !yesterday.isEmpty { groups.append(.init(title: "Yesterday",  transactions: yesterday)) }
        if !thisWeek.isEmpty  { groups.append(.init(title: "This Week",  transactions: thisWeek)) }
        if !thisMonth.isEmpty { groups.append(.init(title: "This Month", transactions: thisMonth)) }
        if !earlier.isEmpty   { groups.append(.init(title: "Earlier",    transactions: earlier)) }
        return groups
    }

    // MARK: - Computed Properties

    private var filteredTransactions: [WalletTransaction] {
        switch filter {
        case .all:       return walletManager.transactions
        case .pending:   return walletManager.transactions.filter { $0.status == .pending }
        case .completed: return walletManager.transactions.filter { $0.status == .completed }
        }
    }

    private var maxPages: Int {
        max(1, Int(ceil(Double(filteredTransactions.count) / Double(pageSize))))
    }

    private var paginatedTransactions: [WalletTransaction] {
        let startIndex = (currentPage - 1) * pageSize
        let endIndex = min(startIndex + pageSize, filteredTransactions.count)
        guard startIndex < filteredTransactions.count else { return [] }
        return Array(filteredTransactions[startIndex..<endIndex])
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bolt.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating)
            Text("No activity yet")
                .font(.title3.weight(.semibold))
            Text("Your first payment will show up here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
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
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
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

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func formatRelativeDate(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
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

    // MARK: - Pagination

    private var paginationControls: some View {
        HStack(spacing: 8) {
            Spacer()

            Button { currentPage = 1 } label: {
                Image(systemName: "chevron.left.2")
            }
            .disabled(currentPage <= 1)
            .accessibilityLabel("First page")

            Button { currentPage = max(1, currentPage - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage <= 1)
            .accessibilityLabel("Previous page")

            Text("Page \(currentPage) of \(maxPages)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .contentTransition(.numericText())

            Button { currentPage = min(maxPages, currentPage + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPage >= maxPages)
            .accessibilityLabel("Next page")

            Button { currentPage = maxPages } label: {
                Image(systemName: "chevron.right.2")
            }
            .disabled(currentPage >= maxPages)
            .accessibilityLabel("Last page")

            Spacer()
        }
        .font(.footnote)
        .buttonStyle(.borderless)
    }
}

#Preview {
    HistoryView()
        .environmentObject(WalletManager())
}
