import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @State private var filterPending: Bool = false
    @State private var selectedTransaction: WalletTransaction?
    @State private var isCheckingStatus: String? = nil
    
    // Pagination - show more items to fill the screen
    @State private var currentPage: Int = 1
    private let pageSize: Int = 10
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if filteredTransactions.isEmpty {
                        emptyStateView
                    } else {
                        transactionsList
                    }
                    
                    // Filter button
                    filterButton
                        .padding(.vertical, 16)
                    
                    // Pagination
                    if maxPages > 1 {
                        paginationControls
                            .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("History")
                        .font(.headline)
                        .foregroundColor(settings.accentColor)
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
                    .environmentObject(walletManager)
            }
            .task {
                await walletManager.loadTransactions()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cashuTransactionsUpdated)) { _ in
                // Force view refresh when transactions are updated
                // The @EnvironmentObject will handle the actual data update
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
    
    // MARK: - Views
    
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
                    .font(.system(size: 48))
                    .foregroundColor(.cashuMutedText)
                Text("No Transactions Yet")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Your transaction history will appear here")
                    .font(.subheadline)
                    .foregroundColor(.cashuMutedText)
                Spacer()
            }
            .padding()
        }
    }
    
    private var transactionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(paginatedTransactions) { transaction in
                    transactionRow(transaction: transaction)
                }
            }
        }
        .refreshable {
            await walletManager.checkAllPendingTokens()
        }
    }
    
    private func transactionRow(transaction: WalletTransaction) -> some View {
        HStack(spacing: 12) {
            // Transaction kind icon (Ecash or Lightning)
            ZStack {
                transactionKindIcon(transaction.kind)
            }
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.05))
            .clipShape(Circle())
            .accessibilityHidden(true)

            // Main content - tappable area
            Button(action: {
                selectedTransaction = transaction
            }) {
                HStack(alignment: .center) {
                    // Details
                    VStack(alignment: .leading, spacing: 0) {
                        Text(transaction.kind == .ecash ? "Ecash" : "Lightning")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                        
                        Text(formatRelativeDate(transaction.date))
                            .font(.system(size: 14))
                            .foregroundColor(.cashuMutedText)
                    }
                    
                    Spacer()
                    
                    // Amount and status
                    VStack(alignment: .trailing, spacing: 0) {
                        // Amount - green for incoming, white for outgoing (pending shows gray)
                        Text(formatAmount(transaction))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(amountColor(transaction))
                        
                        // Status text for pending
                        if transaction.status == .pending {
                            Text("Pending")
                                .font(.system(size: 14))
                                .foregroundColor(.cashuMutedText)
                        } else {
                            // Empty space for consistent height matching Vue's &nbsp;
                            Text(" ")
                                .font(.system(size: 14))
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(transaction.kind == .ecash ? "Ecash" : "Lightning") transaction, \(formatAmount(transaction)) sats, \(transaction.status == .pending ? "pending" : "completed"), \(formatRelativeDate(transaction.date))")
            .accessibilityHint("Opens transaction details")

            // Refresh button for pending ecash transactions
            if transaction.status == .pending && transaction.kind == .ecash {
                Button(action: {
                    Task {
                        await checkTransactionStatus(transaction)
                    }
                }) {
                    if isCheckingStatus == transaction.id {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .cashuMutedText))
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16))
                            .foregroundColor(.cashuMutedText)
                            .frame(width: 24, height: 24)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(isCheckingStatus == transaction.id ? "Checking status" : "Refresh status")
                .accessibilityHint("Checks if this pending token has been claimed")
            } else {
                // Spacer to maintain consistent layout
                Spacer()
                    .frame(width: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private func transactionKindIcon(_ kind: WalletTransaction.TransactionKind) -> some View {
        switch kind {
        case .ecash:
            EcashIcon(size: 20, color: settings.accentColor)
        case .lightning:
            LightningIcon(size: 20, color: settings.accentColor)
        }
    }
    
    private func formatAmount(_ transaction: WalletTransaction) -> String {
        let prefix = transaction.type == .incoming ? "+" : "-"
        return "\(prefix)\(settings.formatAmountShort(transaction.amount))"
    }
    
    private func amountColor(_ transaction: WalletTransaction) -> Color {
        if transaction.status == .pending {
            return .cashuMutedText
        }
        
        if transaction.type == .incoming {
            // Replicate Vue's hsl(120, 88%, 58%) which is a bright neon green
            return Color(red: 0.21, green: 0.95, blue: 0.21)
        }
        
        return .white
    }
    
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func formatRelativeDate(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func checkTransactionStatus(_ transaction: WalletTransaction) async {
        guard let token = transaction.token else { return }
        
        isCheckingStatus = transaction.id
        defer { isCheckingStatus = nil }
        
        let isSpent = await walletManager.checkTokenSpendable(token: token)
        
        if isSpent {
            // Token was redeemed - remove from pending
            walletManager.removePendingToken(tokenId: transaction.id)
            await walletManager.loadTransactions()
        }
        // If not spent, keep as pending
    }
    
    // MARK: - Filter Button
    
    private var filterButton: some View {
        Button(action: {
            filterPending.toggle()
            currentPage = 1
        }) {
            Text(filterPending ? "SHOW ALL" : "FILTER PENDING")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(filterPending ? .black : settings.accentColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(filterPending ? settings.accentColor : Color.clear)
                        .overlay(
                            Capsule()
                                .stroke(settings.accentColor, lineWidth: 1.5)
                        )
                )
        }
        .accessibilityLabel(filterPending ? "Show all transactions" : "Filter pending transactions")
        .accessibilityHint("Toggles between showing all transactions and only pending ones")
    }
    
    // MARK: - Pagination
    
    private var paginationControls: some View {
        HStack(spacing: 8) {
            // First page
            paginationButton(text: "|<", action: { currentPage = 1 }, enabled: currentPage > 1, label: "First page")

            // Previous page
            paginationButton(text: "<", action: { currentPage = max(1, currentPage - 1) }, enabled: currentPage > 1, label: "Previous page")
            
            // Page numbers
            ForEach(visiblePageNumbers, id: \.self) { pageNum in
                if pageNum == -1 {
                    Text("...")
                        .font(.system(size: 14))
                        .foregroundColor(.cashuMutedText)
                        .frame(width: 30)
                } else {
                    pageNumberButton(pageNum)
                }
            }
            
            // Next page
            paginationButton(text: ">", action: { currentPage = min(maxPages, currentPage + 1) }, enabled: currentPage < maxPages, label: "Next page")

            // Last page
            paginationButton(text: ">|", action: { currentPage = maxPages }, enabled: currentPage < maxPages, label: "Last page")
        }
    }
    
    private var visiblePageNumbers: [Int] {
        var pages: [Int] = []
        
        if maxPages <= 5 {
            pages = Array(1...maxPages)
        } else {
            pages.append(1)
            
            if currentPage > 3 {
                pages.append(-1) // Ellipsis
            }
            
            let start = max(2, currentPage - 1)
            let end = min(maxPages - 1, currentPage + 1)
            
            for i in start...end {
                if !pages.contains(i) {
                    pages.append(i)
                }
            }
            
            if currentPage < maxPages - 2 {
                pages.append(-1) // Ellipsis
            }
            
            if !pages.contains(maxPages) {
                pages.append(maxPages)
            }
        }
        
        return pages
    }
    
    private func paginationButton(text: String, action: @escaping () -> Void, enabled: Bool, label: String = "") -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(enabled ? settings.accentColor : .cashuMutedText.opacity(0.5))
        }
        .disabled(!enabled)
        .frame(width: 30)
        .accessibilityLabel(label.isEmpty ? text : label)
    }
    
    private func pageNumberButton(_ page: Int) -> some View {
        Button(action: { currentPage = page }) {
            Text("\(page)")
                .font(.system(size: 14, weight: currentPage == page ? .bold : .medium))
                .foregroundColor(currentPage == page ? .black : settings.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(currentPage == page ? settings.accentColor : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(settings.accentColor, lineWidth: currentPage == page ? 0 : 1)
                        )
                )
        }
        .accessibilityLabel("Page \(page)")
        .accessibilityValue(currentPage == page ? "Current page" : "")
    }
}

#Preview {
    HistoryView()
        .environmentObject(WalletManager())
}
