import SwiftUI
import UIKit

struct CashuRequestDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var store = CashuRequestStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var nostr = NostrService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onClose: (() -> Void)?
    let showsNavigationHeader: Bool

    @State private var requestId: String
    @State private var showMintPicker = false
    @State private var showAmountPicker = false
    @State private var showUnitPicker = false
    @State private var paymentObservation: CashuRequestPaymentObservation
    @State private var regenerationError: String?
    /// Amount of the payment that just landed, for the shared success screen.
    @State private var receivedAmount: UInt64?
    @State private var showPaymentSuccess = false
    /// VoiceOver Share action for the QR: ShareLink can't be invoked
    /// imperatively, so the accessibility action presents the share sheet.
    @State private var showShareSheet = false
    @State private var nfcReceive = NFCReceiveCoordinator()
    @State private var contactlessAvailable = false
    @State private var nfcPaymentCountAtStart = 0

    init(request: CashuRequest, onClose: (() -> Void)? = nil, showsNavigationHeader: Bool = true) {
        self._requestId = State(initialValue: request.id)
        self._paymentObservation = State(
            initialValue: CashuRequestPaymentObservation(existingPayments: request.receivedPayments)
        )
        self.onClose = onClose
        self.showsNavigationHeader = showsNavigationHeader
    }

    private var request: CashuRequest? {
        store.request(withId: requestId)
    }

    private var paymentCount: Int {
        request?.receivedPayments.count ?? 0
    }

    private var monitoredQuoteID: String? {
        scenePhase == .active && walletManager.isRuntimeReady && !showPaymentSuccess
            ? request?.quoteId : nil
    }

    var body: some View {
        Group {
            if showPaymentSuccess {
                paymentSuccessView
                    .transition(.opacity)
            } else if let request {
                content(request: request)
                    // Fast exit: when the payment lands, the request face
                    // clears quickly so the success terminal's staged check
                    // owns the moment.
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.animation(.easeInOut(duration: 0.2))
                    ))
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
            if showsNavigationHeader {
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
        .onChange(of: request?.receivedPayments) {
            nfcReceive.stop()
            presentNextPayment()
        }
        .onChange(of: showPaymentSuccess) {
            presentNextPayment()
        }
        .onChange(of: nfcReceive.receivedAmount) {
            // CDK may credit the wallet without returning an attributable tx ID.
            // Still show the actual redeemed amount in that case.
            if let amount = nfcReceive.receivedAmount, !showPaymentSuccess,
               paymentCount == nfcPaymentCountAtStart {
                receivedAmount = amount
                showPaymentSuccess = true
            }
        }
        .onChange(of: nfcReceive.reviewPayment) { presentNextPayment() }
        .task(id: monitoredQuoteID) {
            guard let quoteID = monitoredQuoteID else { return }
            await walletManager.monitorDisplayedMintQuote(quoteID: quoteID, homeHaptic: false)
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                contactlessAvailable = await NFCReceiveCardSession.isAvailable
            } else if scenePhase == .background {
                nfcReceive.stop()
            }
        }
        .onChange(of: request) { nfcReceive.stop() }
        .onDisappear { nfcReceive.stop() }
        .fullScreenCover(item: Binding(
            get: { nfcReceive.reviewPayment },
            set: { if $0 == nil { nfcReceive.dismissReview() } }
        )) { pending in
            ReceiveTokenDetailView(
                tokenString: pending.token,
                onComplete: { nfcReceive.dismissReview() },
                claim: { try await walletManager.claimPendingReceiveToken(pending) },
                secondaryActionTitle: "Review Later",
                onSecondaryAction: { nfcReceive.dismissReview() }
            )
            .environmentObject(walletManager)
            .canvasSheetBackground()
        }
        .compactBottomSheetSurface()
    }

    /// Keep the current receipt stable; payments arriving during it are picked
    /// up after Done without replaying any previously acknowledged payment.
    private func presentNextPayment() {
        guard !showPaymentSuccess, let request else { return }
        if let reviewed = nfcReceive.reviewPayment {
            // The review screen owns this payment's success. Keep other
            // concurrent receipts queued until that screen closes.
            let saved = walletManager.walletStore.loadSavedTokens()
            for payment in request.receivedPayments where saved[payment.transactionId] == reviewed.token {
                paymentObservation.acknowledge(transactionId: payment.transactionId)
            }
            return
        }
        guard let payment = paymentObservation.newlyLinkedPayment(in: request.receivedPayments) else { return }
        receivedAmount = payment.amount
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
                if request?.reusable == true {
                    showPaymentSuccess = false
                } else if let onClose {
                    onClose()
                } else {
                    dismiss()
                }
            },
            onRetry: {}
        )
    }

    private var paymentSuccessRows: [PaymentStatusView.DetailRow] {
        var rows: [PaymentStatusView.DetailRow] = []
        if let receivedAmount {
            rows.append(.init(
                label: "Amount",
                value: request.map { formatAmount(receivedAmount, unit: $0.unit) }
                    ?? AmountFormatter.sats(receivedAmount, useBitcoinSymbol: settings.useBitcoinSymbol)
            ))
        }
        if let request {
            rows.append(.init(
                label: "Mint",
                value: mintDisplayValue(for: request)
            ))
        }
        return rows
    }

    @ViewBuilder
    private func content(request: CashuRequest) -> some View {
        VStack(spacing: 0) {
            PaymentDetailContent { qrSize in
                requestQRCode(request, size: qrSize)
            } details: {
                VStack(spacing: 16) {
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

                    contactlessReceive(request: request)

                    if let regenerationError {
                        InlineNotice(message: regenerationError, severity: .error)
                    }

                    VStack(spacing: 0) {
                        if request.rail == .ecash {
                            editableRow(label: "Mint", value: mintDisplayValue(for: request),
                                        action: { showMintPicker = true })
                        } else {
                            detailRow(label: "Mint", value: mintDisplayValue(for: request))
                        }
                        if let description = request.displayDescription {
                            DescriptionDetailRow(description: description)
                        }
                        // Only the ecash NUT-18 request can re-mint its Mint /
                        // Amount in place (that's what `regenerate` rebuilds).
                        // Quote-backed rails (BOLT12 offer, etc.) are read-only
                        // here until the unified editable detail lands.
                        if request.rail == .ecash {
                            editableRow(label: "Amount", value: amountDisplayValue(for: request),
                                        action: { showAmountPicker = true })
                        } else if request.amount == nil {
                            detailRow(label: "Amount", value: amountDisplayValue(for: request))
                        }
                        if unitEditable(for: request) {
                            editableRow(
                                label: "Unit",
                                value: request.unit.uppercased(),
                                action: { showUnitPicker = true }
                            )
                        } else if request.rail == .ecash {
                            detailRow(label: "Unit", value: request.unit.uppercased())
                        }
                        detailRow(
                            label: "Created",
                            value: request.createdAt.formatted(date: .abbreviated, time: .shortened)
                        )
                        if request.totalReceived > 0 {
                            detailRow(
                                label: "Total received",
                                value: formatAmount(request.totalReceived, unit: request.unit)
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            let actionLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            actionLayout {
                Button(action: { copy(request.encoded) }) {
                    Text("Copy")
                }
                .flatSheetSecondaryButton()

                // "New Request" rotates a fresh NUT-18 request; it's meaningless
                // for a quote-backed reusable offer (the offer is the artifact).
                if request.rail == .ecash {
                    Button(action: { regenerate() }) {
                        Text("New Request")
                    }
                    .flatSheetSecondaryButton()
                    .accessibilityHint("Generates a fresh Cashu Request and rotates the QR")
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func contactlessReceive(request: CashuRequest) -> some View {
        if contactlessAvailable && (request.rail == .ecash || request.receivedPayments.isEmpty) {
            VStack(spacing: 8) {
                Button {
                    nfcPaymentCountAtStart = paymentCount
                    nfcReceive.start(request: request, walletManager: walletManager)
                } label: {
                    if nfcReceive.phase == .redeeming {
                        HStack {
                            ProgressView()
                            Text("Securing ecash…")
                        }
                    } else {
                        Label("Receive by Tap", systemImage: "wave.3.right")
                    }
                }
                .flatSheetSecondaryButton()
                .disabled(nfcReceive.isBusy || !NFCReceivePayment.canPresent(request) || !walletManager.isRuntimeReady)
                .accessibilityIdentifier("cashu.receive.contactless")
                .accessibilityHint("Hold this iPhone near the payer's device to receive ecash")
                if (request.amount ?? 0) == 0 {
                    Text("Set an amount to receive by tap.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Hold this iPhone near the payer's device. You'll review payments from new mints before claiming.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let message = nfcReceive.message {
                    InlineNotice(message: message, severity: .caution)
                }
            }
        }
    }

    private var statusBadge: some View {
        Group {
            if paymentCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(paymentCount == 1 ? "1 payment received" : "\(paymentCount) payments received")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    Text("Waiting for payment…")
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
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

    private func requestQRCode(_ request: CashuRequest, size: CGFloat) -> some View {
        QRCodeView(
            content: request.encoded,
            showControls: false,
            staticOnly: true,
            onCopy: { copy(request.encoded) },
            onShare: { showShareSheet = true }
        )
        .accessibilityIdentifier("cashu.history.payment-code")
        .frame(width: size, height: size)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
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
    }

    // MARK: - Detail rows

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
        }
        .font(.subheadline)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func editableRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
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
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value)
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

    /// Amount/mint edits reuse the intent within one currency. Changing unit
    /// starts a new request while preserving the old code and its payments.
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
            let updated = try store.update(
                id: existing.id, amount: nextAmount, unit: nextUnit, mints: nextMints
            ) { id in
                try PaymentRequestBuilder.build(
                    id: id,
                    amount: nextAmount,
                    unit: nextUnit,
                    mints: nextMints,
                    description: existing.memo,
                    nostrPubkeyHex: configuration.publicKeyHex,
                    relays: configuration.relays
                )
            }
            if let updated, updated.id != requestId {
                paymentObservation = CashuRequestPaymentObservation(existingPayments: updated.receivedPayments)
                requestId = updated.id
            }
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

    mutating func acknowledge(transactionId: String) {
        observedTransactionIds.insert(transactionId)
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
