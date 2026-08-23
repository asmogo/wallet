import SwiftUI
import UIKit

struct CashuRequestDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var store = CashuRequestStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var nostr = NostrService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onClose: (() -> Void)?

    @State private var requestId: String
    @State private var showMintPicker = false
    @State private var showAmountPicker = false
    @State private var showUnitPicker = false
    @State private var paymentObservation: CashuRequestPaymentObservation
    @State private var regenerationError: String?
    @State private var didAutoComplete = false
    /// Amount of the payment that just landed, for the shared success screen.
    @State private var receivedAmount: UInt64?
    @State private var showPaymentSuccess = false
    /// VoiceOver Share action for the QR: ShareLink can't be invoked
    /// imperatively, so the accessibility action presents the share sheet.
    @State private var showShareSheet = false

    init(request: CashuRequest, onClose: (() -> Void)? = nil) {
        self._requestId = State(initialValue: request.id)
        self._paymentObservation = State(
            initialValue: CashuRequestPaymentObservation(existingPayments: request.receivedPayments)
        )
        self.onClose = onClose
    }

    private var request: CashuRequest? {
        store.request(withId: requestId)
    }

    private var paymentCount: Int {
        request?.receivedPayments.count ?? 0
    }

    var body: some View {
        Group {
            if showPaymentSuccess {
                paymentSuccessView
            } else if let request {
                content(request: request)
            } else {
                Text("Request not found")
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.smooth(duration: 0.3), value: showPaymentSuccess)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(request?.displayTitle ?? "Cashu Request")
                    .font(.headline)
            }
            ToolbarItem(placement: .cancellationAction) {
                SheetCloseButton {
                    if let onClose { onClose() } else { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let request {
                    ShareLink(item: request.encoded) {
                        Image(systemName: "square.and.arrow.up")
                            .toolbarIconTapTarget()
                    }
                    .accessibilityLabel("Share request")
                }
            }
        }
        .sheet(isPresented: $showMintPicker) {
            CashuRequestMintPickerSheet(
                currentMintUrl: request?.mints.first,
                onSelect: { mintUrl in
                    let mints: [String] = mintUrl.map { [$0] } ?? []
                    regenerate(mints: mints)
                }
            )
            .environmentObject(walletManager)
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAmountPicker) {
            CashuRequestAmountPickerSheet(
                currentAmount: request?.amount,
                unit: request?.unit ?? "sat",
                onSelect: { amount in
                    regenerate(amount: amount)
                }
            )
        }
        .sheet(isPresented: $showUnitPicker) {
            if let request, let mint = requestMint(for: request) {
                CashuRequestUnitPickerSheet(
                    units: mint.units,
                    currentUnit: request.unit,
                    onSelect: { unit in regenerate(unit: unit) }
                )
                .presentationDetents([.medium])
            }
        }
        .onChange(of: request?.receivedPayments) { _, currentPayments in
            guard let currentPayments,
                  let payment = paymentObservation.newlyLinkedPayment(in: currentPayments) else { return }
            AppLogger.wallet.notice(
                "CashuRequestDetailView: linked payment \(payment.transactionId, privacy: .public)"
            )
            markPaymentReceived(amount: payment.amount)
        }
        .flatBottomSheetSurface()
    }

    /// Single-fire transition into the shared full-screen success — the same
    /// `PaymentStatusView` every other receive/pay flow ends on, so a paid
    /// request reads identically to a paid invoice. Stays until Done.
    private func markPaymentReceived(amount: UInt64?) {
        guard !didAutoComplete else { return }
        didAutoComplete = true
        receivedAmount = amount ?? request?.amount
        // PaymentStatusView owns the success haptic on appear — don't buzz here.
        showPaymentSuccess = true
    }

    /// The shared success screen (checkmark → title → detail rows → Done).
    private var paymentSuccessView: some View {
        PaymentStatusView(
            details: paymentSuccessRows,
            phase: .success,
            successTitle: "Payment Received!",
            onDone: {
                if let onClose { onClose() } else { dismiss() }
            },
            onRetry: {}
        )
    }

    private var paymentSuccessRows: [PaymentStatusView.DetailRow] {
        var rows: [PaymentStatusView.DetailRow] = []
        if let receivedAmount {
            rows.append(.init(
                icon: "bitcoinsign",
                label: "Amount",
                value: request.map { formatAmount(receivedAmount, unit: $0.unit) }
                    ?? AmountFormatter.sats(receivedAmount, useBitcoinSymbol: settings.useBitcoinSymbol)
            ))
        }
        if let request {
            rows.append(.init(
                icon: "bitcoinsign.bank.building",
                label: "Mint",
                value: mintDisplayValue(for: request)
            ))
        }
        return rows
    }

    @ViewBuilder
    private func content(request: CashuRequest) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    QRCodeView(
                        content: request.encoded,
                        showControls: false,
                        staticOnly: true,
                        onCopy: { copy(request.encoded) },
                        onShare: { showShareSheet = true }
                    )
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 8)
                        .contextMenu {
                            Button(action: { copy(request.encoded) }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            ShareLink(item: request.encoded) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                        .sheet(isPresented: $showShareSheet) {
                            ShareSheet(items: [request.encoded])
                        }

                    if let amount = request.amount, amount > 0 {
                        if request.unit.lowercased() == "sat" {
                            CurrencyAmountDisplay(
                                sats: amount,
                                primary: $settings.amountDisplayPrimary,
                                role: .amountCompact
                            )
                        } else {
                            // Non-sat unit: render in its own currency, no sats flip.
                            AmountLockup(
                                parts: AmountParts.parse(CurrencyAmount(
                                    value: amount,
                                    currency: CurrencyRegistry.currency(forMintUnit: request.unit)
                                ).formatted()),
                                role: .amountCompact,
                                value: Double(amount)
                            )
                        }
                    }

                    deliveryStatus(for: request)

                    if let regenerationError {
                        InlineNotice(message: regenerationError, severity: .error)
                    }

                    VStack(spacing: 0) {
                        // Only the ecash NUT-18 request can re-mint its Mint /
                        // Amount in place (that's what `regenerate` rebuilds).
                        // Quote-backed rails (BOLT12 offer, etc.) are read-only
                        // here until the unified editable detail lands.
                        if request.rail == .ecash {
                            editableRow(
                                icon: "bitcoinsign.bank.building",
                                label: "Mint",
                                value: mintDisplayValue(for: request),
                                action: { showMintPicker = true }
                            )
                            editableRow(
                                icon: "bitcoinsign",
                                label: "Amount",
                                value: amountDisplayValue(for: request),
                                action: { showAmountPicker = true }
                            )
                        } else {
                            detailRow(
                                icon: "bitcoinsign.bank.building",
                                label: "Mint",
                                value: mintDisplayValue(for: request)
                            )
                            detailRow(
                                icon: "bitcoinsign",
                                label: "Amount",
                                value: amountDisplayValue(for: request)
                            )
                        }
                        if unitEditable(for: request) {
                            editableRow(
                                icon: "creditcard",
                                label: "Unit",
                                value: request.unit.uppercased(),
                                action: { showUnitPicker = true }
                            )
                        } else {
                            detailRow(icon: "creditcard", label: "Unit", value: request.unit.uppercased())
                        }
                        detailRow(
                            icon: "calendar",
                            label: "Created",
                            value: request.createdAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button(action: { copy(request.encoded) }) {
                    Text("Copy")
                }
                .glassButton()

                // "New Request" rotates a fresh NUT-18 request; it's meaningless
                // for a quote-backed reusable offer (the offer is the artifact).
                if request.rail == .ecash {
                    Button(action: { regenerate() }) {
                        Text("New Request")
                    }
                    .glassButton()
                    .accessibilityHint("Generates a fresh Cashu Request and rotates the QR")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private var statusBadge: some View {
        Group {
            if paymentCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(paymentCount == 1 ? "1 payment received" : "\(paymentCount) payments received")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    Text("Waiting for payment…")
                }
                .font(.subheadline)
                .foregroundStyle(.orange)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: paymentCount)
    }

    @ViewBuilder
    private func deliveryStatus(for request: CashuRequest) -> some View {
        if paymentCount > 0 || request.rail != .ecash {
            statusBadge
        } else if let notice = CashuRequestNostrReadiness.current().deliveryNotice {
            InlineNotice(
                message: notice.message,
                title: notice.title,
                severity: .caution
            )
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        } else {
            statusBadge
        }
    }

    // MARK: - Detail rows

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
        }
        .font(.subheadline)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }

    private func editableRow(icon: String, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "pencil")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            .font(.subheadline)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edits the \(label.lowercased())")
    }

    // MARK: - Value formatters

    private func mintDisplayValue(for request: CashuRequest) -> String {
        guard let mintUrl = request.mints.first else { return "Any mint" }
        if let mint = walletManager.mints.first(where: { $0.url == mintUrl }) {
            return mint.name
        }
        return URL(string: mintUrl)?.host ?? mintUrl
    }

    private func amountDisplayValue(for request: CashuRequest) -> String {
        guard let amount = request.amount, amount > 0 else { return "Any" }
        return formatAmount(amount, unit: request.unit)
    }

    private func formatAmount(_ amount: UInt64, unit: String) -> String {
        if unit.lowercased() == "sat" {
            return AmountFormatter.sats(amount, useBitcoinSymbol: settings.useBitcoinSymbol)
        }
        return CurrencyAmount(
            value: amount,
            currency: CurrencyRegistry.currency(forMintUnit: unit)
        ).formatted()
    }

    // MARK: - Actions

    private func copy(_ s: String) {
        UIPasteboard.general.string = s
        HapticFeedback.selection()
        ConfirmationToast.show("Copied Cashu request")
    }

    /// Re-encodes the displayed request with optional overrides, keeping the same
    /// NUT-18 id. Defaults preserve the current request's params. Amount / mint
    /// edits re-parameterize the one live request in place — payments to any
    /// previously shared copy still land on this row, and history never grows a
    /// second entry for the same receive intent.
    private func regenerate(amount: UInt64?? = nil, unit: String? = nil, mints: [String]? = nil) {
        HapticFeedback.selection()
        guard let existing = request else { return }
        let readiness = CashuRequestNostrReadiness.current()
        guard let configuration = readiness.requestConfiguration else {
            regenerationError = readiness.recoveryMessage
            return
        }
        let nextMints = mints ?? existing.mints
        // Validate the unit against the (possibly newly chosen) mint: keep the
        // requested/existing unit when that mint supports it, else fall back to
        // the mint's default. Covers both explicit unit edits and mint changes.
        let requestedUnit = unit ?? existing.unit
        let nextUnit = walletManager.mints.first { $0.url == nextMints.first }?
            .resolvedUnit(requestedUnit) ?? requestedUnit
        let nextAmount: UInt64?
        switch amount {
        case .some(let inner):
            nextAmount = inner
        case .none:
            // Preserve the fixed amount only while the unit is unchanged — a
            // stored number means different things across units (500 sat is not
            // $5.00), so a unit change resets it to "Any" and the user re-enters
            // in the new unit.
            nextAmount = (nextUnit == existing.unit) ? existing.amount : nil
        }
        do {
            let encoded = try PaymentRequestBuilder.build(
                id: existing.id,
                amount: nextAmount,
                unit: nextUnit,
                mints: nextMints,
                description: existing.memo,
                nostrPubkeyHex: configuration.publicKeyHex,
                relays: configuration.relays
            )
            store.update(id: existing.id, amount: nextAmount, unit: nextUnit, mints: nextMints, encoded: encoded)
            regenerationError = nil
        } catch {
            AppLogger.wallet.error("Could not regenerate request: \(String(describing: error))")
            regenerationError = "Couldn't update the request. Please try again."
        }
    }

    /// The tracked mint backing a request (nil for "any mint" / untracked).
    private func requestMint(for request: CashuRequest) -> MintInfo? {
        guard let mintUrl = request.mints.first else { return nil }
        return walletManager.mints.first { $0.url == mintUrl }
    }

    /// The Unit row is editable only for an ecash request whose mint advertises
    /// more than one unit.
    private func unitEditable(for request: CashuRequest) -> Bool {
        request.rail == .ecash && (requestMint(for: request)?.supportsMultipleUnits ?? false)
    }
}

/// Tracks the request-specific transaction records that existed when its detail
/// opened and returns only payments linked afterwards. Wallet balance changes
/// are intentionally outside this correlation boundary.
struct CashuRequestPaymentObservation {
    private var observedTransactionIds: Set<String>

    init(existingPayments: [CashuRequestPayment]) {
        observedTransactionIds = Set(existingPayments.map(\.transactionId))
    }

    mutating func newlyLinkedPayment(
        in currentPayments: [CashuRequestPayment]
    ) -> CashuRequestPayment? {
        let payment = currentPayments.last {
            !observedTransactionIds.contains($0.transactionId)
        }
        observedTransactionIds = Set(currentPayments.map(\.transactionId))
        return payment
    }
}
