import SwiftUI
import Cdk

private struct ReceiveRequestFailure {
    enum Retry {
        case setReusableAmount(UInt64)
        case amountlessOffer(forceNew: Bool, unit: String?)
        case create(method: PaymentMethodKind, amountless: Bool, forceNew: Bool)

        var method: PaymentMethodKind {
            switch self {
            case .setReusableAmount, .amountlessOffer:
                return .bolt12
            case .create(let method, _, _):
                return method
            }
        }
    }

    let title: String
    let message: String
    let retry: Retry
}

struct ReceiveLightningView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var amountString = ""
    @State private var selectedMethod: PaymentMethodKind = .bolt11
    /// BOLT12 only: when true the offer is amountless (sender chooses).
    @State private var isAmountless = false
    @State private var showMethodPicker = false
    @State private var mintQuote: MintQuoteInfo?
    @State private var isCreatingRequest = false
    @State private var isMinting = false
    @State private var isCheckingPayment = false
    @State private var isPaid = false
    @State private var requestFailure: ReceiveRequestFailure?
    @State private var showMintPicker = false
    /// Reusable BOLT12 offer: drives the Amount-row pencil → amount picker sheet.
    @State private var showReusableAmountPicker = false
    /// VoiceOver Share action for the QR cards: ShareLink can't be invoked
    /// imperatively, so the accessibility action presents the share sheet.
    @State private var showShareSheet = false
    @State private var qrShareText = ""
    @State private var quoteStatusTask: Task<Void, Never>?
    @State private var expiryTimeRemaining: TimeInterval = 0
    @State private var expiryTimer: Timer?
    @State private var isExpired = false
    @State private var onchainObservation: OnchainPaymentObservation?
    @State private var quoteCreatedAt: Date?
    @State private var monitoredQuoteId: String?
    /// On-chain quotes abandoned via "Use new address" — a payment may already
    /// be racing toward the old address, so keep checking them for the life of
    /// the sheet (Android parity). Mint-status checks only; no explorer polling.
    @State private var abandonedOnchainQuoteIds: [String] = []
    @State private var abandonedQuoteTask: Task<Void, Never>?

    // Multi-unit mint: the user's explicit unit pick for this receive (nil = the
    // mint's default mintable unit), plus the picker flag.
    @State private var selectedReceiveUnit: String?
    @State private var showUnitPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if let failure = requestFailure {
                    requestFailureView(failure)
                        .transition(.opacity)
                } else if isPaid, let quote = mintQuote {
                    // Payment received → the same full-screen success the pay/send
                    // flows use, replacing the (now-useless) QR entirely.
                    receiveSuccessView(quote: quote)
                        .transition(.opacity)
                } else if let quote = mintQuote {
                    requestDisplayView(quote: quote)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            // Fast exit: when the payment lands, the QR clears
                            // quickly so the success terminal's staged check
                            // owns the moment.
                            removal: .opacity.animation(.easeInOut(duration: 0.2))
                        ))
                } else if isCreatingRequest && (isAmountlessOffer || selectedMethod == .onchain) {
                    // Auto-creating requests (amountless BOLT12 or onchain) have no
                    // keypad to host the spinner — show a dedicated overlay.
                    creatingOverlay
                        .transition(.opacity)
                } else {
                    amountInputView
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.smooth(duration: 0.3), value: mintQuote != nil)
            .animation(.smooth(duration: 0.3), value: isPaid)
            .animation(.smooth(duration: 0.3), value: requestFailure != nil)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(screenTitle)
            // No nav bar chrome — the title floats over the black canvas. This
            // kills the secondary gray bar. Content has enough top padding to
            // clear the safe-area inset so nothing overlaps.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }

                if requestFailure == nil, let quote = mintQuote, !isPaid {
                    ToolbarItem(placement: .topBarTrailing) {
                        if quote.paymentMethod == .bolt12 || quote.paymentMethod == .onchain {
                            // Overflow menu keeps Share + New quieter than a
                            // dedicated share glyph + second bottom CTA
                            // (Android ⋮ parity). On-chain mirrors BOLT12's
                            // "new artifact" item with a fresh address.
                            Menu {
                                ShareLink(item: quote.request) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                if quote.paymentMethod == .bolt12 {
                                    Button {
                                        createNewAmountlessOffer(unit: quote.unit)
                                    } label: {
                                        Label(
                                            isCreatingRequest ? "Creating…" : "New reusable invoice",
                                            systemImage: "arrow.2.squarepath"
                                        )
                                    }
                                    .disabled(isCreatingRequest)
                                } else {
                                    Button {
                                        trackAbandonedOnchainQuote()
                                        createRequest(method: .onchain, amountless: false, forceNew: true)
                                    } label: {
                                        Label(
                                            isCreatingRequest ? "Creating…" : "New address",
                                            systemImage: "arrow.clockwise"
                                        )
                                    }
                                    .disabled(isCreatingRequest)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .toolbarIconTapTarget()
                            }
                            .accessibilityLabel("More options")
                        } else {
                            ShareLink(item: quote.request) {
                                Image(systemName: "square.and.arrow.up")
                                    .toolbarIconTapTarget()
                            }
                            .accessibilityLabel("Share request")
                        }
                    }
                } else if requestFailure == nil && shouldShowMethodPicker && !isCreatingRequest {
                    // Liquid Glass method switcher. On iOS 26 the toolbar renders
                    // bar buttons as glass, so this reads as a sibling of the
                    // close button by construction. Replaces the old inline
                    // `methodChip` text affordance.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            HapticFeedback.selection()
                            showMethodPicker = true
                        } label: {
                            Image(systemName: selectedOption.navSymbol)
                                .contentTransition(.symbolEffect(.replace))
                                .toolbarIconTapTarget()
                        }
                        // Both reusable options share title + glyph, so the
                        // descriptor is what tells "fixed" from "any amount".
                        .accessibilityLabel("Receive method: \(selectedOption.friendlyTitle), \(selectedOption.friendlyDescriptor)")
                        .accessibilityHint("Opens the receive method picker")
                    }
                }

                // Unit selector — only in the amount-entry state, for a mint that
                // can mint more than one unit (on-chain is amountless, no unit).
                // Declared after the method button so it sits to its right.
                if requestFailure == nil, mintQuote == nil, !isCreatingRequest, selectedMethod != .onchain,
                   let mint = walletManager.activeMint, mint.supportsMultipleMintUnits {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            HapticFeedback.selection()
                            showUnitPicker = true
                        } label: {
                            Text(effectiveUnit.uppercased())
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityLabel("Unit: \(effectiveUnit.uppercased())")
                        .accessibilityHint("Choose the unit to mint")
                    }
                }
            }
            .sheet(isPresented: $showMintPicker) {
                MintSelectorSheet(selectedMint: $walletManager.activeMint)
                    .environmentObject(walletManager)
            }
            .sheet(isPresented: $showMethodPicker) {
                MethodPickerSheet(
                    selectedOption: selectedOption,
                    options: availableMethodOptions,
                    onSelect: { applyMethodOption($0) }
                )
            }
            .sheet(isPresented: $showUnitPicker) {
                UnitSelectorSheet(
                    units: walletManager.activeMint?.mintUnits ?? ["sat"],
                    selectedUnit: effectiveUnit,
                    onSelect: selectReceiveUnit
                )
            }
            .onAppear {
                syncSelectedMethodWithActiveMint()
            }
            .onChange(of: walletManager.activeMint?.id) {
                syncSelectedMethodWithActiveMint()
            }
            .onChange(of: selectedMethod) {
                requestFailure = nil
                onchainObservation = nil
                // `isAmountless` is owned by the picked `ReceiveMethodOption` now
                // (set in `applyMethodOption`); don't recompute it from the empty
                // field here — that would fight the user's explicit picker choice.
            }
            .onChange(of: entryUnit) { oldUnit, newUnit in
                // Only the sats↔fiat display flip re-expresses the typed string.
                // A non-sat mint unit is entered directly and must not be
                // reinterpreted through the sat price.
                guard isSatReceive else { return }
                // Flip (or a price load that changes the effective unit): carry
                // the typed amount across, converted, so it stays equivalent.
                amountString = AmountFormatter.entryConverted(raw: amountString, from: oldUnit, to: newUnit)
            }
            .onDisappear {
                quoteStatusTask?.cancel()
                expiryTimer?.invalidate()
                quoteStatusTask = nil
                expiryTimer = nil
                monitoredQuoteId = nil
                abandonedQuoteTask?.cancel()
                abandonedQuoteTask = nil
            }
        }
        .accessibilityIdentifier("receive-lightning-screen")
        .compactBottomSheetSurface()
    }

    // MARK: - Computed Properties

    private var availableMintMethods: [PaymentMethodKind] {
        let methods = walletManager.activeMint?.supportedMintMethods ?? [.bolt11]
        let orderedMethods = PaymentMethodKind.allCases.filter { methods.contains($0) }
        return orderedMethods.isEmpty ? [.bolt11] : orderedMethods
    }

    /// Picker rows: BOLT12 fans out into fixed + any-amount, so a BOLT12-only
    /// mint still yields two options (and therefore a visible picker).
    private var availableMethodOptions: [ReceiveMethodOption] {
        ReceiveMethodOption.options(for: availableMintMethods)
    }

    /// The option mirroring the current (selectedMethod, isAmountless) state —
    /// drives the picker highlight and the nav-bar switcher.
    private var selectedOption: ReceiveMethodOption {
        ReceiveMethodOption.current(method: selectedMethod, isAmountless: isAmountless)
    }

    private var shouldShowMethodPicker: Bool {
        // Count options, not methods: a BOLT12-only mint is one method but two
        // options, and the in-screen toggle that used to disambiguate is gone.
        availableMethodOptions.count > 1
    }

    private var screenTitle: String {
        let method = requestFailure?.retry.method ?? mintQuote?.paymentMethod
        guard let method else { return "Receive" }

        switch method {
        case .bolt11:
            return "Lightning Invoice"
        case .bolt12:
            return "Reusable Invoice"
        case .onchain:
            return "Bitcoin Address"
        }
    }

    private func requestFailureTitle(for method: PaymentMethodKind) -> String {
        method == .onchain ? "Couldn't Create Address" : "Couldn't Create Invoice"
    }

    private func requestFailureView(_ failure: ReceiveRequestFailure) -> some View {
        PaymentStatusView(
            details: [],
            phase: .failure(message: failure.message),
            failureTitle: failure.title,
            onDone: { requestFailure = nil },
            onRetry: { retryRequest(failure.retry) }
        )
    }

    private func retryRequest(_ retry: ReceiveRequestFailure.Retry) {
        requestFailure = nil
        switch retry {
        case .setReusableAmount(let amount):
            setReusableOfferAmount(amount)
        case .amountlessOffer(let forceNew, let unit):
            loadOrCreateAmountlessOffer(forceNew: forceNew, unit: unit)
        case .create(let method, let amountless, let forceNew):
            createRequest(method: method, amountless: amountless, forceNew: forceNew)
        }
    }

    /// The unit the keypad is entering in: fiat only when fiat is primary AND a
    /// price is loaded, else sats (mirrors `CurrencyAmountDisplay.effectivePrimary`).
    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    /// Satoshis represented by the typed amount, interpreted per `entryUnit`.
    /// Zero outside sat mode (a non-sat amount has no sat value).
    private var amountSats: UInt64 {
        guard isSatReceive else { return 0 }
        return AmountFormatter.entrySats(raw: amountString, unit: entryUnit)
    }

    // MARK: - Active mint unit

    /// The unit this receive will mint into — the user's pick when the mint can
    /// mint it, otherwise the mint's default mintable unit. Auto-resets when the
    /// active mint changes to one that can't mint the selection.
    private var effectiveUnit: String {
        walletManager.activeMint?.resolvedMintUnit(selectedReceiveUnit) ?? "sat"
    }

    private var isSatReceive: Bool { effectiveUnit.lowercased() == "sat" }
    private var receiveUnitCurrency: any Currency { CurrencyRegistry.currency(forMintUnit: effectiveUnit) }
    private var receiveUnitDecimals: Int { receiveUnitCurrency.decimals }

    /// The amount actually minted, in the active unit's base units (sats for
    /// sat; cents for eur/usd; integer for a custom unit).
    private var amountBaseUnits: UInt64 {
        isSatReceive ? amountSats : AmountFormatter.entryBaseUnits(raw: amountString, decimals: receiveUnitDecimals)
    }

    /// Big-number display for a non-sat entry, formatted in the active unit.
    private var receiveUnitEntryDisplay: String {
        CurrencyAmount(value: amountBaseUnits, currency: receiveUnitCurrency).formatted()
    }

    private func selectReceiveUnit(_ unit: String) {
        selectedReceiveUnit = unit
        // The typed amount's meaning changes with the unit — clear it.
        amountString = ""
        requestFailure = nil
        HapticFeedback.selection()
    }

    /// Format a mint-quote amount in its own unit: sats keep the existing style,
    /// other units render via their `Currency` (e.g. "€5.00").
    private func formatQuoteAmount(_ amount: UInt64, unit: String) -> String {
        unit.lowercased() == "sat"
            ? AmountFormatter.sats(amount, useBitcoinSymbol: settings.useBitcoinSymbol)
            : CurrencyAmount(value: amount, currency: CurrencyRegistry.currency(forMintUnit: unit)).formatted()
    }

    /// The one path that submits no amount: a BOLT12 offer with "Any amount" lit.
    /// Everything else (BOLT11, on-chain, a BOLT12 offer with a typed amount)
    /// requires a positive value.
    private var isAmountlessOffer: Bool {
        selectedMethod == .bolt12 && isAmountless
    }

    private var canCreateRequest: Bool {
        guard !isCreatingRequest else { return false }
        if isAmountlessOffer { return true }
        return amountBaseUnits > 0
    }

    // MARK: - Amount Input View

    private var amountInputView: some View {
        VStack(spacing: 0) {
            Spacer()

            amountHero

            Spacer()

            // Under the amount, over the keypad — the same slot the send flows use.
            if let mint = walletManager.activeMint {
                mintSelector(mint: mint)
                    // Aligned to the number pad below, not the CTA.
                    .padding(.horizontal, NumberPadMetrics.gutter)
                    .padding(.bottom, 8)
            }

            Group {
                if isSatReceive {
                    NumberPadAmountInput(amountString: $amountString, unit: entryUnit)
                } else {
                    NumberPadAmountInput(amountString: $amountString, decimals: receiveUnitDecimals)
                }
            }
            .padding(.horizontal, NumberPadMetrics.gutter)
            .onChange(of: amountString) { _, newValue in
                // Typing a digit takes over from the amountless offer.
                if isAmountless && !newValue.isEmpty { isAmountless = false }
            }

            Button(action: createRequest) {
                if isCreatingRequest {
                    ProgressView()
                } else {
                    Text(selectedMethod.createActionTitle)
                }
            }
            // Quiet tonal fill, matching Android's gray keypad CTA — the white
            // ink stays reserved for the pay-confirm commit.
            .flatSheetSecondaryButton()
            .accessibilityIdentifier("receive-lightning-create-request")
            .disabled(!canCreateRequest)
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
    }

    private var amountHero: some View {
        VStack(spacing: 12) {
            if selectedMethod == .onchain {
                methodBadge
                    .transition(.opacity)
            }

            if isSatReceive {
                CurrencyAmountDisplay(
                    sats: amountSats,
                    primary: $settings.amountDisplayPrimary,
                    entryRaw: amountString
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Request amount: \(amountString.isEmpty ? "0" : amountString) sats")
            } else {
                // Non-sat mint unit: show it directly, no BTC-price flip.
                AmountLockup(
                    parts: AmountParts.parse(receiveUnitEntryDisplay),
                    role: .amountHero,
                    value: Double(amountBaseUnits),
                    accessibilityPrefix: "Request amount"
                )
            }
        }
        .animation(.snappy, value: selectedMethod)
    }

    /// All-caps "ON-CHAIN" label sitting above the amount. On-chain receive is
    /// unusual enough to warrant the callout; Lightning and reusable invoices
    /// rely on the nav-bar glyph alone, so this only renders for on-chain.
    private var methodBadge: some View {
        Text(selectedMethod.displayName.uppercased())
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("Method: \(selectedMethod.friendlyTitle)")
    }

    /// Shown while auto-creating a request (amountless BOLT12 or onchain address),
    /// between the picker dismissing and the QR sliding in.
    private var creatingOverlay: some View {
        let label = selectedMethod == .onchain ? "Generating address" : "Creating reusable invoice"
        return VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    // MARK: - Mint Selector

    private func mintSelector(mint: MintInfo) -> some View {
        MintSelectorRow(
            direction: .destination,
            mint: mint,
            balanceText: formatBalance(mint.balance),
            showsBalance: true,
            // One mint means nothing to choose between, so the row drops its
            // chevron and stops opening a picker that would list a single row.
            onChooseMint: walletManager.mints.count > 1 ? { showMintPicker = true } : nil
        )
    }

    // MARK: - Request Display View

    /// Routes the result screen by rail. Every reusable BOLT12 offer (amountless
    /// or fixed) gets the calm, Cashu-Request-style metadata layout; BOLT11 and
    /// on-chain keep the amount-hero + expiry-countdown layout in
    /// `standardRequestDisplayView`.
    @ViewBuilder
    private func requestDisplayView(quote: MintQuoteInfo) -> some View {
        if quote.paymentMethod == .bolt12 {
            reusableOfferDisplayView(quote: quote)
                .onAppear {
                    persistReceiveIntent(for: quote)
                    startQuoteMonitoring(for: quote)
                }
                .onChange(of: mintQuote?.id) { _, _ in
                    if let quote = mintQuote {
                        persistReceiveIntent(for: quote)
                        startQuoteMonitoring(for: quote)
                    }
                }
        } else {
            standardRequestDisplayView(quote: quote)
        }
    }

    /// Cashu-Request-style screen for a reusable BOLT12 offer: QR → (amount hero,
    /// if fixed) → status → read-only Mint / editable Amount / Created rows → Copy.
    /// Share + New live in the toolbar overflow menu so primary chrome stays calm.
    /// Editing the Amount row mints a fresh fixed-amount offer (or reverts to the
    /// amountless one) — that's how a fixed-amount reusable invoice is made.
    /// No expiry countdown, no rotate affordance.
    private func reusableOfferDisplayView(quote: MintQuoteInfo) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    QRCodeView(
                        content: quote.request,
                        showControls: false,
                        staticOnly: true,
                        onCopy: { copyRequest(quote.request) },
                        onShare: { shareQuoteRequest(quote.request) }
                    )
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 8)
                        .contextMenu {
                            Button(action: { copyRequest(quote.request) }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            ShareLink(item: quote.request) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                createNewAmountlessOffer(unit: quote.unit)
                            } label: {
                                Label("New reusable invoice", systemImage: "arrow.2.squarepath")
                            }
                            .disabled(isCreatingRequest)
                        }
                        .sheet(isPresented: $showShareSheet) {
                            ShareSheet(items: [qrShareText])
                        }

                    if let amount = quote.amount, amount > 0 {
                        if quote.unit.lowercased() == "sat" {
                            CurrencyAmountDisplay(
                                sats: amount,
                                primary: $settings.amountDisplayPrimary,
                                role: .amountCompact
                            )
                            .accessibilityLabel("Offer amount: \(amount) sats")
                        } else {
                            AmountLockup(
                                parts: AmountParts.parse(formatQuoteAmount(amount, unit: quote.unit)),
                                role: .amountCompact,
                                value: Double(amount),
                                accessibilityPrefix: "Offer amount"
                            )
                        }
                    }

                    statusBadge

                    VStack(spacing: 0) {
                        detailRow(
                            label: "Mint",
                            value: reusableMintDisplayValue
                        )
                        editableRow(
                            label: "Amount",
                            value: quote.amount.flatMap { $0 > 0 ? formatQuoteAmount($0, unit: quote.unit) : nil } ?? "Any",
                            action: { showReusableAmountPicker = true }
                        )
                        if let created = quote.createdAt {
                            detailRow(
                                label: "Created",
                                value: created.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal)
            }

            Button(action: { copyRequest(quote.request) }) {
                Text(copyButtonTitle(for: quote))
            }
            .flatSheetSecondaryButton()
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showReusableAmountPicker) {
            CashuRequestAmountPickerSheet(
                currentAmount: quote.amount,
                unit: quote.unit,
                onSelect: { setReusableOfferAmount($0) }
            )
        }
    }

    /// Friendly name of the offer's issuing mint for the read-only Mint row. A
    /// BOLT12 offer is bound to one mint, so this never shows "Any mint" in
    /// practice — the fallback only guards a missing active mint.
    private var reusableMintDisplayValue: String {
        guard let mint = walletManager.activeMint else { return "Any mint" }
        return mint.name.isEmpty ? extractMintHost(mint.url) : mint.name
    }

    /// Full-screen success shown once payment is detected — the exact same
    /// `PaymentStatusView` the pay/send flows use, so a received payment reads
    /// identically to a sent one (checkmark → title → detail block → Done).
    /// Stays until the user taps Done; the mint/refresh runs in the background.
    private func receiveSuccessView(quote: MintQuoteInfo) -> some View {
        PaymentStatusView(
            details: receiveSuccessRows(quote: quote),
            phase: .success,
            successTitle: "Payment Received!",
            onDone: { dismiss() },
            onRetry: {}
        )
    }

    private func receiveSuccessRows(quote: MintQuoteInfo) -> [PaymentStatusView.DetailRow] {
        var rows: [PaymentStatusView.DetailRow] = []
        if let amount = quote.amount {
            rows.append(.init(
                label: "Amount",
                value: formatQuoteAmount(amount, unit: quote.unit)
            ))
        }
        if let mint = walletManager.activeMint {
            rows.append(.init(
                label: "Mint",
                value: extractMintHost(mint.url)
            ))
        }
        return rows
    }

    private func standardRequestDisplayView(quote: MintQuoteInfo) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    QRCodeView(
                        content: quote.request,
                        showControls: false,
                        staticOnly: true,
                        onCopy: { copyRequest(quote.request) },
                        onShare: { shareQuoteRequest(quote.request) }
                    )
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 8)
                        .contextMenu {
                            Button(action: { copyRequest(quote.request) }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            ShareLink(item: quote.request) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                        .sheet(isPresented: $showShareSheet) {
                            ShareSheet(items: [qrShareText])
                        }

                    amountSummary(for: quote)

                    statusBadge

                    if !isPaid && !isExpired && expiryTimeRemaining > 0 {
                        // Plain caption, no pill — fewer surfaces.
                        HStack(spacing: 5) {
                            Image(systemName: "timer")
                                .font(.caption2)
                            Text("Expires in \(formatTimeRemaining(expiryTimeRemaining))")
                                .font(.footnote)
                        }
                        .foregroundStyle(expiryTimeRemaining < 60 ? ErrorSeverity.error.foreground : Color.primary.opacity(0.5))
                    }

                    if walletManager.activeMint != nil || blockExplorerURL(for: quote) != nil {
                        VStack(spacing: 0) {
                            if let mint = walletManager.activeMint {
                                detailRow(
                                    label: "Mint",
                                    value: extractMintHost(mint.url)
                                )
                            }
                            if let explorerURL = blockExplorerURL(for: quote) {
                                explorerLinkRow(label: blockExplorerLabel(for: quote), url: explorerURL)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal)
            }

            Button(action: { copyRequest(quote.request) }) {
                Text(copyButtonTitle(for: quote))
            }
            .flatSheetSecondaryButton()
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .onAppear {
            startQuoteMonitoring(for: quote)
            startExpiryCountdown(quote: quote)
        }
        .onChange(of: mintQuote?.id) { _, _ in
            if let quote = mintQuote {
                startQuoteMonitoring(for: quote)
                startExpiryCountdown(quote: quote)
            }
        }
    }

    private func amountSummary(for quote: MintQuoteInfo) -> some View {
        VStack(spacing: 6) {
            if let amount = quote.amount {
                if quote.paymentMethod == .onchain {
                    // Onchain: amount surfaces once the sender has paid (amountPaid).
                    // Always shown in sats — no fiat toggle.
                    AmountLockup(
                        parts: AmountFormatter.satsParts(
                            amount, useBitcoinSymbol: settings.useBitcoinSymbol
                        ),
                        role: .amountCompact,
                        value: Double(amount),
                        accessibilityPrefix: "Amount received"
                    )
                } else if quote.unit.lowercased() == "sat" {
                    // Smaller than the QR — the QR is the focal element on this
                    // screen; the amount confirms it.
                    CurrencyAmountDisplay(
                        sats: amount,
                        primary: $settings.amountDisplayPrimary,
                        role: .amountCompact
                    )
                    .accessibilityLabel("Request amount: \(amount) sats")
                } else {
                    // Non-sat mint unit: show it directly, no BTC-price flip.
                    AmountLockup(
                        parts: AmountParts.parse(formatQuoteAmount(amount, unit: quote.unit)),
                        role: .amountCompact,
                        value: Double(amount),
                        accessibilityPrefix: "Request amount"
                    )
                }
            } else {
                // "New address" lives in the toolbar overflow menu (BOLT12
                // parity); this slot only shows progress while it generates.
                if isCreatingRequest {
                    ProgressView()
                        .tint(.secondary)
                }
            }
        }
    }

    // MARK: - Detail Row

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
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    /// Same as `detailRow` but tappable, with a trailing pencil — used for the
    /// Amount row on the reusable offer screen (mirrors the Cashu Request screen).
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
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edits the \(label.lowercased())")
    }

    /// Same shape as `detailRow` but opens an external URL, with the trailing
    /// arrow-up-right glyph settings uses for outbound links — used for the
    /// on-chain block explorer row.
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

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        // No `isPaid` branch: the body swaps to the full-screen success
        // terminal the instant `isPaid` flips, so an inline received badge
        // here could never render — the celebration lives in
        // `PaymentStatusView`'s staged entrance.
        Group {
            if isCheckingPayment || isMinting {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(.accentColor)
                        .scaleEffect(0.8)
                    Text(isMinting ? "Minting..." : "Checking...")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            } else if isExpired {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .accessibilityHidden(true)
                    Text("Expired")
                }
                .font(.subheadline.weight(.medium))
                // Same severity token as the countdown above it, which already
                // moved off Color.red — the two states of one clock.
                .foregroundStyle(ErrorSeverity.error.foreground)
                .transition(.opacity)
            } else if mintQuote?.state == .paid || mintQuote?.state == .issued {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .symbolEffect(.bounce, value: reduceMotion ? nil : mintQuote?.state)
                        .accessibilityHidden(true)
                    Text("Payment detected")
                }
                // Quiet intermediate — payment seen but not yet minted into the
                // balance. Monochrome (not green): green is reserved for the final
                // "Payment Received!" celebration below (DESIGN.md — retired the
                // small worded green success badge).
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(pendingStatusText)
                }
                .font(.subheadline)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.7), value: isPaid)
        .animation(.easeInOut(duration: 0.2), value: isCheckingPayment)
        .animation(.easeInOut(duration: 0.2), value: isMinting)
        .animation(.easeInOut(duration: 0.2), value: isExpired)
    }

    private var pendingStatusText: String {
        guard let quote = mintQuote else {
            return "Waiting for payment..."
        }

        switch quote.paymentMethod {
        case .bolt11, .bolt12:
            return "Waiting for payment..."
        case .onchain:
            if let observation = onchainObservation {
                return "\(observation.statusText). Trying to mint..."
            }
            return "Waiting for on-chain payment..."
        }
    }

    // MARK: - Helpers

    private func formattedAmount(sats: UInt64?) -> String {
        let amount = sats ?? 0
        if settings.useBitcoinSymbol {
            return "₿\(amount)"
        }
        return "\(amount) sat"
    }

    private func formatBalance(_ sats: UInt64) -> String {
        AmountFormatter.sats(sats, useBitcoinSymbol: settings.useBitcoinSymbol)
    }

    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "Expired" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours >= 1 {
            // 23h 59m — under-an-hour precision isn't useful at this scale
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes >= 1 {
            // 12m 30s — seconds matter once we're under the hour
            return "\(minutes)m \(secs)s"
        }
        // Sub-minute, urgency: just seconds
        return "\(secs)s"
    }

    private func quoteStateText(for quote: MintQuoteInfo) -> String {
        if isPaid { return "Paid" }
        if isExpired { return "Expired" }
        if quote.paymentMethod == .onchain,
           quote.state == .pending,
           let observation = onchainObservation {
            return observation.statusText
        }

        switch quote.state {
        case .issued:
            return "Issued"
        case .paid:
            return "Paid"
        case .pending:
            return "Pending"
        }
    }

    private func copyButtonTitle(for quote: MintQuoteInfo) -> String {
        "Copy \(quote.paymentMethod.requestDisplayName)"
    }

    private func blockExplorerURL(for quote: MintQuoteInfo) -> URL? {
        guard quote.paymentMethod == .onchain else { return nil }

        if let txid = onchainObservation?.txid {
            return OnchainExplorer.transactionWebURL(
                for: txid,
                address: quote.request,
                mintURL: walletManager.activeMint?.url
            )
        }

        return OnchainExplorer.addressWebURL(for: quote.request, mintURL: walletManager.activeMint?.url)
    }

    private func blockExplorerLabel(for quote: MintQuoteInfo) -> String {
        guard quote.paymentMethod == .onchain else {
            return "View in block explorer"
        }

        return onchainObservation == nil
            ? "View address in block explorer"
            : "View transaction in block explorer"
    }

    private func syncSelectedMethodWithActiveMint() {
        // A different mint may not mint the previously-picked unit — clear the
        // explicit choice so `effectiveUnit` falls back to the new mint's default.
        selectedReceiveUnit = nil
        guard availableMintMethods.contains(selectedMethod) else {
            let fallback = availableMintMethods.first ?? .bolt11
            selectedMethod = fallback
            // BOLT12 is now exclusively amountless (the fixed-amount row was
            // retired), so a fallback onto bolt12 — e.g. a mint that supports
            // only bolt12 — must land on the amountless path, not a keypad.
            // Every other rail enters its amount on the keypad.
            isAmountless = (fallback == .bolt12)
            return
        }
    }

    // MARK: - Actions

    /// Translate a picked `ReceiveMethodOption` into state + side effects. The
    /// single place that owns the (method, isAmountless) transition, so there's
    /// no split between a sheet binding-write and an `onChange` reaction.
    private func applyMethodOption(_ option: ReceiveMethodOption) {
        if option.method == .onchain {
            // Onchain: no amount needed — generate an address immediately.
            selectedMethod = .onchain
            isAmountless = false
            amountString = ""
            createRequest(method: .onchain, amountless: false)
        } else if option.autoCreates {
            // Any-amount reusable offer: skip the keypad and create now. Set
            // state so the overlay/title/switcher reflect the reusable method,
            // then create with EXPLICIT params (don't rely on the @State writes
            // above having propagated by the time `createRequest` reads them).
            selectedMethod = option.method   // .bolt12
            isAmountless = true
            amountString = ""
            loadOrCreateAmountlessOffer()
        } else {
            // Lightning / fixed reusable: land on the amount screen.
            selectedMethod = option.method
            isAmountless = false
        }
    }

    private func createRequest() {
        createRequest(method: selectedMethod, amountless: isAmountlessOffer)
    }

    /// Persist a receive-intent for the quote so it appears in History as a
    /// first-class, re-openable row — exactly like a Cashu Request. Reusable
    /// BOLT12 offers aggregate their payments and keep collecting; the one-shot
    /// BOLT11 / on-chain rails are wired in a later step. Deduped by `quoteId`,
    /// so re-opening the single reusable offer never spawns a second row.
    private func persistReceiveIntent(for quote: MintQuoteInfo) {
        let rail: CashuRequest.Rail
        let reusable: Bool
        switch quote.paymentMethod {
        case .bolt12:
            rail = .bolt12
            reusable = true
        case .bolt11, .onchain:
            return
        }

        let expiry = quote.expiry.flatMap { $0 > 0 ? Date(timeIntervalSince1970: Double($0)) : nil }
        CashuRequestStore.shared.upsertQuoteIntent(
            rail: rail,
            quoteId: quote.id,
            encoded: quote.request,
            amount: quote.amount,
            mints: walletManager.activeMint.map { [$0.url] } ?? [],
            reusable: reusable,
            expiry: expiry
        )
    }

    /// Re-mints the reusable BOLT12 offer at a new amount, driven by the Amount-row
    /// pencil. nil / 0 → amountless (reuses the existing offer); a positive value →
    /// a fresh fixed-amount offer. Setting an amount is how the user turns an "Any"
    /// reusable invoice into a fixed-amount one. The old QR stays on screen until
    /// the new offer is ready, so the keypad never flashes back in.
    private func setReusableOfferAmount(_ amount: UInt64?) {
        let target: UInt64? = (amount ?? 0) > 0 ? amount : nil
        isAmountless = (target == nil)

        guard let target else {
            loadOrCreateAmountlessOffer()
            return
        }

        isCreatingRequest = true
        requestFailure = nil
        isPaid = false
        isExpired = false
        onchainObservation = nil
        monitoredQuoteId = nil
        quoteStatusTask?.cancel()

        Task { @MainActor in
            do {
                mintQuote = try await walletManager.createMintQuote(amount: target, method: .bolt12)
            } catch {
                requestFailure = ReceiveRequestFailure(
                    title: requestFailureTitle(for: .bolt12),
                    message: error.userFacingWalletMessage,
                    retry: .setReusableAmount(target)
                )
            }
            isCreatingRequest = false
        }
    }

    /// Reopen the mint's existing amountless offer by default. The explicit new
    /// action deliberately bypasses that lookup and leaves the prior offer valid.
    private func loadOrCreateAmountlessOffer(forceNew: Bool = false, unit: String? = nil) {
        isCreatingRequest = true
        requestFailure = nil
        isAmountless = true
        isPaid = false
        isExpired = false
        onchainObservation = nil
        quoteCreatedAt = nil
        monitoredQuoteId = nil
        expiryTimeRemaining = 0
        quoteStatusTask?.cancel()
        expiryTimer?.invalidate()

        Task { @MainActor in
            do {
                let quote: MintQuoteInfo
                if !forceNew, let existing = try await walletManager.existingAmountlessOffer() {
                    quote = existing
                } else {
                    quote = try await walletManager.createMintQuote(
                        amount: nil,
                        method: .bolt12,
                        unit: unit ?? effectiveUnit
                    )
                }
                quoteCreatedAt = Date()
                mintQuote = quote
            } catch {
                requestFailure = ReceiveRequestFailure(
                    title: requestFailureTitle(for: .bolt12),
                    message: error.userFacingWalletMessage,
                    retry: .amountlessOffer(forceNew: forceNew, unit: unit)
                )
            }
            isCreatingRequest = false
        }
    }

    private func createNewAmountlessOffer(unit: String) {
        amountString = ""
        loadOrCreateAmountlessOffer(forceNew: true, unit: unit)
    }

    private func createRequest(method requestMethod: PaymentMethodKind, amountless: Bool, forceNew: Bool = false) {
        // Onchain is always amountless (sender decides). Lightning/BOLT12 require a value.
        // Amount is in the active unit's base units (sats, or eur/usd cents, …).
        let requestAmount: UInt64? = (amountless || requestMethod == .onchain) ? nil : (amountBaseUnits > 0 ? amountBaseUnits : nil)

        if !amountless, requestMethod != .onchain, (requestAmount ?? 0) == 0 {
            return
        }

        isCreatingRequest = true
        requestFailure = nil
        isPaid = false
        isExpired = false
        onchainObservation = nil
        quoteCreatedAt = nil
        monitoredQuoteId = nil
        expiryTimeRemaining = 0
        quoteStatusTask?.cancel()
        expiryTimer?.invalidate()

        Task { @MainActor in
            do {
                let quote: MintQuoteInfo
                if !forceNew,
                   requestMethod == .onchain,
                   let existing = try await walletManager.existingOnchainMintQuote() {
                    quote = existing
                } else {
                    quote = try await walletManager.createMintQuote(
                        amount: requestAmount,
                        method: requestMethod,
                        unit: effectiveUnit
                    )
                }
                quoteCreatedAt = Date()
                mintQuote = quote
            } catch {
                requestFailure = ReceiveRequestFailure(
                    title: requestFailureTitle(for: requestMethod),
                    message: error.userFacingWalletMessage,
                    retry: .create(
                        method: requestMethod,
                        amountless: amountless,
                        forceNew: forceNew
                    )
                )
            }
            isCreatingRequest = false
        }
    }

    private func shareQuoteRequest(_ request: String) {
        qrShareText = request
        showShareSheet = true
    }

    private func copyRequest(_ request: String) {
        UIPasteboard.general.string = request
        HapticFeedback.notification(.success)
        let copiedItem = mintQuote?.paymentMethod == .onchain
            ? "Bitcoin address"
            : "payment request"
        ConfirmationToast.show("Copied \(copiedItem)")
    }

    private func startExpiryCountdown(quote: MintQuoteInfo) {
        expiryTimer?.invalidate()
        expiryTimer = nil

        guard let expiry = quote.expiry, expiry > 0 else {
            expiryTimeRemaining = 0
            isExpired = false
            return
        }

        let expiryDate = Date(timeIntervalSince1970: Double(expiry))
        expiryTimeRemaining = expiryDate.timeIntervalSince(Date())

        if expiryTimeRemaining <= 0 {
            isExpired = true
            return
        }

        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            expiryTimeRemaining -= 1
            if expiryTimeRemaining <= 0 {
                isExpired = true
                expiryTimer?.invalidate()
                quoteStatusTask?.cancel()
            }
        }
    }

    /// "Use new address" re-keys every monitor to the replacement quote
    /// (`createRequest` resets `monitoredQuoteId` and cancels
    /// `quoteStatusTask`); this keeps the outgoing address on a 30s
    /// mint-status check so a payment already in flight still lands with the
    /// full success screen. Multiple presses accrue; ids are deduped.
    private func trackAbandonedOnchainQuote() {
        guard let quote = mintQuote,
              quote.paymentMethod == .onchain,
              quote.state != .issued,
              !quote.isExpired,
              !abandonedOnchainQuoteIds.contains(quote.id) else { return }
        abandonedOnchainQuoteIds.append(quote.id)
        startAbandonedQuoteWatcher()
    }

    private func startAbandonedQuoteWatcher() {
        guard abandonedQuoteTask == nil else { return }
        abandonedQuoteTask = Task { @MainActor in
            while !Task.isCancelled && !isPaid && !abandonedOnchainQuoteIds.isEmpty {
                await checkAbandonedOnchainQuotes()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
            abandonedQuoteTask = nil
        }
    }

    @MainActor
    private func checkAbandonedOnchainQuotes() async {
        for quoteId in abandonedOnchainQuoteIds {
            guard !isPaid, !Task.isCancelled else { return }
            guard let info = try? await walletManager.checkMintQuote(quoteId: quoteId) else { continue }
            // Drop quotes that expired before the mint saw any deposit; a
            // funded-but-expired quote keeps being probed.
            if info.isExpired, info.state == .pending, (info.amount ?? 0) == 0 {
                abandonedOnchainQuoteIds.removeAll { $0 == quoteId }
                continue
            }
            // On-chain quotes sit .pending until a mint attempt succeeds — the
            // mint call is the probe (mintQuoteIfReady parity; not-yet-funded
            // failures are expected and swallowed).
            var mintedAmount: UInt64?
            do {
                mintedAmount = try await walletManager.mintTokens(quoteId: quoteId)
            } catch {
                guard isAlreadyIssuedMintError(error) else { continue }
            }
            abandonedOnchainQuoteIds.removeAll { $0 == quoteId }
            // Stop the live quote's monitoring BEFORE swapping `mintQuote`, so
            // the display view's onChange can't restart polling mid-swap; then
            // reuse the standard success path.
            quoteStatusTask?.cancel()
            monitoredQuoteId = nil
            expiryTimer?.invalidate()
            let refreshed = (try? await walletManager.checkMintQuote(quoteId: quoteId)) ?? info
            // `receiveSuccessRows` and the home toast need a non-nil amount;
            // fall back to the freshly minted amount if the quote lacks one.
            mintQuote = refreshed.amount != nil ? refreshed : MintQuoteInfo(
                id: refreshed.id,
                request: refreshed.request,
                amount: mintedAmount,
                paymentMethod: .onchain,
                state: .issued,
                expiry: refreshed.expiry,
                createdAt: refreshed.createdAt,
                unit: refreshed.unit
            )
            await completeReceivedQuote(mintInBackground: false)
            return
        }
    }

    private func startQuoteMonitoring(for quote: MintQuoteInfo) {
        guard monitoredQuoteId != quote.id else { return }

        monitoredQuoteId = quote.id
        quoteStatusTask?.cancel()
        quoteStatusTask = Task { @MainActor in
            switch quote.paymentMethod {
            case .bolt11:
                await pollMintQuote(quoteId: quote.id, initialInterval: 5, maxInterval: 15)
            case .bolt12:
                await monitorMintQuoteViaSubscription(quoteId: quote.id, paymentMethod: .bolt12)
            case .onchain:
                await refreshMintQuoteStatus()
                await monitorMintQuoteViaSubscription(quoteId: quote.id, paymentMethod: .onchain)
            }
        }
    }

    @MainActor
    private func monitorMintQuoteViaSubscription(
        quoteId: String,
        paymentMethod: PaymentMethodKind
    ) async {
        do {
            if SettingsManager.shared.useWebsockets,
               let subscription = try await walletManager.subscribeToMintQuote(
                quoteId: quoteId,
                paymentMethod: paymentMethod
            ) {
                while !Task.isCancelled && !isPaid && !isExpired {
                    let notification = try await subscription.recv()
                    guard !Task.isCancelled else { break }

                    switch notification {
                    case .mintQuoteUpdate(let quoteUpdate):
                        guard quoteUpdate.quote == quoteId else { continue }
                        await refreshMintQuoteStatus()
                    case .mintQuoteOnchainUpdate(let quoteUpdate):
                        guard quoteUpdate.quote == quoteId else { continue }
                        await refreshMintQuoteStatus()
                    case .proofState, .meltQuoteUpdate, .meltQuoteOnchainUpdate:
                        continue
                    }
                }
                return
            }
        } catch {
            // Fall back to polling when subscriptions are unavailable or fail.
        }

        let initialInterval: UInt64 = paymentMethod == .onchain ? 30 : 10
        await pollMintQuote(quoteId: quoteId, initialInterval: initialInterval, maxInterval: 30)
    }

    @MainActor
    private func pollMintQuote(
        quoteId: String,
        initialInterval: UInt64,
        maxInterval: UInt64
    ) async {
        var interval = initialInterval

        while !Task.isCancelled && !isPaid && !isExpired && mintQuote?.id == quoteId {
            try? await Task.sleep(nanoseconds: interval * 1_000_000_000)

            guard !Task.isCancelled, !isPaid, !isExpired, mintQuote?.id == quoteId else { break }
            await refreshMintQuoteStatus()

            if interval < maxInterval {
                interval = min(interval + 1, maxInterval)
            }
        }
    }

    @MainActor
    private func refreshMintQuoteStatus() async {
        guard let quote = mintQuote, !isExpired, !isMinting else { return }

        isCheckingPayment = true
        defer { isCheckingPayment = false }

        do {
            let updatedQuote = try await walletManager.checkMintQuote(quoteId: quote.id)
            mintQuote = updatedQuote

            if updatedQuote.paymentMethod == .onchain, updatedQuote.state == .pending {
                await refreshOnchainObservation(for: updatedQuote)
                await mintQuoteIfReady(updatedQuote)
                return
            } else {
                onchainObservation = nil
            }

            switch updatedQuote.state {
            case .pending:
                return
            case .paid:
                // Payment detected. Finish the UX immediately and mint in the
                // background so a slow/transiently-failing mint never hangs the
                // sheet (the balance credits a beat later).
                await completeReceivedQuote(mintInBackground: true)
            case .issued:
                // Mint already issued the ecash — just refresh + finish.
                await completeReceivedQuote(mintInBackground: false)
            }
        } catch {
            // Ignore transient polling failures and keep monitoring.
        }
    }

    @MainActor
    private func refreshOnchainObservation(for quote: MintQuoteInfo) async {
        guard quote.paymentMethod == .onchain,
              let amount = quote.amount,
              let createdAt = quoteCreatedAt,
              let mintURL = walletManager.activeMint?.url else {
            onchainObservation = nil
            return
        }

        onchainObservation = await OnchainExplorer.observePayment(
            for: quote.request,
            mintURL: mintURL,
            expectedAmount: amount,
            createdAfter: createdAt
        )
    }

    @MainActor
    private func mintQuoteIfReady(_ quote: MintQuoteInfo) async {
        guard !isMinting else { return }

        isMinting = true
        defer { isMinting = false }

        do {
            let _ = try await walletManager.mintTokens(quoteId: quote.id)
            await completeReceivedQuote(mintInBackground: false)
        } catch {
            if isAlreadyIssuedMintError(error) {
                await completeReceivedQuote(mintInBackground: false)
                return
            }

            if quote.paymentMethod == .onchain {
                return
            }

            AppLogger.wallet.error(
                "Failed to mint quote \(quote.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Finish the receive UX as soon as the payment is *detected*. When
    /// `mintInBackground` is true the quote is `.paid` but not yet minted: we
    /// claim it in a detached task so a slow mint never holds the sheet open.
    /// When false the ecash is already issued and we just refresh.
    @MainActor
    private func completeReceivedQuote(mintInBackground: Bool) async {
        guard !isPaid else { return }

        // Flipping `isPaid` swaps the body to the full-screen success. The
        // success haptic is owned by `PaymentStatusView` on appear (don't
        // double-buzz here).
        isPaid = true
        expiryTimer?.invalidate()

        let quoteId = mintQuote?.id

        // Run the mint/refresh in an UNSTRUCTURED task that outlives this view
        // and the (about-to-be-cancelled) poll task, so it completes after the
        // sheet slides away.
        if mintInBackground, let quoteId {
            Task { await walletManager.claimPaidMintQuote(quoteId: quoteId) }
        } else {
            Task { @MainActor in
                await walletManager.refreshBalance()
                await walletManager.loadTransactions()
            }
        }

        // Fire the home-screen toast (same notification the NPC mint flow
        // posts from WalletManager) so the user sees the receipt on the home
        // screen after dismiss.
        if let quote = mintQuote, let amount = quote.amount {
            NotificationCenter.default.post(
                name: .cashuTokenReceived,
                object: nil,
                // Pass the unit so the home delta skips a misleading "+N sat" for
                // a non-sat mint (the sat balance didn't move).
                userInfo: ["amount": amount, "unit": quote.unit]
            )
        }

        // Payment is in — stop polling. The full-screen success now owns the
        // screen and stays until the user taps Done (no auto-dismiss); the
        // mint finishes in the background.
        quoteStatusTask?.cancel()
    }

    private func isAlreadyIssuedMintError(_ error: Error) -> Bool {
        let errorString = "\(error.localizedDescription) \(String(describing: error))".lowercased()

        if errorString.contains("already being minted")
            || errorString.contains("not issued")
            || errorString.contains("not yet")
            || errorString.contains("unissued") {
            return false
        }

        return errorString.contains("already issued")
            || errorString.contains("already minted")
            || errorString.contains("quote is issued")
            || errorString.contains("state=issued")
    }
}

#Preview {
    ReceiveLightningView()
        .environmentObject(WalletManager())
}
