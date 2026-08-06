import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    /// Snapshot at open; [transaction] prefers the live wallet row so a
    /// successful open-check can flip Pending → Completed without dismissing.
    private let seed: WalletTransaction
    @ObservedObject var settings = SettingsManager.shared

    @State private var copyButtonText = "Copy"
    @State private var showShareSheet = false
    /// Label of the row whose value was just copied — drives the doc.on.doc →
    /// green checkmark swap on tap-to-copy rows (Address / Transaction ID / …).
    @State private var copiedRowLabel: String?
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
        walletManager.transactions.resolveForDetail(
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

    private var pendingSentToken: PendingToken? {
        pendingSentTokenFor(
            transaction: transaction,
            pendingTokens: walletManager.pendingTokens
        )
    }

    private var offersManualClaimCheck: Bool {
        shouldOfferManualClaimCheck(
            automaticChecksEnabled: settings.checkSentTokens,
            pendingToken: pendingSentToken
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Hero: an actionable QR (unclaimed token / pending or
                        // reusable invoice), else a state glyph that bounces in on
                        // open — green check when completed, red X when failed;
                        // nothing while a no-QR transaction is still pending.
                        heroSlot

                        // Amount hero — always crisp `.primary`; the glyph above
                        // carries the state colour.
                        Group {
                            if !isSatUnit {
                                AmountLockup(
                                    parts: AmountParts.parse(formattedNativeAmount),
                                    role: showsQR ? .amountCompact : .amountConfirm,
                                    value: Double(transaction.amount),
                                    accessibilityPrefix: "Amount"
                                )
                            } else if transaction.kind == .onchain {
                                AmountLockup(
                                    parts: AmountFormatter.satsParts(
                                        transaction.amount, useBitcoinSymbol: settings.useBitcoinSymbol
                                    ),
                                    role: showsQR ? .amountCompact : .amountConfirm,
                                    value: Double(transaction.amount),
                                    accessibilityPrefix: "Amount"
                                )
                            } else {
                                CurrencyAmountDisplay(
                                    sats: transaction.amount,
                                    primary: $settings.amountDisplayPrimary,
                                    role: showsQR ? .amountCompact : .amountConfirm
                                )
                                .accessibilityLabel("Amount: \(transaction.amount) sats")
                            }
                        }
                        .padding(.top, heroSlotIsEmpty ? 32 : 0)

                        // Detail rows on canvas, led by Status + Date. Type is
                        // omitted — the nav title names it.
                        VStack(spacing: 0) {
                            ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                                if let copyValue = row.copyValue {
                                    copyableRow(icon: row.icon, label: row.label, value: row.value, copyValue: copyValue)
                                } else {
                                    detailRow(icon: row.icon, label: row.label, value: row.value)
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
                }

                // Pending outgoing ecash gains the same one-off status action as
                // the generated-token screen when automatic checks are disabled.
                // Keep it after Copy so the two surfaces share the same action order.
                if offersManualClaimCheck || copyableContent != nil {
                    VStack(spacing: 12) {
                        if let content = copyableContent {
                            Button(action: { copyContent(content) }) {
                                Text(copyButtonText)
                            }
                            .glassButton()
                            .accessibilityLabel(copyButtonText == "Copied" ? "Copied" : "Copy \(qrContentTypeLabel)")
                            .accessibilityHint("Copies the \(qrContentAccessibilityLabel) to clipboard")
                        }

                        if offersManualClaimCheck, let pendingToken = pendingSentToken {
                            Button(action: { startManualClaimCheck(pendingToken) }) {
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
                ToolbarItem(placement: .navigationBarLeading) {
                    SheetCloseButton()
                }
                ToolbarItem(placement: .principal) {
                    Text(transaction.displayTitle).font(.headline)
                }
                if showsQR {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .toolbarIconTapTarget()
                        }
                        .accessibilityLabel("Share")
                    }
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
                .font(.system(size: 64))
                .foregroundStyle(ErrorSeverity.success.foreground)
                .padding(.top, 24)
                .accessibilityLabel("Completed")
        } else if transaction.status == .failed {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64))
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

    /// A monochrome row glyph for the Status row (row icons are all `.secondary`).
    private var statusFieldIcon: String {
        switch transaction.status {
        case .completed: return "checkmark.circle"
        case .pending:   return "clock"
        case .failed:    return "xmark.circle"
        case .expired:   return "clock.badge.xmark"
        }
    }

    /// Detail rows as data, led by Status + Date, so the hairline interleaving stays
    /// correct as later rows drop out. Unit is gone (`unitLabel` is always BTC/SAT);
    /// the settled Request string is gone (its live form is the QR/Copy). On-chain
    /// keeps Address / Transaction ID (still actionable).
    private var detailRows: [(icon: String, label: String, value: String, copyValue: String?)] {
        var rows: [(icon: String, label: String, value: String, copyValue: String?)] = [
            (statusFieldIcon, "Status", statusFieldValue, nil),
            ("calendar", "Date", transaction.date.formatted(date: .abbreviated, time: .shortened), nil),
        ]
        if transaction.fee > 0 {
            rows.append(("arrow.up.arrow.down", "Fee", formattedNativeFee, nil))
        }
        if transaction.kind == .onchain {
            if let mintUrl = transaction.mintUrl {
                rows.append(("bitcoinsign.bank.building", "Mint", extractMintHost(mintUrl), nil))
            }
            // Address/txid are reference blobs — show the decoder's standard
            // 8…6 short form; tap-to-copy carries the full value.
            if let request = transaction.invoice {
                rows.append(("qrcode", "Address", PaymentRequestDecoder.middleTruncated(request), request))
            }
            if let preimage = transaction.preimage {
                rows.append(("checkmark.seal", "Transaction ID", PaymentRequestDecoder.middleTruncated(preimage), preimage))
            }
        } else {
            if let mintUrl = transaction.mintUrl {
                rows.append(("bitcoinsign.bank.building", "Mint", extractMintHost(mintUrl), nil))
            }
            if let preimage = transaction.preimage {
                rows.append(("key", "Payment Proof", preimage, preimage))
            }
        }
        return rows
    }

    private var isSatUnit: Bool {
        transaction.unit.caseInsensitiveCompare("sat") == .orderedSame
    }

    private var formattedNativeAmount: String {
        CurrencyAmount(
            value: transaction.amount,
            currency: CurrencyRegistry.currency(forMintUnit: transaction.unit)
        ).formatted()
    }

    private var formattedNativeFee: String {
        if isSatUnit { return "\(transaction.fee) sat" }
        return CurrencyAmount(
            value: transaction.fee,
            currency: CurrencyRegistry.currency(forMintUnit: transaction.unit)
        ).formatted()
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
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
    }

    /// Same shape as `detailRow` but tap-to-copy: copies the FULL value (the
    /// display may be middle-truncated) with a success haptic and a fleeting
    /// doc.on.doc → green checkmark swap — the app's copy-feedback convention
    /// (iOS has no native toast). Deliberately no `.textSelection`: it would
    /// fight the tap gesture, and the row itself is the copy affordance.
    private func copyableRow(icon: String, label: String, value: String, copyValue: String) -> some View {
        let isCopied = copiedRowLabel == label
        return Button {
            UIPasteboard.general.string = copyValue
            HapticFeedback.notification(.success)
            copiedRowLabel = label
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if copiedRowLabel == label { copiedRowLabel = nil }
            }
        } label: {
            HStack {
                Label(label, systemImage: icon)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.footnote)
                    .foregroundStyle(isCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    .padding(.leading, 4)
            }
            .font(.subheadline)
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: copiedRowLabel)
        .accessibilityLabel(isCopied ? "\(label) copied" : label)
        .accessibilityHint("Copies the \(label.lowercased()) to clipboard")
    }

    /// Same shape as `detailRow` but opens an external URL, with the trailing
    /// arrow-up-right glyph settings uses for outbound links — the on-chain
    /// block explorer row (matches the receive screen's row).
    private func explorerLinkRow(label: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Label(label, systemImage: "safari")
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
        copyButtonText = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copyButtonText = "Copy"
        }
    }

    private func startManualClaimCheck(_ pendingToken: PendingToken) {
        manualClaimCheckTask?.cancel()
        manualClaimCheckTask = Task {
            isCheckingClaim = true
            manualClaimCheckResult = nil
            defer { isCheckingClaim = false }

            do {
                let outcome = try await runPendingTokenClaimCheck {
                    try await walletManager.checkPendingTokenStatus(pendingToken: pendingToken)
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
