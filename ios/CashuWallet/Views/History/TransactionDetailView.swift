import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    /// Snapshot at open; [transaction] prefers the live wallet row so a
    /// successful open-check can flip Pending → Completed without dismissing.
    private let seed: WalletTransaction
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    @State private var claimReceiveToken: PendingReceiveToken?
    @State private var showShareSheet = false
    @State private var isCheckingClaim = false
    @State private var manualClaimCheckResult: PendingTokenClaimCheckResult?
    @State private var manualClaimCheckTask: Task<Void, Never>?

    init(transaction: WalletTransaction) {
        self.seed = transaction
    }

    /// Live row from the wallet when present; falls back to the open-time seed.
    /// After a mint, CDK replaces the pending quote-id row with a new transaction
    /// id that still carries `quoteId` — follow that so status flips in place.
    private var transaction: WalletTransaction {
        walletManager.transactions.liveDetail(
            openId: seed.id,
            openQuoteId: seed.quoteId ?? seed.id
        ) ?? seed
    }

    /// Returns the content to display as a QR code.
    private var qrContent: String? {
        if let token = transaction.token { return token }
        if let invoice = transaction.invoice { return invoice }
        return nil
    }

    /// Content for the bottom Copy button. Unlike `qrContent`, this also covers a
    /// *settled* ecash token as a copyable receipt — the string is a record of
    /// what was received/sent even though its proofs are spent. QR and Share stay
    /// gated on `showsQR` so the app never re-presents a spent token as a
    /// scannable/shareable payment artifact; only the passive Copy is extended.
    /// See DESIGN.md → the settled-ecash receipt carve-out.
    private var copyableContent: String? {
        if showsQR { return qrContent }
        if transaction.kind == .ecash, transaction.status == .completed,
           let token = transaction.token { return token }
        return nil
    }

    /// A pending (unclaimed) sent token offers a one-off status probe when
    /// automatic checks are disabled. CDK tracks the lifecycle; the app only
    /// triggers `checkSendStatus` for the row's saga.
    private var offersManualClaimCheck: Bool {
        shouldOfferManualClaimCheck(
            automaticChecksEnabled: settings.checkSentTokens,
            transaction: transaction
        )
    }

    private var showsQR: Bool { transaction.hasActionablePaymentCode }

    private var qrContentTypeLabel: String {
        switch transaction.kind {
        case .ecash:     return "token"
        case .lightning: return "request"
        case .onchain:   return "address"
        }
    }

    private var qrContentAccessibilityLabel: String {
        switch transaction.kind {
        case .ecash:     return "ecash token"
        case .lightning: return "payment request"
        case .onchain:   return "bitcoin address"
        }
    }

    var body: some View {
        ActivityDetailSheet(title: transaction.displayTitle) {
            receiptDetails
            if showsQR, let content = qrContent {
                ActivityPaymentCode(
                    content: content,
                    staticOnly: transaction.kind != .ecash,
                    onCopy: { copyContent(content) },
                    onShare: { showShareSheet = true }
                )
            }
            receiptActions
        }
        .sheet(isPresented: $showShareSheet) {
            if let token = transaction.token {
                CashuTokenShareSheet(token: token)
            } else if let invoice = transaction.invoice {
                ShareSheet(items: [invoice])
            }
        }
        // Single-quote check on open (not the full pending list). Re-checks
        // this mint quote against the mint and mints if already paid —
        // Android TransactionDetailScreen parity.
        .task(id: seed.id) {
            guard let quoteId = seed.mintQuoteIdForStatusRefresh else { return }
            _ = await walletManager.refreshPendingMintQuote(quoteId: quoteId)
        }
        .onDisappear {
            manualClaimCheckTask?.cancel()
        }
        .fullScreenCover(item: $claimReceiveToken) { pending in
            ReceiveTokenDetailView(
                tokenString: pending.token,
                onComplete: {
                    claimReceiveToken = nil
                    dismiss()
                },
                claim: { try await walletManager.claimPendingReceiveToken(pending) }
            )
            .environmentObject(walletManager)
        }
    }

    // MARK: - Subviews

    private var receiptDetails: some View {
        VStack(spacing: 24) {
            // Receipt amounts use the same primary/secondary ordering
            // as Home and History, at one stable scale for every lifecycle.
            TransactionReceiptAmountPair(
                transaction: transaction,
                role: .amountConfirm,
                preferredPrimary: settings.homeBalancePrimary,
                showFiat: settings.showFiatBalance,
                btcPrice: priceService.btcPriceUSD,
                currencyCode: settings.bitcoinPriceCurrency,
                useBitcoinSymbol: settings.useBitcoinSymbol
            )

            // Detail rows on canvas, led by Status + Date. Type is
            // omitted — the nav title names it.
            VStack(spacing: 0) {
                ForEach(Array(detailRows.enumerated()), id: \.offset) { _, row in
                    if let copyValue = row.copyValue {
                        copyableRow(label: row.label, value: row.value, copyValue: copyValue)
                    } else {
                        detailRow(label: row.label, value: row.value)
                    }
                    if row.label == "Mint", let description = transaction.displayDescription {
                        DescriptionDetailRow(description: description)
                    }
                }
                if !detailRows.contains(where: { $0.label == "Mint" }),
                   let description = transaction.displayDescription {
                    DescriptionDetailRow(description: description)
                }
                if let explorerURL = onchainExplorerURL {
                    explorerLinkRow(label: "View in block explorer", url: explorerURL)
                }
            }
            .padding(.horizontal, 4)

            if offersManualClaimCheck {
                switch manualClaimCheckResult {
                case .notClaimed:
                    InlineNotice(
                        message: "This token has not been claimed yet.",
                        title: "Status checked",
                        severity: .info
                    )
                case .failed(let message):
                    InlineNotice(
                        message: message.text,
                        title: "Couldn't check status",
                        severity: message.severity
                    )
                case .claimed, nil:
                    EmptyView()
                }
            }
        }
    }


    @ViewBuilder
    private var receiptActions: some View {
        if offersManualClaimCheck || copyableContent != nil || pendingReceive != nil {
            VStack(spacing: 12) {
                if let pending = pendingReceive {
                    Button("Receive") { claimReceiveToken = pending }
                        .glassButton()
                }
                if let content = copyableContent {
                    Button(action: { copyContent(content) }) {
                        Text("Copy")
                    }
                    .flatSheetSecondaryButton()
                    .accessibilityLabel("Copy \(qrContentTypeLabel)")
                    .accessibilityHint("Copies the \(qrContentAccessibilityLabel) to clipboard")
                }

                if offersManualClaimCheck {
                    Button(action: { startManualClaimCheck() }) {
                        if isCheckingClaim {
                            ProgressView()
                        } else {
                            Text("Check Status")
                        }
                    }
                    .glassButton()
                    .disabled(isCheckingClaim)
                    .accessibilityIdentifier("cashu.history.check-token-status")
                    .accessibilityLabel(isCheckingClaim ? "Checking claim status" : "Check Status")
                    .accessibilityInputLabels(["Check Status"])
                }
            }
        }
    }


    private var pendingReceive: PendingReceiveToken? {
        guard transaction.isPendingReceiveToken, transaction.status == .pending else { return nil }
        return walletManager.pendingReceiveTokens.first { $0.tokenId == transaction.id }
    }

    /// Direction and rail come from the title; this row names the lifecycle.
    private var statusFieldValue: String {
        switch transaction.status {
        case .completed:
            switch transaction.kind {
            case .ecash:     return "Claimed"
            case .lightning: return "Paid"
            case .onchain:   return "Confirmed"
            }
        case .pending: return "Pending"
        case .failed:  return "Failed"
        case .expired: return "Expired"
        }
    }

    /// Detail rows as data, led by Status + Date, so the hairline interleaving stays
    /// correct as later rows drop out. Unit is gone (`unitLabel` is always BTC/SAT);
    /// the settled Request string is gone (its live form is the QR/Copy). On-chain
    /// keeps Address / Transaction ID (still actionable).
    private var detailRows: [(label: String, value: String, copyValue: String?)] {
        var rows: [(label: String, value: String, copyValue: String?)] = [
            ("Status", statusFieldValue, nil),
            ("Date", transaction.date.formatted(date: .abbreviated, time: .shortened), nil),
        ]
        if transaction.fee > 0 {
            rows.append(("Fee", formattedNativeFee, nil))
        }
        if transaction.kind == .onchain {
            if let mintUrl = transaction.mintUrl {
                rows.append(("Mint", walletManager.mints.first(where: { $0.url == mintUrl })?.name ?? extractMintHost(mintUrl), nil))
            }
            // Address/txid are reference blobs — show the decoder's standard
            // 8…6 short form; tap-to-copy carries the full value.
            if let request = transaction.invoice {
                rows.append(("Address", PaymentRequestDecoder.middleTruncated(request), request))
            }
            if let preimage = transaction.preimage {
                rows.append(("Transaction ID", PaymentRequestDecoder.middleTruncated(preimage), preimage))
            }
        } else {
            if let mintUrl = transaction.mintUrl {
                rows.append(("Mint", walletManager.mints.first(where: { $0.url == mintUrl })?.name ?? extractMintHost(mintUrl), nil))
            }
            if let preimage = transaction.preimage {
                rows.append(("Payment Proof", PaymentRequestDecoder.middleTruncated(preimage), preimage))
            }
        }
        return rows
    }

    private var isSatUnit: Bool {
        CurrencyRegistry.isSatoshiUnit(transaction.unit)
    }

    private var formattedNativeFee: String {
        if isSatUnit { return "\(transaction.fee) sat" }
        return CurrencyAmount(
            value: transaction.fee,
            currency: CurrencyRegistry.currency(forMintUnit: transaction.unit)
        ).formatted()
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    /// Same shape as `detailRow` but tap-to-copy: copies the FULL value while
    /// leaving the affordance visually stable. The shared top toast is the one
    /// confirmation channel; no icon morph competes with it.
    private func copyableRow(label: String, value: String, copyValue: String) -> some View {
        Button {
            UIPasteboard.general.string = copyValue
            HapticFeedback.notification(.success)
            ConfirmationToast.show(copyConfirmationMessage(for: label))
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "doc.on.doc")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            .font(.subheadline)
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityHint("Copies the \(label.lowercased()) to clipboard")
    }

    /// Same shape as `detailRow` but opens an external URL, with the trailing
    /// arrow-up-right glyph settings uses for outbound links — the on-chain
    /// block explorer row (matches the receive screen's row).
    private func explorerLinkRow(label: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { HapticFeedback.selection() })
        .accessibilityHint("Opens the block explorer in your browser")
    }

    // MARK: - Helpers

    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    private var onchainExplorerURL: URL? {
        guard transaction.kind == .onchain else { return nil }
        if let txid = transaction.preimage {
            return OnchainExplorer.transactionWebURL(
                for: txid,
                address: transaction.invoice,
                mintURL: transaction.mintUrl
            )
        }
        guard let address = transaction.invoice else { return nil }
        return OnchainExplorer.addressWebURL(for: address, mintURL: transaction.mintUrl)
    }

    // MARK: - Actions

    private func copyContent(_ content: String) {
        UIPasteboard.general.string = content
        HapticFeedback.notification(.success)
        ConfirmationToast.show("Copied \(qrContentAccessibilityLabel)")
    }

    private func copyConfirmationMessage(for label: String) -> String {
        switch label {
        case "Address": return "Copied Bitcoin address"
        case "Transaction ID": return "Copied transaction ID"
        case "Payment Proof": return "Copied payment proof"
        default: return "Copied \(label.lowercased())"
        }
    }

    private func startManualClaimCheck() {
        manualClaimCheckTask?.cancel()
        manualClaimCheckTask = Task {
            isCheckingClaim = true
            manualClaimCheckResult = nil
            defer { isCheckingClaim = false }

            do {
                let outcome = try await runPendingTokenClaimCheck {
                    try await walletManager.checkPendingTokenStatus(transaction: transaction)
                }
                guard !Task.isCancelled else { return }

                manualClaimCheckResult = outcome
                announceClaimCheckResult(outcome)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func announceClaimCheckResult(_ outcome: PendingTokenClaimCheckResult) {
        let announcement: String
        switch outcome {
        case .claimed:
            announcement = "Token claimed."
        case .notClaimed:
            announcement = "Status checked. This token has not been claimed yet."
        case .failed(let message):
            announcement = "Couldn't check status. \(message.text)"
        }
        AccessibilityNotification.Announcement(announcement).post()
    }
}

/// A receipt follows the same amount hierarchy selected from the Home balance.
/// It remains a static display rather than an independent entry-mode control.
struct TransactionReceiptAmountPair: View {
    let transaction: WalletTransaction
    let role: CashuTextRole
    let preferredPrimary: AmountDisplayPrimary
    let showFiat: Bool
    let btcPrice: Double?
    let currencyCode: String
    let useBitcoinSymbol: Bool

    static func display(
        transaction: WalletTransaction,
        preferredPrimary: AmountDisplayPrimary,
        showFiat: Bool,
        btcPrice: Double?,
        currencyCode: String,
        useBitcoinSymbol: Bool
    ) -> AmountDisplayText {
        AmountFormatter.displayMintUnitAmount(
            amount: transaction.amount,
            unit: transaction.unit,
            preferredPrimary: preferredPrimary,
            showFiat: showFiat,
            btcPrice: btcPrice,
            currencyCode: currencyCode,
            useBitcoinSymbol: useBitcoinSymbol
        )
    }

    private var amountDisplay: AmountDisplayText {
        Self.display(
            transaction: transaction,
            preferredPrimary: preferredPrimary,
            showFiat: showFiat,
            btcPrice: btcPrice,
            currencyCode: currencyCode,
            useBitcoinSymbol: useBitcoinSymbol
        )
    }

    var body: some View {
        VStack(spacing: AmountPairMetrics.spacing) {
            AmountLockup(
                parts: amountDisplay.primaryParts,
                role: role,
                value: Double(transaction.amount),
                accessibilityPrefix: "Amount"
            )

            if let secondary = amountDisplay.secondary {
                Text(secondary)
                    .cashuText(.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Alternate amount: \(secondary)")
            }
        }
    }
}

/// Prose belongs to the inspector, with a native reader for longer descriptions.
struct DescriptionDetailRow: View {
    let description: String
    @Environment(\.compactPaymentDetails) private var compactPaymentDetails
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var fullHeight: CGFloat = 0
    @State private var previewHeight: CGFloat = 0
    @State private var showFullDescription = false

    private var previewLines: Int {
        compactPaymentDetails || verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize ? 1 : 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description")
                    .foregroundStyle(.secondary)
                Spacer()
                if fullHeight > previewHeight + 1 {
                    Button { showFullDescription = true } label: {
                        Text("Read more")
                            .fontWeight(.medium)
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Opens the full description")
                }
            }
            Text(description)
                .lineLimit(previewLines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
                .background {
                    Text(description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                        .hidden()
                        .accessibilityHidden(true)
                }
                .accessibilityIdentifier("payment-description-preview")
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .sheet(isPresented: $showFullDescription) {
            PaymentDescriptionView(description: description)
                .presentationDetents([.large])
        }
    }
}

private struct PaymentDescriptionView: View {
    let description: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(description)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Stored receive intents use the same inspector as individual transactions.
/// Creating or editing a request remains an explicit action from the receipt.
struct CashuRequestReceiptView: View {
    private let seed: CashuRequest
    @EnvironmentObject private var walletManager: WalletManager
    @ObservedObject private var store = CashuRequestStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared
    @State private var showShareSheet = false
    @State private var showManageRequest = false
    @State private var selectedPayment: WalletTransaction?

    init(request: CashuRequest) { seed = request }

    private var request: CashuRequest { store.request(withId: seed.id) ?? seed }
    private var payments: [WalletTransaction] {
        let ids = Set(request.receivedPayments.map(\.transactionId))
        return walletManager.transactions.filter { ids.contains($0.id) }
    }
    private var totalReceived: UInt64 {
        request.receivedPayments.reduce(0) { total, payment in
            total + (payments.first { $0.id == payment.transactionId }?.amount ?? payment.amount)
        }
    }
    private var status: String {
        switch request.lifecycle {
        case .waiting: return "Waiting for payment"
        case .collecting: return "Active"
        case .received: return request.rail == .onchain ? "Confirmed" : "Paid"
        case .expired: return "Expired"
        }
    }
    private var codeAvailable: Bool {
        !request.encoded.isEmpty && (request.lifecycle == .waiting || request.lifecycle == .collecting)
    }

    var body: some View {
        // One-shot expiry can pass while a receipt is open, even without a store update.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ActivityDetailSheet(title: request.displayTitle) {
                VStack(spacing: 4) {
                    if !request.receivedPayments.isEmpty {
                        Text("Total received").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let amount = request.receivedPayments.isEmpty ? request.amount : totalReceived {
                        let display = amountDisplay(amount)
                        AmountLockup(parts: display.primaryParts, role: .amountConfirm,
                                     value: Double(amount), accessibilityPrefix: "Amount")
                        if let secondary = display.secondary {
                            Text(secondary).cashuText(.bodyEmphasis).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Any amount").cashuText(.amountConfirm)
                    }
                }

                VStack(spacing: 0) {
                    row("Status", status)
                    row("Date", request.createdAt.formatted(date: .abbreviated, time: .shortened))
                    row("Mint", request.mints.isEmpty ? "Any mint" : request.mints.map { url in
                        walletManager.mints.first { $0.url == url }?.name ?? URL(string: url)?.host ?? url
                    }.joined(separator: ", "))
                    if let description = request.displayDescription {
                        DescriptionDetailRow(description: description)
                    }
                    if request.reusable {
                        row("Requested amount", request.amount.map { amountDisplay($0).primary } ?? "Any amount")
                        row("Payments received", "\(request.receivedPayments.count)")
                    }
                    ForEach(payments) { payment in
                        Button { selectedPayment = payment } label: {
                            HStack {
                                Text(payment.date.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(amountDisplay(payment.amount).primary)
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 12)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens payment details")
                    }
                }
                if codeAvailable {
                    ActivityPaymentCode(content: request.encoded,
                                        onCopy: copyRequest, onShare: { showShareSheet = true })
                    Button("Copy", action: copyRequest)
                        .flatSheetSecondaryButton()
                        .accessibilityLabel("Copy payment request")
                }
                if request.rail == .ecash {
                    Button("Manage request") { showManageRequest = true }
                        .flatSheetSecondaryButton()
                }
            }
        }
        .sheet(isPresented: $showShareSheet) { ShareSheet(items: [request.encoded]) }
        .sheet(isPresented: $showManageRequest) {
            NavigationStack {
                CashuRequestDetailView(request: request)
                    .environmentObject(walletManager)
            }
        }
        .sheet(item: $selectedPayment) { payment in
            TransactionDetailView(transaction: payment).environmentObject(walletManager)
        }
        .task(id: seed.id) {
            if let quoteId = request.quoteId {
                _ = await walletManager.refreshPendingMintQuote(quoteId: quoteId)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func amountDisplay(_ amount: UInt64) -> AmountDisplayText {
        AmountFormatter.displayMintUnitAmount(
            amount: amount, unit: request.unit, preferredPrimary: settings.homeBalancePrimary,
            showFiat: settings.showFiatBalance, btcPrice: priceService.btcPriceUSD,
            currencyCode: settings.bitcoinPriceCurrency, useBitcoinSymbol: settings.useBitcoinSymbol
        )
    }

    private func copyRequest() {
        UIPasteboard.general.string = request.encoded
        HapticFeedback.notification(.success)
        ConfirmationToast.show("Copied payment request")
    }
}
