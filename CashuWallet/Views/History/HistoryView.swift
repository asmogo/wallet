import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @State private var filterPending: Bool = false
    @State private var selectedTransaction: WalletTransaction?
    @State private var isCheckingStatus: String? = nil

    // Pagination
    @State private var currentPage: Int = 1
    private let pageSize: Int = 10

    var body: some View {
        NavigationStack {
            Group {
                if filteredTransactions.isEmpty {
                    emptyStateView
                } else {
                    List {
                        Section {
                            ForEach(paginatedTransactions) { transaction in
                                transactionRow(transaction: transaction)
                                    .listRowSeparator(.hidden)
                            }
                        }

                        if maxPages > 1 {
                            Section {
                                paginationControls
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .refreshable {
                        await walletManager.syncPendingMintQuotes()
                        await walletManager.checkAllPendingTokens()
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $filterPending) {
                        Label("Pending Only", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .toggleStyle(.button)
                    .onChange(of: filterPending) {
                        currentPage = 1
                    }
                    .accessibilityLabel(filterPending ? "Show all transactions" : "Filter pending transactions")
                    .accessibilityHint("Toggles between showing all transactions and only pending ones")
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
                    .environmentObject(walletManager)
            }
            .task {
                await walletManager.syncPendingMintQuotes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cashuTransactionsUpdated)) { _ in
                // Force view refresh when transactions are updated
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredTransactions: [WalletTransaction] {
        if filterPending {
            return walletManager.transactions.filter { $0.status == .pending }
        }
        return walletManager.transactions
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
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                "No Transactions Yet",
                systemImage: "clock",
                description: Text("Your transaction history will appear here")
            )
        } else {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "clock")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No Transactions Yet")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Your transaction history will appear here")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Transaction Row

    private func transactionRow(transaction: WalletTransaction) -> some View {
        Button {
            selectedTransaction = transaction
        } label: {
            HStack(spacing: 12) {
                transactionKindIcon(transaction.kind)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.kind.displayName)
                        .font(.body)

                    Text(formatRelativeDate(transaction.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatAmount(transaction))
                        .font(.body.bold())
                        .foregroundStyle(amountColor(transaction))

                    if transaction.status == .pending {
                        Text(transaction.displayStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if transaction.status == .pending {
                    Button {
                        Task {
                            await refreshPendingTransaction(transaction)
                        }
                    } label: {
                        if isCheckingStatus == transaction.id {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isCheckingStatus == transaction.id ? "Checking status" : "Refresh status")
                    .accessibilityHint(refreshHint(for: transaction))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transaction.kind.displayName) transaction, \(formatAmount(transaction)) sats, \(transaction.status == .pending ? transaction.displayStatusText.lowercased() : "completed"), \(formatRelativeDate(transaction.date))")
        .accessibilityHint("Opens transaction details")
    }

    @ViewBuilder
    private func transactionKindIcon(_ kind: WalletTransaction.TransactionKind) -> some View {
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

    // MARK: - Formatting

    private func formatAmount(_ transaction: WalletTransaction) -> String {
        let prefix = transaction.type == .incoming ? "+" : "-"
        return "\(prefix)\(settings.formatAmountShort(transaction.amount))"
    }

    private func amountColor(_ transaction: WalletTransaction) -> Color {
        if transaction.status == .pending {
            return .secondary
        }
        if transaction.type == .incoming {
            return .green
        }
        return .primary
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
        case .ecash:
            return "Checks if this pending token has been claimed"
        case .lightning, .onchain:
            return "Refreshes this pending receive request"
        }
    }

    // MARK: - Pagination

    private var paginationControls: some View {
        HStack {
            Spacer()

            Button("|<") { currentPage = 1 }
                .disabled(currentPage <= 1)
                .accessibilityLabel("First page")

            Button("<") { currentPage = max(1, currentPage - 1) }
                .disabled(currentPage <= 1)
                .accessibilityLabel("Previous page")

            ForEach(visiblePageNumbers, id: \.self) { pageNum in
                if pageNum == -1 {
                    Text("...")
                        .foregroundStyle(.secondary)
                } else {
                    Button("\(pageNum)") { currentPage = pageNum }
                        .fontWeight(currentPage == pageNum ? .bold : .regular)
                        .accessibilityLabel("Page \(pageNum)")
                        .accessibilityValue(currentPage == pageNum ? "Current page" : "")
                }
            }

            Button(">") { currentPage = min(maxPages, currentPage + 1) }
                .disabled(currentPage >= maxPages)
                .accessibilityLabel("Next page")

            Button(">|") { currentPage = maxPages }
                .disabled(currentPage >= maxPages)
                .accessibilityLabel("Last page")

            Spacer()
        }
        .font(.caption)
    }

    private var visiblePageNumbers: [Int] {
        var pages: [Int] = []

        if maxPages <= 5 {
            pages = Array(1...maxPages)
        } else {
            pages.append(1)

            if currentPage > 3 {
                pages.append(-1)
            }

            let start = max(2, currentPage - 1)
            let end = min(maxPages - 1, currentPage + 1)

            for i in start...end {
                if !pages.contains(i) {
                    pages.append(i)
                }
            }

            if currentPage < maxPages - 2 {
                pages.append(-1)
            }

            if !pages.contains(maxPages) {
                pages.append(maxPages)
            }
        }

        return pages
    }
}

#Preview {
    HistoryView()
        .environmentObject(WalletManager())
}
