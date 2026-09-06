import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    /// Snapshot at open; [transaction] prefers the live wallet row so a
    /// successful open-check can flip Pending → Completed without dismissing.
    private let seed: WalletTransaction
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

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
        if transaction.kind == .ecash, let token = transaction.token { return token }
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

    /// A reusable BOLT12 offer — its bech32 human-readable prefix is `lno`.
    private var isReusableOffer: Bool {
        transaction.invoice?.lowercased().hasPrefix("lno") == true
    }

    /// Whether the stored request is still worth showing as a QR. A record of a
    /// *settled* one-shot invoice shouldn't reoffer a dead payment code, so the QR
    /// (and its Copy / Share) appears only while the content is still actionable.
    private var showsQR: Bool {
        switch transaction.kind {
        case .ecash:
            // Governs the scannable/shareable artifacts (QR hero + top Share).
            // A claimed token is spent, so only an unclaimed (pending) send is
            // still worth re-presenting. The passive Copy button is separate — it
            // extends to settled tokens as a receipt via `copyableContent`.
            // An unclaimed *incoming* token is money to claim, not a payment
            // code to hand out — its detail leads with the Receive button.
            if transaction.isPendingReceiveToken { return false }
            return transaction.token != nil && transaction.status == .pending
        case .lightning:
            guard transaction.invoice != nil else { return false }
            return transaction.status == .pending || isReusableOffer
        case .onchain:
            // The address is only worth re-presenting while the deposit is
            // still awaited; once confirmed this is a historical receipt like
            // a settled invoice — checkmark hero, no QR.
            return transaction.invoice != nil && transaction.status == .pending
        }
    }

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

    /// Every transaction detail opens as a member of the same receipt-sheet
    /// family; only the height varies with content. A QR hero needs most of the
    /// screen, an onchain receipt carries an extra explorer row, and everything
    /// else fits the standard receipt detent. `.large` stays reachable by drag.
    /// The QR fraction is sized so the scroll content — including its 24pt
    /// bottom padding, the row-to-CTA gap every receipt shows — fits without
    /// clipping; any tighter and that gap is the first thing cut.
    private var presentationDetents: Set<PresentationDetent> {
        if transaction.displayDescription != nil { return [.large] }
        if showsQR { return [.fraction(0.94), .large] }
        return transaction.kind == .onchain
            ? [.fraction(0.78), .large]
            : [.fraction(0.68), .large]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Hero: an actionable QR (unclaimed token / pending or
                        // reusable invoice), else a state glyph that bounces in on
                        // open — green check when completed, red X when failed;
                        // nothing while a no-QR transaction is still pending.
                        if !showsQR || transaction.displayDescription == nil {
                            heroSlot
                        }

                        // Receipt amounts use the same primary/secondary ordering
                        // as Home and History. The glyph above carries state colour.
                        TransactionReceiptAmountPair(
                            transaction: transaction,
                            role: showsQR ? .amountCompact : .amountConfirm,
                            preferredPrimary: settings.homeBalancePrimary,
                            showFiat: settings.showFiatBalance,
                            btcPrice: priceService.btcPriceUSD,
                            currencyCode: settings.bitcoinPriceCurrency,
                            useBitcoinSymbol: settings.useBitcoinSymbol
                        )
                        .padding(.top, heroSlotIsEmpty ? 32 : 0)

                        if let description = transaction.displayDescription {
                            DescriptionDetailRow(description: description)
                            if showsQR { heroSlot }
                        }

                        // Detail rows on canvas, led by Status + Date. Type is
                        // omitted — the nav title names it.
                        VStack(spacing: 0) {
                            ForEach(Array(detailRows.enumerated()), id: \.offset) { _, row in
                                if let copyValue = row.copyValue {
                                    copyableRow(label: row.label, value: row.value, copyValue: copyValue)
                                } else {
                                    detailRow(label: row.label, value: row.value)
                                }
                            }
                            if let explorerURL = onchainExplorerURL {
                                explorerLinkRow(label: "View in block explorer", url: explorerURL)
                            }
                        }
                        .padding(.top, 8)
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
                    .padding(.horizontal)
                    .padding(.bottom, copyableContent == nil ? 0 : 24)
                }
                .scrollBounceBehavior(.basedOnSize)

                // Pending outgoing ecash gains the same one-off status action as
                // the generated-token screen when automatic checks are disabled.
                // Keep it after Copy so the two surfaces share the same action order.
                if offersManualClaimCheck || copyableContent != nil {
                    VStack(spacing: 12) {
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
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                // Title only — no close or share chrome. Like every receipt
                // sheet, dismissal is the drag indicator / swipe, and sharing
                // stays on the QR itself (context menu + VoiceOver action).
                ToolbarItem(placement: .principal) {
                    Text(transaction.displayTitle).font(.headline)
                }
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
        }
        .compactBottomSheetSurface()
        .presentationDetents(presentationDetents)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    /// The hero above the amount. An actionable request shows its QR; otherwise a
    /// state glyph bounces in on open — green check (completed) / red X (failed),
    /// same size as the payment-success screen. A pending, no-QR tx shows nothing.
    @ViewBuilder
    private var heroSlot: some View {
        if showsQR, let content = qrContent {
            QRCodeView(
                content: content,
                showControls: false,
                // Lightning invoices / Bitcoin addresses are standard QR formats;
                // ecash tokens are long and benefit from UR-animated encoding.
                staticOnly: transaction.kind != .ecash,
                onCopy: { copyContent(content) },
                onShare: { showShareSheet = true }
            )
            .frame(width: 280, height: 280)
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            .padding(.top, 8)
            .contextMenu {
                Button(action: { copyContent(content) }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button(action: { showShareSheet = true }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        } else if transaction.status == .completed {
            // Static glyph — no `.symbolEffect(.bounce)`. This is historical review
            // (a detail screen re-opened often), not the live payment-received moment
            // that owns the bounce (DESIGN.md §6). The status already happened.
            // Status hero, not an inline notice — but it speaks the same
            // severity vocabulary, so it takes the same tokens rather than
            // raw .green/.red.
            Image(systemName: "checkmark.circle.fill")
                .font(.statusGlyph)
                .foregroundStyle(ErrorSeverity.success.foreground)
                .padding(.top, 24)
                .accessibilityLabel("Completed")
        } else if transaction.status == .failed {
            Image(systemName: "xmark.circle.fill")
                .font(.statusGlyph)
                .foregroundStyle(ErrorSeverity.error.foreground)
                .padding(.top, 24)
                .accessibilityLabel("Failed")
        }
    }

    /// True when the hero renders nothing (a no-QR transaction still pending, or
    /// an expired invoice — deliberately quiet, no glyph), so the amount gets top
    /// breathing room instead of butting against the nav bar.
    private var heroSlotIsEmpty: Bool {
        !showsQR && transaction.isUnsettled
    }

    /// The lifecycle word for the Status row. Direction/rail come from the nav
    /// title, so this only names the state: completed → Claimed/Paid/Confirmed.
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
                rows.append(("Mint", extractMintHost(mintUrl), nil))
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
                rows.append(("Mint", extractMintHost(mintUrl), nil))
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
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
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
            .padding(.vertical, 14)
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
            .padding(.vertical, 14)
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

/// Prose uses the full inspector width and remains selectable without truncation.
struct DescriptionDetailRow: View {
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .foregroundStyle(.secondary)
            Text(description)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
