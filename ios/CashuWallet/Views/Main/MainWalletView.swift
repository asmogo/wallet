import CoreNFC
import SwiftUI

enum HomeActionAccessibility {
    static let receiveHint = """
    Opens the unified flow for a pasted ecash token or a new Cashu Request, \
    Lightning invoice, BOLT12 offer, or Bitcoin address
    """

    static let sendHint = """
    Opens the unified flow for ecash, Lightning addresses, BOLT11 invoices, \
    BOLT12 offers, Bitcoin addresses, or Cashu Requests
    """
}

struct MainWalletView: View {
    /// Called when the user taps "View all activity" — switches the tab
    /// container to the History tab. Lives at the call-site so
    /// MainWalletView stays decoupled from the Tab enum.
    var onViewAllHistory: () -> Void = {}

    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var navigationManager: NavigationManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var priceService = PriceService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.cashuFonts) private var fonts

    @State private var receivedDelta: ReceivedDelta?
    @State private var deltaDismissTask: Task<Void, Never>?
    @State private var contactlessCoordinator = ContactlessPaymentCoordinator()
    @State private var selectedTransaction: WalletTransaction?
    @State private var isSheetDismissing = false
    @State private var topInsetHeight: CGFloat = 0
    /// Last-viewed home balance unit, persisted so the wallet reopens on it.
    /// Clamped back to "sat" whenever that unit no longer carries a balance.
    @AppStorage("homeBalanceUnit") private var storedHomeUnit: String = "sat"

    private let recentRowCap = 5
    /// Hero height (primary + status). Same whether single-unit or pager.
    ///
    /// Derived from the resolved type metrics rather than being a constant. It
    /// stays fixed for a given text size, so a unit swap or a fiat show/hide
    /// still cannot reflow the home canvas — that guarantee is the entire
    /// reason the reservation exists. But it now grows with the text size, so
    /// large-text users are no longer cropped by a box sized for the default.
    /// The old 94 also held an 18pt slot around a `.body`, whose line box is
    /// ~22pt, so the status line was clipping even at the default size.
    private var heroPagerHeight: CGFloat {
        CashuTextRole.amountHero.lineHeight(at: typeSize, fonts: fonts)
            + balanceLineSpacing + statusLineHeight
    }

    /// Reserved status-line slot under the primary amount.
    private var statusLineHeight: CGFloat {
        CashuTextRole.body.lineHeight(at: typeSize, fonts: fonts)
    }
    /// Move the converted line upward without changing the hero footprint:
    /// remove 2pt above it and reserve the same 2pt below it.
    private let balanceLineSpacing: CGFloat = 2
    private let convertedAmountBottomPadding: CGFloat = 2
    private let pageDotSize: CGFloat = 6
    /// Gap between hero and dots — always reserved with the dots slot.
    private let pageDotGap: CGFloat = 0

    private var isBottomSheetPresented: Bool {
        navigationManager.activeWalletSheet != nil || selectedTransaction != nil
    }

    /// Units the home hero can page through: sat, then each held non-sat unit.
    private var homeUnits: [String] {
        HomeBalance.homeBalanceUnits(walletManager.balancesByUnit)
    }

    /// Whether to show the swipe/dots pager: only when the active (default) mint
    /// is multi-unit AND a non-sat balance is held. A single-unit default mint
    /// keeps the single sat hero.
    private var showsUnitPager: Bool {
        HomeBalance.showsUnitPager(
            activeMintSupportsMultipleUnits: walletManager.activeMint?.supportsMultipleUnits ?? false,
            balancesByUnit: walletManager.balancesByUnit
        )
    }

    /// TabView selection clamped to the currently available units.
    private var selectedHomeUnit: Binding<String> {
        Binding(
            get: { HomeBalance.resolvedUnit(storedHomeUnit, in: homeUnits) },
            set: { storedHomeUnit = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                recentContent
            }
            .scrollIndicators(.hidden)
            // Rows dissolve into the pinned top section as they scroll up.
            .scrollEdgeFade(top: topInsetHeight)
            .refreshable {
                await walletManager.syncPendingMintQuotes(force: true)
                await walletManager.checkAllPendingTokens()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                fixedTopSection
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TopInsetHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
            }
            .onPreferenceChange(TopInsetHeightKey.self) { topInsetHeight = $0 }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                            .toolbarIconTapTarget()
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens wallet settings")
                    .accessibilityIdentifier("wallet-settings-button")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        navigationManager.activeWalletSheet = .scanner
                    } label: {
                        Image(systemName: "viewfinder")
                            .font(.body.weight(.semibold))
                            .toolbarIconTapTarget()
                    }
                    .accessibilityLabel("Scan QR Code")
                    .accessibilityHint("Opens the QR scanner")
                }
            }
            // The one flow-sheet slot. `onDismiss` fires after the dismiss
            // animation and promotes any surface parked by
            // `NavigationManager.present` — sheets replace, never stack.
            .sheet(
                item: $navigationManager.activeWalletSheet,
                onDismiss: { navigationManager.sheetDidDismiss() }
            ) { sheet in
                sheetView(for: sheet)
                    .observeBottomSheetDismissal { isSheetDismissing = $0 }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
                    .environmentObject(walletManager)
                    .observeBottomSheetDismissal { isSheetDismissing = $0 }
            }
            .task { await walletManager.loadTransactions() }
        }
        .bottomSheetBackdrop(
            isPresented: isBottomSheetPresented && !isSheetDismissing
        )
        .onChange(of: isBottomSheetPresented) { _, presented in
            if presented { isSheetDismissing = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cashuTokenReceived)) { note in
            guard let amount = note.userInfo?["amount"] as? UInt64 else { return }
            // The home balance + delta are sat-denominated. A non-sat receive
            // (eur/usd/…) doesn't move the sat balance and is confirmed on its own
            // success screen, so skip the delta rather than flash a misleading
            // "+N sat".
            let unit = note.userInfo?["unit"] as? String ?? "sat"
            guard unit.lowercased() == "sat" else { return }
            let fee = note.userInfo?["fee"] as? UInt64
            // Only background receives (poster sets "homeHaptic") buzz here; in-flow
            // receives own the success haptic on their confirmation surface.
            let playHaptic = note.userInfo?["homeHaptic"] as? Bool ?? false
            showReceivedDelta(amount: amount, fee: fee, playHaptic: playHaptic)
        }
        .onDisappear { deltaDismissTask?.cancel() }
    }

    // MARK: - Fixed Top Section

    // Pinned above the scroll. Sits on the bare canvas so the masked scroll
    // content reads as floating beneath it.
    private var fixedTopSection: some View {
        VStack(spacing: 0) {
            balanceSection
                .padding(.top, 8)

            actionButtons
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Balance Section

    private var balanceSection: some View {
        VStack(spacing: 0) {
            // Fixed footprint: hero + (gap + dots) always, whether the active
            // mint is single-unit or multi-unit — switching mints must not shove
            // Receive/Send / Recent up or down.
            VStack(spacing: pageDotGap) {
                Group {
                    let units = homeUnits
                    if !showsUnitPager {
                        unitBalanceHero("sat")
                    } else {
                        // Multi-unit: swipeable pager, one unit per page.
                        // Custom dots (not UIPageControl) for tight vertical margin.
                        TabView(selection: selectedHomeUnit) {
                            ForEach(units, id: \.self) { unit in
                                unitBalanceHero(unit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                    .tag(unit)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
                .frame(height: heroPagerHeight, alignment: .top)

                ZStack {
                    if showsUnitPager {
                        unitPagerDots(homeUnits)
                    }
                }
                .frame(height: pageDotSize)
            }
            .padding(.top, 18)
        }
    }

    /// One unit's balance hero. Sat uses the configured fiat/sats ordering plus
    /// its converted/received sub-line; other units render directly in that currency
    /// (no fiat conversion — eur is already fiat). Status-line slot is always
    /// reserved so pages and single-unit mode share one height.
    @ViewBuilder
    private func unitBalanceHero(_ unit: String) -> some View {
        VStack(spacing: balanceLineSpacing) {
            if unit.lowercased() == "sat" {
                let sats = walletManager.balancesByUnit["sat"] ?? walletManager.balance
                let display = balanceDisplay(sats)
                let primaryValue = balanceNumericValue(sats, primary: display.effectivePrimary)
                if let secondary = display.secondary {
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .snappy) {
                            settings.homeBalancePrimary.toggle()
                        }
                    } label: {
                        AmountLockup(
                            parts: display.primaryParts,
                            value: primaryValue,
                            accessibilityPrefix: "Balance"
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Balance: \(display.primary)")
                    .accessibilityHint("Double tap to make \(secondary) the primary balance")
                    .sensoryFeedback(.selection, trigger: settings.homeBalancePrimary)
                } else {
                    AmountLockup(
                        parts: display.primaryParts,
                        value: primaryValue,
                        accessibilityPrefix: "Balance"
                    )
                }

                // Status line under the balance: a transient monochrome
                // received-delta beat takes over the fiat slot for 2.5s on receipt,
                // then fiat fades back. Same slot, so the swap doesn't reflow the
                // balance. (De-greened 2026-07-05 — the balance roll carries the moment.)
                balanceStatusLine(display, secondaryValue: balanceSecondaryNumericValue(sats, display: display))
            } else {
                let amount = walletManager.balancesByUnit[unit] ?? 0
                let formatted = CurrencyAmount(
                    value: amount,
                    currency: CurrencyRegistry.currency(forMintUnit: unit)
                ).formatted()
                AmountLockup(
                    parts: AmountParts.parse(formatted),
                    value: Double(amount),
                    accessibilityPrefix: "Balance"
                )
                .animation(.snappy, value: amount)
                // Same reserved status slot as sat (no fiat conversion for non-sat).
                Color.clear.frame(height: statusLineHeight)
            }
        }
        .padding(.bottom, convertedAmountBottomPadding)
    }

    /// Compact page dots under the unit pager (6pt dots, 6pt gap, active pill
    /// at 2.5× width). Parent always reserves [pageDotGap + pageDotSize].
    private func unitPagerDots(_ units: [String]) -> some View {
        let selected = selectedHomeUnit.wrappedValue
        return HStack(spacing: 6) {
            ForEach(units, id: \.self) { unit in
                let isSelected = unit == selected
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.2))
                    .frame(
                        width: isSelected ? pageDotSize * 2.5 : pageDotSize,
                        height: pageDotSize
                    )
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: selected)
        .accessibilityHidden(true)
    }

    // MARK: - Received Delta Beat

    /// The status line beneath the balance: the transient received-delta beat
    /// while a payment just landed, otherwise the fiat sub-amount. Always keeps
    /// [statusLineHeight] so hiding fiat never collapses the hero.
    @ViewBuilder
    private func balanceStatusLine(_ display: AmountDisplayText, secondaryValue: Double?) -> some View {
        ZStack {
            if let delta = receivedDelta {
                receivedDeltaBeat(delta)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
            } else if !walletManager.isRuntimeReady {
                Text("Preparing wallet…")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else if let secondary = display.secondary {
                Text(secondary)
                    .font(.body)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: secondaryValue ?? 0))
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : .snappy, value: secondaryValue)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(height: statusLineHeight)
    }

    /// Quiet "+2,500" beat. Monochrome (`.secondary`) — no green, no checkmark,
    /// no bounce: the rolling balance above is the primary signal, this just
    /// names the exact amount that landed. Grouped via the canonical formatter,
    /// no unit (the balance beside it carries it), no directional arrow (the
    /// down-arrow stays exclusive to row badges). VoiceOver-hidden; the balance
    /// announces the new total.
    private func receivedDeltaBeat(_ delta: ReceivedDelta) -> some View {
        Text("+\(settings.formatAmountShort(delta.amount))")
            .monospacedDigit()
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    /// Reuses the sanctioned payment-received celebration spring (Motion §6);
    /// reduce-motion collapses it to a plain opacity cross-fade.
    private var receivedDeltaAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.7)
    }

    /// Shows the beat and re-arms a 2.5s dismiss timer. Rapid receives coalesce
    /// to last-write-wins: the prior timer is cancelled and the new amount takes
    /// over. Fires the "sats landed" haptic only when the caller opts in
    /// (`playHaptic`) — reserved for background receives no visible surface
    /// confirms (npub.cash). In-flow receives (Lightning / ecash paste via
    /// PaymentStatusView, a watched Cashu request) already own a success haptic,
    /// so they leave it off to avoid a double-buzz.
    private func showReceivedDelta(amount: UInt64, fee: UInt64?, playHaptic: Bool) {
        deltaDismissTask?.cancel()
        if playHaptic { HapticFeedback.notification(.success) }
        withAnimation(receivedDeltaAnimation) {
            receivedDelta = ReceivedDelta(amount: amount, fee: fee)
        }
        deltaDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(receivedDeltaAnimation) {
                receivedDelta = nil
            }
        }
    }

    // MARK: - Action Buttons (Receive + Send)

    /// Scan moved to the toolbar; the action row is a two-button pair.
    /// On iOS 26 these use Apple's native neutral Liquid Glass button style
    /// (`.buttonStyle(.glass)`), wrapped in a `GlassEffectContainer` so the two
    /// adjacent capsules sample light consistently. The native style owns its own
    /// interactive press/morph, so a single gesture drives each button. iOS 18–25
    /// falls back to the in-house `glassButton()` capsule.
    @ViewBuilder
    private var actionButtons: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    actionButton(
                        "Receive",
                        identifier: "wallet-action-receive",
                        hint: HomeActionAccessibility.receiveHint
                    ) { navigationManager.activeWalletSheet = .receive }

                    actionButton(
                        "Send",
                        identifier: "wallet-action-send",
                        hint: HomeActionAccessibility.sendHint
                    ) { navigationManager.activeWalletSheet = .send(prefill: nil) }
                }
            }
            .disabled(!walletManager.isRuntimeReady)
        } else {
            HStack(spacing: 12) {
                Button { navigationManager.activeWalletSheet = .receive } label: {
                    Text("Receive")
                }
                .glassButton()
                .accessibilityIdentifier("wallet-action-receive")
                .accessibilityHint(HomeActionAccessibility.receiveHint)

                Button { navigationManager.activeWalletSheet = .send(prefill: nil) } label: {
                    Text("Send")
                }
                .glassButton()
                .accessibilityIdentifier("wallet-action-send")
                .accessibilityHint(HomeActionAccessibility.sendHint)
            }
            .disabled(!walletManager.isRuntimeReady)
        }
    }

    /// A single home action button rendered with Apple's native neutral
    /// Liquid Glass style, sized to fill half the action row.
    @available(iOS 26, *)
    private func actionButton(
        _ title: String,
        identifier: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier(identifier)
        .accessibilityHint(hint)
    }

    // MARK: - Recent Activity

    @ViewBuilder
    private var recentContent: some View {
        let items = recentItems
        if items.isEmpty {
            Group {
                if walletManager.mints.isEmpty {
                    NativeEmptyState(
                        title: "Add a mint to get started",
                        systemImage: "bitcoinsign.bank.building",
                        description: "Mints custody your ecash. Add one to begin.",
                        actionTitle: "Add mint",
                        action: { navigationManager.activeWalletSheet = .connectMint }
                    )
                } else {
                    // Same shared component, size, and centered placement as the
                    // History empty state, but with its own tray icon and copy
                    // (recent-activity framing vs. History's clock + "history"). No
                    // "Recent" header here: with nothing to label it's redundant,
                    // and dropping it matches History's clean full-screen empty state.
                    NativeEmptyState(
                        title: "No Activity Yet",
                        systemImage: "tray",
                        description: "Your recent payments will show up here."
                    )
                }
            }
            .containerRelativeFrame(.vertical)
            .padding(.horizontal, 16)
        } else {
            VStack(spacing: 0) {
                recentList(items)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)

                // Tail spacer so the last row can scroll under the
                // Liquid Glass tab bar without sitting flush against it.
                Color.clear.frame(height: 32)
            }
        }
    }

    private func recentList(_ items: [WalletTransaction]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Recent")

            ForEach(items) { item in
                transactionRow(transaction: item)
            }

            Button(action: onViewAllHistory) {
                HStack(spacing: 4) {
                    Text("View all activity")
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Switches to the History tab")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .cashuText(.overline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 16)
            .padding(.bottom, 14)
    }

    // MARK: - Recent completed payments

    private var recentItems: [WalletTransaction] {
        HomeActivity.recentTransactions(
            from: walletManager.transactions,
            limit: recentRowCap
        )
    }

    // MARK: - Transaction row (slimmer than HistoryView's variant)

    private func transactionRow(transaction: WalletTransaction) -> some View {
        Button {
            HapticFeedback.selection()
            selectedTransaction = transaction
        } label: {
            HStack(spacing: 14) {
                rowIcon(for: transaction)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(rowTitle(for: transaction))
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Text(formatRelativeDate(transaction.date))
                        .cashuText(.metadata)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                TransactionAmountColumn(transaction: transaction)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rowTitle(for: transaction)), \(formatAmount(transaction)), \(transaction.status == .completed ? "completed" : transaction.displayStatusText.lowercased()), \(formatRelativeDate(transaction.date))")
        .accessibilityHint("Opens transaction details")
    }

    @ViewBuilder
    private func rowIcon(for transaction: WalletTransaction) -> some View {
        TransactionIcon(direction: transaction.type)
    }

    private func rowTitle(for transaction: WalletTransaction) -> String {
        transaction.displayTitle
    }

    private func formatAmount(_ transaction: WalletTransaction) -> String {
        let value: String
        if transaction.unit.lowercased() == "sat" {
            value = balanceDisplay(transaction.amount).primary
        } else {
            value = CurrencyAmount(
                value: transaction.amount,
                currency: CurrencyRegistry.currency(forMintUnit: transaction.unit)
            ).formatted()
        }
        guard !transaction.isUnsettled else { return value }
        return transaction.type == .incoming ? "+\(value)" : value
    }

    // MARK: - Relative date

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

    // MARK: - Helpers

    private func balanceDisplay(_ sats: UInt64) -> AmountDisplayText {
        AmountFormatter.displayText(
            amountSats: sats,
            preferredPrimary: settings.homeBalancePrimary,
            showFiat: settings.showFiatBalance,
            btcPrice: priceService.btcPriceUSD,
            currencyCode: settings.bitcoinPriceCurrency,
            useBitcoinSymbol: settings.useBitcoinSymbol
        )
    }

    private func balanceNumericValue(_ sats: UInt64, primary: AmountDisplayPrimary) -> Double {
        primary == .fiat ? priceService.satsToFiat(sats) : Double(sats)
    }

    private func balanceSecondaryNumericValue(_ sats: UInt64, display: AmountDisplayText) -> Double? {
        guard display.secondary != nil else { return nil }
        return display.effectivePrimary == .fiat ? Double(sats) : priceService.satsToFiat(sats)
    }

    @ViewBuilder
    private func sheetView(for sheet: WalletSheet) -> some View {
        switch sheet {
        case .receive:
            // UnifiedReceiveView mirrors UnifiedSendView: a content-fit input sheet
            // with Scan · Ecash · Bitcoin. A pasted/scanned *payable* is really a
            // Send, so it hands the destination back to the Send flow via `onSend`.
            UnifiedReceiveView(
                onClose: { navigationManager.activeWalletSheet = nil },
                onSend: { destination in
                    navigationManager.activeWalletSheet = .send(prefill: destination)
                },
                // A pasted/scanned token opens the full-screen claim page; the
                // sheet closes first (parked handoff), so its X lands on the
                // wallet — never back on this input sheet.
                onOpenReceiveToken: { token in
                    navigationManager.present(.cover(.receiveToken(token)))
                },
                onReceiveLightning: {
                    navigationManager.activeWalletSheet = .receiveLightning
                }
            )
            .environmentObject(walletManager)
        case .send(let prefill):
            // UnifiedSendView owns its presentation detents: content-fit on the
            // input step, `.large` + canvas once amount/confirm/status take over.
            UnifiedSendView(
                initialDestination: prefill,
                onClose: { navigationManager.activeWalletSheet = nil },
                onReceive: { navigationManager.activeWalletSheet = .receive },
                onContactless: {
                    navigationManager.activeWalletSheet = nil
                    contactlessCoordinator.start(
                        walletManager: walletManager,
                        navigationManager: navigationManager
                    )
                },
                // A token pasted into Send is a receive: bounce it to the
                // full-screen claim page, closing the Send sheet first.
                onOpenReceiveToken: { token in
                    navigationManager.present(.cover(.receiveToken(token)))
                },
                onSendEcash: { navigationManager.activeWalletSheet = .sendEcash }
            )
            .environmentObject(walletManager)
        case .scanner:
            // The scanner self-dismisses on a successful read and hands the
            // payload back; the routed surface presents only after this sheet
            // is gone — the scanner is never left open underneath.
            ScannerWrapperView(
                onScanned: { payload in
                    navigationManager.routeScannedPayload(payload, walletManager: walletManager)
                },
                classify: { payload in
                    navigationManager.classifyScannedPayload(payload, walletManager: walletManager)
                }
            )
            .environmentObject(walletManager)
            .presentationDetents([.large])
            .canvasSheetBackground()
        case .sendEcash:
            // Swapped into the sheet from Send's method row, so there is no
            // stack to pop: X and swipe-down both abandon to the wallet.
            SendView()
                .environmentObject(walletManager)
                .presentationDetents([.large])
                .compactBottomSheetSurface()
        case .receiveLightning:
            ReceiveLightningView()
                .environmentObject(walletManager)
                .presentationDetents([.large])
                .compactBottomSheetSurface()
        case .meltInvoice(let invoice):
            MeltViewWithInvoice(invoice: invoice)
                .environmentObject(walletManager)
                .presentationDetents([.large])
                .flatBottomSheetSurface()
        case .connectMint:
            // Same surface the Send sheet shows when there are no mints — the
            // detents and canvas background live inside it.
            ConnectMintSheet()
                .environmentObject(walletManager)
        case .discoverMints:
            MintDiscoverySheet()
            .environmentObject(walletManager)
            .flatBottomSheetSurface()
        }
    }
}

/// A just-received amount, surfaced as the transient balance beat. The `id`
/// makes rapid successive receives re-trigger the entrance + checkmark bounce.
private struct ReceivedDelta: Identifiable, Equatable {
    let id = UUID()
    let amount: UInt64
    let fee: UInt64?
}

private struct TopInsetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    MainWalletView()
        .environmentObject(WalletManager())
        .environmentObject(NavigationManager())
}
