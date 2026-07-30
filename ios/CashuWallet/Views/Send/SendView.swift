import SwiftUI
import CoreNFC

struct SendView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared

    @State private var amountString = ""
    @State private var memo = ""
    @State private var generatedToken: String?
    @State private var generatedTokenMintURL: String?
    @State private var tokenFee: UInt64 = 0
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var errorSeverity: ErrorSeverity = .error
    @State private var errorShowsMintAction = false
    // Optional second line under the error notice (e.g. the change-fee hint);
    // overrides the generic insufficient-balance detail when set.
    @State private var errorDetail: String?
    @State private var showMintPicker = false
    @State private var selectedSendMint: MintInfo?

    // Multi-unit send: the user's explicit unit choice for this flow (nil = use
    // the mint's default), the picker sheet flag, and the async-loaded balance
    // for the active non-sat unit (sat uses the cached mint balance instead).
    @State private var selectedSendUnit: String?
    @State private var showUnitPicker = false
    @State private var selectedUnitBalance: UInt64?
    // Unit + amount captured at generation time so the pending-token screen keeps
    // showing the right denomination even if the live selection later changes.
    @State private var generatedTokenUnit: String = "sat"
    @State private var generatedAmount: UInt64 = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Token claim detection
    @State private var isCheckingClaim = false
    @State private var tokenClaimed = false
    @State private var checkingTask: Task<Void, Never>?

    // Copy button feedback
    @State private var copyButtonText = "Copy"
    @State private var showShareSheet = false
    @State private var lockWithP2PK = false
    @State private var p2pkPubkeyInput = ""

    // Lock-ecash flow (scan a public key to lock the token to)
    @State private var showLockScanner = false

    @ObservedObject private var priceService = PriceService.shared

    var body: some View {
        NavigationStack {
            Group {
                if let token = generatedToken {
                    if tokenClaimed {
                        // Recipient claimed → the same full-screen success the
                        // pay/receive flows use, replacing the QR entirely.
                        claimedSuccessView
                            .transition(.opacity)
                    } else {
                        tokenDisplayView(token: token)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                } else {
                    sendInputView
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.smooth(duration: 0.3), value: generatedToken != nil)
            .animation(.smooth(duration: 0.3), value: tokenClaimed)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(generatedToken != nil ? "Pending Ecash" : "Send Ecash")
            // Match the Lightning Invoice screen: float the title + chrome
            // over the black canvas, no secondary gray strip.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                // Explicit close in every state — the sheet drag indicator is
                // unreliable and the fullScreenCover send path has no swipe
                // dismiss at all, which stranded users on "Pending Ecash".
                ToolbarItem(placement: .topBarLeading) {
                    SheetCloseButton()
                }

                if generatedToken == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            HapticFeedback.selection()
                            showLockScanner = true
                        } label: {
                            Image(systemName: "lock")
                                .toolbarIconTapTarget()
                        }
                        .accessibilityLabel("Lock ecash")
                        .accessibilityHint("Lock this ecash to a public key")
                    }
                }

                // Unit selector — only when the active mint offers more than one
                // unit. Declared after the lock so it sits to the lock's right.
                if generatedToken == nil, let mint = unitContextMint, mint.supportsMultipleUnits {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            HapticFeedback.selection()
                            showUnitPicker = true
                        } label: {
                            Text(effectiveSendUnit.uppercased())
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityLabel("Unit: \(effectiveSendUnit.uppercased())")
                        .accessibilityHint("Choose the unit for this ecash")
                    }
                }

                if generatedToken != nil && !tokenClaimed {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .toolbarIconTapTarget()
                        }
                        .accessibilityLabel("Share token")
                    }
                }
            }
            .sheet(isPresented: $showMintPicker) {
                MintSelectorSheet(
                    selectedMint: sendMintSelection,
                    minimumAmount: amountSats > 0 ? amountSats : nil,
                    onSelect: selectSendMint
                )
                    .environmentObject(walletManager)
            }
            .sheet(isPresented: $showUnitPicker) {
                UnitSelectorSheet(
                    units: unitContextMint?.units ?? ["sat"],
                    selectedUnit: effectiveSendUnit,
                    onSelect: selectSendUnit
                )
            }
            .sheet(isPresented: $showShareSheet) {
                if let token = generatedToken {
                    CashuTokenShareSheet(token: token)
                }
            }
            .sheet(isPresented: $showLockScanner) {
                ScannerWrapperView(
                    onScanned: handleScannedPubkey,
                    promptText: "Scan a public key to lock to",
                    quickFills: lockQuickFills
                )
                .environmentObject(walletManager)
                .canvasSheetBackground()
            }
            .onDisappear {
                checkingTask?.cancel()
            }
            .onChange(of: entryUnit) { oldUnit, newUnit in
                // Only the sats↔fiat display flip re-expresses the typed string.
                // A non-sat mint unit is entered directly and must not be
                // reinterpreted through the sat price.
                guard isSatSend else { return }
                amountString = AmountFormatter.entryConverted(raw: amountString, from: oldUnit, to: newUnit)
            }
            .task(id: unitBalanceKey) {
                await loadUnitBalance()
            }
        }
    }

    // MARK: - Send Input View

    private var sendInputView: some View {
        VStack(spacing: 0) {
            // Mint selector
            if let mint = displaySendMint {
                mintSelector(mint: mint)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            // Locked-to-key indicator (when the token will be P2PK-locked)
            if lockWithP2PK, let locked = normalizedP2PKPubkeyInput {
                lockedKeyChip(key: locked)
                    .padding(.horizontal)
                    .padding(.top, 10)
            }

            // Flexible cell between mint row and keypad: amount centered (Android
            // InputFace weight spacers), notice pinned to the bottom of the same cell.
            ZStack {
                Group {
                    if isSatSend {
                        CurrencyAmountDisplay(
                            sats: amountSats,
                            primary: $settings.amountDisplayPrimary,
                            entryRaw: amountString,
                            isDimmed: isInsufficientBalance
                        )
                    } else {
                        Text(sendUnitEntryDisplay)
                            .font(.system(size: 64, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isInsufficientBalance ? .secondary : .primary)
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                            .contentTransition(.numericText(value: Double(amountBaseUnits)))
                            .animation(.snappy, value: amountBaseUnits)
                            .animation(.snappy, value: isInsufficientBalance)
                    }
                }

                VStack {
                    Spacer(minLength: 0)
                    if isInsufficientBalance {
                        sendInputNotice(
                            message: "Insufficient balance",
                            detail: insufficientBalanceDetail,
                            severity: .caution
                        )
                    } else if let error = errorMessage {
                        sendInputNotice(
                            message: error,
                            detail: errorDetail ?? (errorShowsMintAction ? insufficientBalanceDetail : nil),
                            severity: errorSeverity
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25), value: isInsufficientBalance)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25), value: errorMessage)

            // Number pad — sats/fiat display entry, or direct entry in the
            // active mint unit's own precision (0 decimals for sat, 2 for eur/usd).
            Group {
                if isSatSend {
                    NumberPadAmountInput(amountString: $amountString, unit: entryUnit)
                } else {
                    NumberPadAmountInput(amountString: $amountString, decimals: sendUnitDecimals)
                }
            }
            .padding(.horizontal, 24)

            Button(action: {
                HapticFeedback.impact(.light)
                generateToken()
            }) {
                if isGenerating {
                    ProgressView()
                } else {
                    Text("Send")
                }
            }
            .glassButton()
            .disabled(!canSend || isGenerating)
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .animation(.snappy(duration: 0.3), value: lockWithP2PK)
    }

    /// Minimal notice for the send amount face — local so layout/animation stay
    /// isolated from `InlineNotice` / overlay sizing quirks.
    private func sendInputNotice(
        message: String,
        detail: String?,
        severity: ErrorSeverity
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: severity.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(severity.foreground)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(severity.foreground)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(severity.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    // MARK: - Mint Selector

    private func mintSelector(mint: MintInfo) -> some View {
        MintAmountSelectorRow(
            mint: mint,
            balanceText: sendBalanceText,
            onChooseMint: { showMintPicker = true },
            onUseMax: { useMax(mint: mint) }
        )
    }

    /// The unit the keypad is entering in: fiat only when fiat is primary AND a
    /// price is loaded, else sats (mirrors `CurrencyAmountDisplay.effectivePrimary`).
    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    /// Satoshis represented by the typed amount, interpreted per `entryUnit`.
    /// Zero outside sat mode (a non-sat amount has no sat value) — this also
    /// keeps `displaySendMint`'s balance-minimum from filtering on a garbage
    /// value while the keypad holds a eur/usd amount.
    private var amountSats: UInt64 {
        guard isSatSend else { return 0 }
        return AmountFormatter.entrySats(raw: amountString, unit: entryUnit)
    }

    // MARK: - Active unit

    /// The mint whose supported units drive the selector. Uses no sat-minimum,
    /// so resolving the active unit never (recursively) depends on the entered
    /// amount. Equals `displaySendMint` whenever a mint is explicitly chosen or
    /// the unit is non-sat.
    private var unitContextMint: MintInfo? {
        resolvedSelectedSendMint ?? recommendedSendMint(minimumAmount: nil)
    }

    /// The unit this send is denominated in — the user's pick when the mint
    /// supports it, otherwise a unit the wallet can actually spend. Auto-resets
    /// when the mint changes to one lacking the selected unit.
    private var effectiveSendUnit: String {
        guard let mint = unitContextMint else { return "sat" }
        if let selectedSendUnit, mint.units.contains(selectedSendUnit) {
            return selectedSendUnit
        }
        return defaultSpendableUnit(for: mint)
    }

    /// The unit to default to when the user hasn't chosen one: the mint's
    /// preferred unit while it holds a balance, otherwise the first supported
    /// unit the wallet can spend — so a USD-only wallet lands on USD instead of
    /// an empty sat form.
    private func defaultSpendableUnit(for mint: MintInfo) -> String {
        let preferred = mint.defaultUnit
        if unitHasSpendableBalance(preferred, mint: mint) { return preferred }
        return mint.units.first { unitHasSpendableBalance($0, mint: mint) } ?? preferred
    }

    /// Whether `unit` currently holds a spendable balance. Sat reads the cached
    /// per-mint balance; other units use the wallet-wide per-unit totals (the
    /// same source as the home hero) since non-sat per-mint balances load async.
    private func unitHasSpendableBalance(_ unit: String, mint: MintInfo) -> Bool {
        if unit.lowercased() == "sat" { return mint.balance > 0 }
        return (walletManager.balancesByUnit[unit] ?? 0) > 0
    }

    private var isSatSend: Bool { effectiveSendUnit.lowercased() == "sat" }
    private var sendUnitCurrency: any Currency { CurrencyRegistry.currency(forMintUnit: effectiveSendUnit) }
    private var sendUnitDecimals: Int { sendUnitCurrency.decimals }

    /// The amount actually created, in the active unit's base units (sats for
    /// sat; cents for eur/usd; integer for a custom unit).
    private var amountBaseUnits: UInt64 {
        isSatSend ? amountSats : AmountFormatter.entryBaseUnits(raw: amountString, decimals: sendUnitDecimals)
    }

    /// The active unit's spendable balance: sat from the cached mint balance,
    /// other units from the async-loaded `selectedUnitBalance`.
    private var effectiveSendBalance: UInt64 {
        isSatSend ? (displaySendMint?.balance ?? 0) : (selectedUnitBalance ?? 0)
    }

    /// Big-number display for a non-sat entry, formatted in the active unit.
    private var sendUnitEntryDisplay: String {
        CurrencyAmount(value: amountBaseUnits, currency: sendUnitCurrency).formatted()
    }

    /// The mint-row balance line, in the active unit ("…" while non-sat loads).
    private var sendBalanceText: String {
        if isSatSend { return formatBalance(displaySendMint?.balance ?? 0) }
        guard let bal = selectedUnitBalance else { return "…" }
        return CurrencyAmount(value: bal, currency: sendUnitCurrency).formatted()
    }

    /// Re-loads `selectedUnitBalance` whenever the (mint, unit) pair changes.
    private var unitBalanceKey: String { "\(displaySendMint?.url ?? "")|\(effectiveSendUnit)" }

    private func selectSendUnit(_ unit: String) {
        selectedSendUnit = unit
        // The typed amount's meaning changes with the unit — clear it and its
        // now-stale balance rather than reinterpret the digits.
        amountString = ""
        selectedUnitBalance = nil
        errorMessage = nil
        HapticFeedback.selection()
    }

    private func loadUnitBalance() async {
        guard !isSatSend, let mint = displaySendMint else {
            selectedUnitBalance = nil
            return
        }
        let unit = effectiveSendUnit
        let balance = await walletManager.unitBalance(mintURL: mint.url, unit: unit)
        // Ignore a result that arrived after the user moved on to another unit/mint.
        guard effectiveSendUnit == unit, displaySendMint?.url == mint.url else { return }
        selectedUnitBalance = balance
    }

    private func useMax(mint: MintInfo) {
        HapticFeedback.impact(.light)
        // The gross balance is always sendable: sends don't include fees
        // (TokenService includeFee: false), and a full-balance send matches
        // the proof set exactly — no swap, no fee, also on fee-charging mints.
        fillAmount(baseUnits: effectiveSendBalance)
    }

    /// Writes a base-unit amount into the keypad string in the current entry
    /// mode. Fiat entry is coarser than sats, so the cents round-trip can land
    /// above the target — which would leave a Send Max fill unsendable — and
    /// gets trimmed a cent at a time until it fits.
    private func fillAmount(baseUnits: UInt64) {
        if isSatSend {
            // Balance is sats; express it in the current entry unit so the keypad
            // string keeps its meaning.
            amountString = AmountFormatter.entryConverted(raw: String(baseUnits), from: .sats, to: entryUnit)
            guard entryUnit == .fiat else { return }
            var cents = AmountFormatter.entryBaseUnits(raw: amountString, decimals: 2)
            while cents > 0, AmountFormatter.entrySats(raw: amountString, unit: .fiat) > baseUnits {
                cents -= 1
                amountString = AmountFormatter.entryString(baseUnits: cents, decimals: 2)
            }
        } else {
            amountString = AmountFormatter.entryString(baseUnits: baseUnits, decimals: sendUnitDecimals)
        }
    }

    private var canSend: Bool {
        let amount = amountBaseUnits
        guard amount > 0 else { return false }
        guard displaySendMint != nil else { return false }
        if lockWithP2PK && normalizedP2PKPubkeyInput == nil { return false }
        return amount <= effectiveSendBalance
    }

    /// Live over-balance while typing — drives amount dimming + the caution notice
    /// above the keypad (mirrors Android Send Ecash / AmountEntryView).
    private var isInsufficientBalance: Bool {
        // Non-sat balances load async; don't flash "insufficient" at 0 while pending.
        if !isSatSend && selectedUnitBalance == nil { return false }
        let amount = amountBaseUnits
        return amount > 0 && amount > effectiveSendBalance
    }

    private var availableSendMints: [MintInfo] {
        var mints = walletManager.mints
        if let activeMint = walletManager.activeMint,
           !mints.contains(where: { $0.id == activeMint.id }) {
            mints.insert(activeMint, at: 0)
        }
        return mints
    }

    private var resolvedSelectedSendMint: MintInfo? {
        guard let selectedSendMint else { return nil }
        return availableSendMints.first { $0.id == selectedSendMint.id } ?? selectedSendMint
    }

    private var displaySendMint: MintInfo? {
        resolvedSelectedSendMint ?? recommendedSendMint(minimumAmount: amountSats > 0 ? amountSats : nil)
    }

    private var sendMintSelection: Binding<MintInfo?> {
        Binding(
            get: { displaySendMint },
            set: { newMint in
                if let newMint {
                    selectSendMint(newMint)
                } else {
                    selectedSendMint = nil
                }
            }
        )
    }

    private func recommendedSendMint(minimumAmount: UInt64?) -> MintInfo? {
        guard !availableSendMints.isEmpty else { return nil }

        let candidates: [MintInfo]
        if let minimumAmount, minimumAmount > 0 {
            let affordable = availableSendMints.filter { $0.balance >= minimumAmount }
            candidates = affordable.isEmpty ? availableSendMints : affordable
        } else {
            candidates = availableSendMints
        }

        if let activeMint = walletManager.activeMint,
           let activeCandidate = candidates.first(where: { $0.id == activeMint.id }) {
            return activeCandidate
        }

        return candidates.sorted { lhs, rhs in
            if lhs.balance == rhs.balance {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.balance > rhs.balance
        }.first
    }

    private func selectSendMint(_ mint: MintInfo) {
        selectedSendMint = mint
        errorMessage = nil
        HapticFeedback.selection()
    }

    /// Compact, removable indicator that the token will be P2PK-locked. Tapping
    /// the body reopens the scanner to change the key; the × clears the lock.
    /// Mirrors `ClipboardPaymentChip`'s visual language.
    private func lockedKeyChip(key: String) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticFeedback.selection()
                showLockScanner = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .background(.thinMaterial, in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Locked to")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(lockedKeyLabel(key))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Locked to public key")
            .accessibilityHint("Double-tap to change the key")

            Button(action: {
                HapticFeedback.selection()
                lockWithP2PK = false
                p2pkPubkeyInput = ""
            }) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove lock")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    /// Label for the locked-to chip: "Your key" when locking to the recoverable
    /// primary key, otherwise the recipient's npub-style short form.
    private func lockedKeyLabel(_ key: String) -> String {
        if let primary = settings.primaryP2PKPublicKey,
           normalizeForCompare(primary) == normalizeForCompare(key) {
            return "Your key"
        }
        return P2PKKeyDisplay.shortLabel(forPubkey: key)
    }

    private func normalizeForCompare(_ pubkey: String) -> String {
        let s = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.count == 66, s.hasPrefix("02") || s.hasPrefix("03") { return String(s.dropFirst(2)) }
        return s
    }

    // MARK: - Token Display View

    private func tokenDisplayView(token: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // QR Code — same dimensions and corner radius as the
                    // Lightning Invoice screen for visual consistency.
                    // Cashu tokens often exceed a single QR's capacity so
                    // UR encoding stays on, but the SPEED/SIZE dev HUD is
                    // suppressed from production.
                    QRCodeView(content: token, showControls: false)
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 8)
                        .contextMenu {
                            Button(action: { copyToken(token) }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            Button(action: { showShareSheet = true }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            if !settings.checkSentTokens {
                                Button(action: {
                                    Task { await checkTokenClaimNow(token: token) }
                                }) {
                                    Label("Check Status", systemImage: "arrow.clockwise")
                                }
                            }
                        }

                    // Amount — sats keep the fiat-flip display; a non-sat token
                    // shows its own unit directly.
                    if generatedIsSat {
                        CurrencyAmountDisplay(
                            sats: generatedAmount,
                            primary: $settings.amountDisplayPrimary,
                            primarySize: 32
                        )
                    } else {
                        Text(CurrencyAmount(value: generatedAmount, currency: generatedUnitCurrency).formatted())
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                    }

                    // Status — inline badge transition, then dismiss + toast.
                    Group {
                        if tokenClaimed {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolEffect(.bounce, value: reduceMotion ? false : tokenClaimed)
                                Text("Claimed")
                            }
                            // Monochrome, not green: green is reserved for the 64pt
                            // hero success checks (DESIGN.md retired the small worded
                            // green ✓ badge). The settled state reads .primary.
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                        } else if isCheckingClaim {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.8)
                                Text("Checking...")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                                Text("Pending")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.7), value: tokenClaimed)
                    .animation(.easeInOut(duration: 0.2), value: isCheckingClaim)

                    // Detail rows on canvas with hairline dividers — same
                    // pattern as the Lightning Invoice screen.
                    VStack(spacing: 0) {
                        // Sender's send fee — zero unless the send needed a
                        // change swap. The receiver's redeem fee is shown on
                        // their side, so a "0 sat" row here only misleads.
                        if tokenFee > 0 {
                            detailRow(icon: "arrow.up.arrow.down", label: "Fee", value: generatedFeeText)
                            canvasDivider
                        }
                        detailRow(icon: "banknote", label: "Unit", value: generatedTokenUnit.uppercased())
                        // Fiat conversion is only meaningful for sats, only when
                        // the user opted into fiat balances, and only for amounts
                        // worth at least a cent — matches Android's gating.
                        if generatedIsSat, settings.showFiatBalance,
                           let fiatValue = priceService.formatSatsAsFiat(generatedAmount) {
                            canvasDivider
                            detailRow(icon: "banknote", label: "Fiat", value: fiatValue)
                        }
                        if let mintURL = generatedTokenMintURL {
                            canvasDivider
                            detailRow(icon: "bitcoinsign.bank.building", label: "Mint",
                                      value: extractMintHost(mintURL))
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal)
            }

            Button(action: { copyToken(token) }) {
                Text(copyButtonText)
            }
            .glassButton()
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .onAppear {
            guard settings.checkSentTokens else { return }
            startClaimPolling(token: token)
        }
    }

    /// Full-screen success shown once the recipient claims the token — the exact
    /// same `PaymentStatusView` the pay/receive flows use, so "Claimed" reads
    /// identically to a sent payment (checkmark → title → detail block → Done).
    /// Stays until the user taps Done.
    private var claimedSuccessView: some View {
        PaymentStatusView(
            details: claimedSuccessRows,
            phase: .success,
            successTitle: "Claimed",
            onDone: { dismiss() },
            onRetry: {}
        )
    }

    private var claimedSuccessRows: [PaymentStatusView.DetailRow] {
        let amountText = generatedIsSat
            ? AmountFormatter.sats(generatedAmount, useBitcoinSymbol: settings.useBitcoinSymbol)
            : CurrencyAmount(value: generatedAmount, currency: generatedUnitCurrency).formatted()
        var rows: [PaymentStatusView.DetailRow] = [
            .init(icon: "bitcoinsign", label: "Amount", value: amountText),
        ]
        if tokenFee > 0 {
            rows.append(.init(icon: "arrow.up.arrow.down", label: "Fee", value: generatedFeeText))
        }
        if let mintURL = generatedTokenMintURL {
            rows.append(.init(
                icon: "bitcoinsign.bank.building",
                label: "Mint",
                value: extractMintHost(mintURL)
            ))
        }
        return rows
    }

    // MARK: - Generated-token display helpers

    private var generatedIsSat: Bool { generatedTokenUnit.lowercased() == "sat" }
    private var generatedUnitCurrency: any Currency { CurrencyRegistry.currency(forMintUnit: generatedTokenUnit) }
    private var generatedFeeText: String {
        generatedIsSat ? "\(tokenFee) sat" : CurrencyAmount(value: tokenFee, currency: generatedUnitCurrency).formatted()
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    private var canvasDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.leading, 28)
    }

    private func formatBalance(_ sats: UInt64) -> String {
        AmountFormatter.sats(sats, useBitcoinSymbol: settings.useBitcoinSymbol)
    }

    /// Secondary line under an insufficient-balance notice: what's actually here.
    private var insufficientBalanceDetail: String? {
        guard let mint = displaySendMint else { return nil }
        return "You have \(sendBalanceText) in \(mint.name)."
    }

    private func presentError(_ message: String, severity: ErrorSeverity = .error, showsMintAction: Bool = false, detail: String? = nil) {
        errorMessage = message
        errorSeverity = severity
        errorShowsMintAction = showsMintAction
        errorDetail = detail
    }

    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    // MARK: - Actions

    private func generateToken() {
        let amount = amountBaseUnits
        guard amount > 0 else { return }
        guard let mint = displaySendMint else {
            presentError("No mint available.")
            return
        }
        let unit = effectiveSendUnit
        let selectedP2PKPubkey = lockWithP2PK ? normalizedP2PKPubkeyInput : nil
        guard !lockWithP2PK || selectedP2PKPubkey != nil else {
            presentError("Choose a valid key to lock to.")
            return
        }

        isGenerating = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let result = try await walletManager.sendTokens(
                    amount: amount,
                    memo: memo.isEmpty ? nil : memo,
                    p2pkPubkey: selectedP2PKPubkey,
                    mintUrl: mint.url,
                    unit: unit
                )
                generatedToken = result.token
                generatedTokenMintURL = mint.url
                generatedTokenUnit = unit
                generatedAmount = amount
                tokenFee = result.fee
                HapticFeedback.notification(.success)
            } catch {
                let walletMessage = error.walletMessage
                if error.isInsufficientBalanceError, amount <= effectiveSendBalance {
                    // The balance covers the amount, but the swap that makes
                    // change for it carries a fee the remainder can't absorb —
                    // the plain "Not enough balance." reads as a wallet bug when
                    // the user typed exactly what the screen says they hold.
                    presentError(
                        "Not enough balance to cover the mint fee.",
                        severity: .caution,
                        detail: "The mint charges a fee to make change for this amount. Try Send Max."
                    )
                } else {
                    presentError(
                        walletMessage.text,
                        severity: walletMessage.severity,
                        showsMintAction: error.isInsufficientBalanceError
                    )
                }
                HapticFeedback.notification(.error)
            }
            isGenerating = false
        }
    }

    private var normalizedP2PKPubkeyInput: String? {
        Self.normalizeP2PKPubkey(p2pkPubkeyInput)
    }

    /// Normalizes a P2PK public key string: accepts a 66-char `02`/`03`-prefixed
    /// hex key, or bare 64-char hex (auto-prefixed `02`). Returns nil for anything
    /// else — including Nostr `npub`s, which this scheme can't lock to.
    static func normalizeP2PKPubkey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        let allHex = trimmed.unicodeScalars.allSatisfy { hexChars.contains($0) }

        if trimmed.count == 64 && allHex {
            return "02\(trimmed)"
        }

        guard trimmed.count == 66,
              (trimmed.hasPrefix("02") || trimmed.hasPrefix("03")),
              allHex else {
            return nil
        }

        return trimmed
    }

    // MARK: - Lock Ecash

    /// Lock-flow intake: a scanned/pasted public key arms P2PK locking for the
    /// next send; invalid input (junk, or an `npub`) is rejected.
    private func handleScannedPubkey(_ scanned: String) {
        guard let normalized = Self.normalizeP2PKPubkey(scanned) else {
            presentError("That's not a valid public key.")
            HapticFeedback.notification(.error)
            return
        }
        p2pkPubkeyInput = normalized
        lockWithP2PK = true
        errorMessage = nil
        HapticFeedback.notification(.success)
    }

    private func lockQuickFills() -> [ScannerWrapperView.ScannerQuickFill] {
        var fills: [ScannerWrapperView.ScannerQuickFill] = []
        // "Lock to my key" is opt-in via Settings → Locked Ecash → Quick lock to my key.
        if settings.showP2PKButtonInDrawer, let myKey = settings.primaryP2PKPublicKey {
            fills.append(.init(title: "Lock to my key", systemImage: "key.fill", value: myKey))
        }
        if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           Self.normalizeP2PKPubkey(clip) != nil {
            fills.append(.init(title: "Paste key", systemImage: "doc.on.clipboard", value: clip))
        }
        return fills
    }

    private func copyToken(_ token: String) {
        UIPasteboard.general.string = token
        HapticFeedback.notification(.success)

        // Show "COPIED" feedback for 3 seconds
        copyButtonText = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copyButtonText = "Copy"
        }
    }

    // MARK: - Token Claim Detection

    private func startClaimPolling(token: String) {
        // Cancel any existing task
        checkingTask?.cancel()

        isCheckingClaim = true

        checkingTask = Task {
            let maxChecks = 10
            let maxInterval: UInt64 = 15_000_000_000
            var checkCount = 0
            var interval: UInt64 = 5_000_000_000

            while !Task.isCancelled && !tokenClaimed && checkCount < maxChecks {
                try? await Task.sleep(nanoseconds: interval)

                guard !Task.isCancelled else { break }

                // Check if token has been spent
                let isSpent = await walletManager.checkTokenSpendable(token: token)

                if isSpent {
                    // Flipping `tokenClaimed` swaps the body to the full-screen
                    // success (owns its own success haptic on appear, so don't
                    // buzz here). It stays until the user taps Done.
                    await MainActor.run {
                        tokenClaimed = true
                        isCheckingClaim = false
                    }

                    // Remove from pending and reload transactions so HistoryView updates
                    // We need to find the pending token ID - it's stored when we create the token
                    await walletManager.markTokenAsClaimed(token: token)
                    break
                }

                checkCount += 1
                interval = min(interval + 1_000_000_000, maxInterval)
            }

            await MainActor.run {
                isCheckingClaim = false
            }
        }
    }

    private func checkTokenClaimNow(token: String) async {
        await MainActor.run {
            isCheckingClaim = true
        }

        let isSpent = await walletManager.checkTokenSpendable(token: token)
        if isSpent {
            // Full-screen success owns the screen + its haptic; stays until Done.
            await MainActor.run {
                tokenClaimed = true
            }
            await walletManager.markTokenAsClaimed(token: token)
        }

        await MainActor.run {
            isCheckingClaim = false
        }
    }
}

// MARK: - Melt View

// MARK: - Mint + amount selector row

/// The shared amount-entry mint row used by every keypad screen (Create ecash and
/// the unified Send amount step). A tappable mint identity (avatar + balance) on the
/// left, then a "Send Max" pill, then the mint-picker chevron at the far right — so
/// the dropdown affordance reads clearly without crowding the balance.
struct MintAmountSelectorRow: View {
    let mint: MintInfo
    let balanceText: String
    let onChooseMint: () -> Void
    let onUseMax: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onChooseMint) {
                HStack(spacing: 12) {
                    MintAvatarView(iconUrl: mint.iconUrl, name: mint.name, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mint.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(balanceText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Paying mint: \(mint.name), \(balanceText)")

            Spacer(minLength: 8)

            Button(action: onUseMax) {
                Text("Send Max")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Fill the amount with your full mint balance")

            Button(action: onChooseMint) {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose a different mint")
        }
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12), interactive: true)
    }
}

/// The shared mint pill for the single-screen payment confirms (Pay Lightning and
/// Pay Cashu Request). A tappable mint identity — avatar + name + balance — with a
/// switch chevron, on Liquid Glass; tapping opens the mint picker via `onTap`. Keeps
/// the two scanner confirms visually identical without duplicating the pill.
struct MintConfirmSelectorRow: View {
    let mint: MintInfo
    var balanceText: String? = nil
    let onTap: () -> Void

    private var resolvedBalance: String { balanceText ?? "\(mint.balance) sat" }

    var body: some View {
        Button(action: {
            HapticFeedback.selection()
            onTap()
        }) {
            HStack(spacing: 12) {
                MintAvatarView(iconUrl: mint.iconUrl, name: mint.name, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mint.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(resolvedBalance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Paying mint: \(mint.name), \(resolvedBalance)")
        .accessibilityHint("Double-tap to choose the mint to pay from")
    }
}

// MARK: - Unified destination-first Send

/// The single entry point for sending — one grounded screen modeled on the Family
/// wallet. The title "Send" and a pinned "To [recipient]" pill stay put; only the
/// area below transitions through steps: input → amount keypad → confirm(fee) →
/// sending → sent. A "Send to" field accepts a Lightning address, BOLT11 invoice,
/// BOLT12 offer, on-chain address, or Cashu request; detecting a valid destination
/// advances automatically (paste/scan/recent immediately, hand-typing after a short
/// settle). The pay/confirm logic mirrors `MeltView` and `CashuPaymentRequestPayView`
/// (same `walletManager` calls) but is hosted in-place so the screen stays grounded.
/// A pasted bearer *token* routes out to the Receive-this claim screen.
struct UnifiedSendView: View {
    /// Pre-fills the destination field on open — used when the Receive sheet
    /// hands a pasted/scanned *payable* (invoice, address, Cashu Request) back to
    /// Send. Consumed once, then decoded exactly like a paste.
    var initialDestination: String? = nil
    let onClose: () -> Void
    /// CTA out of the zero-balance empty state — opens the Receive chooser.
    let onReceive: () -> Void
    /// "Add custom mint URL" out of the no-mints empty state.
    let onAddCustomMint: () -> Void
    /// Start the NFC tap-to-pay session (dismisses this sheet first).
    let onContactless: () -> Void

    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    // Step machine
    @State private var step: Step = .input
    @State private var destination = ""
    @State private var locked: LockedDestination?

    // Amount + melt quote
    @State private var amountString = ""
    @State private var meltQuote: MeltQuoteInfo?
    @State private var selectedMint: MintInfo?
    /// True when the mint accepted the melt for asynchronous (NUT-05) settlement —
    /// typical for on-chain — so the success screen says "processing", not "sent".
    @State private var meltSettlementPending = false

    // Cashu-request live fee (ported from CashuPaymentRequestPayView)
    @State private var feeState: FeeState = .idle
    @State private var feePpkByMint: [String: UInt64] = [:]
    @State private var feeTask: Task<Void, Never>?

    // Cashu-request "add mint & pay" recovery (mirrors CashuPaymentRequestPayView)
    @State private var selectedAddMintURL: String?
    @State private var addMintChooserPresented = false
    @State private var topUpContext: TopUpContext?

    // Flow control
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var errorSeverity: ErrorSeverity = .error
    @State private var errorShowsMintAction = false
    @State private var errorIsTerminal = false
    /// Persisted across confirmation → processing/success/failure so a
    /// rail-changing or recovery route cannot disappear as wallet state updates.
    @State private var activeRouteExplanation: CashuRequestRouteExplanation?
    @State private var inputHint: String?
    @State private var autoAdvanceTask: Task<Void, Never>?
    /// Set when the user taps the pill to edit: auto-advance stays suppressed while
    /// the field text equals this value, so a still-valid recipient doesn't bounce
    /// straight back forward. Cleared the instant the text differs.
    @State private var suppressedValue: String?
    /// Guards `initialDestination` so a pre-filled payable is consumed only once.
    @State private var didConsumeInitialDestination = false

    private func presentError(_ message: String, severity: ErrorSeverity = .error) {
        errorMessage = message
        errorSeverity = severity
        errorShowsMintAction = false
        errorIsTerminal = false
    }

    private func presentError(from error: Error) {
        let walletMessage = error.walletMessage
        errorMessage = walletMessage.text
        errorSeverity = walletMessage.severity
        errorShowsMintAction = error.isInsufficientBalanceError
        errorIsTerminal = walletMessage.recoverability == .terminal
    }

    /// Secondary line under an insufficient-balance notice: what's actually here.
    private var meltInsufficientDetail: String? {
        guard let mint = activeMeltMint else { return nil }
        return "You have \(AmountFormatter.sats(mint.balance, useBitcoinSymbol: settings.useBitcoinSymbol)) in \(mint.name)."
    }

    /// The unified error surface for this flow. Insufficient-balance errors carry the
    /// live mint balance as a second line; the recovery action lives in the bottom
    /// CTA (see `meltConfirmBody`), never inside the notice.
    @ViewBuilder
    private func errorNotice(_ message: String) -> some View {
        InlineNotice(
            message: message,
            severity: errorSeverity,
            detail: errorShowsMintAction ? meltInsufficientDetail : nil,
            tinted: true
        )
    }

    /// Another compatible mint exists to fall back to when this one is short.
    private var canSwitchMintForBalance: Bool {
        errorShowsMintAction && meltCompatibleMints.count > 1
    }

    /// A melt failure is terminal (offer "Done", not a futile retry) when the error is a
    /// permanent fact, or when its only recovery — switching mints — isn't available.
    private var meltFailureIsTerminal: Bool {
        errorIsTerminal || (errorShowsMintAction && !canSwitchMintForBalance)
    }

    /// "Choose another mint" recovery for an insufficient-balance quote failure, when a
    /// compatible mint exists to fall back to. Only offered on the confirm step, where
    /// picking a mint re-fetches the quote.
    private var meltSwitchMintCTA: PaymentStatusView.FailureCTA? {
        guard case .melt = locked, step == .confirm, canSwitchMintForBalance else { return nil }
        return .init(title: "Choose another mint") {
            HapticFeedback.selection()
            showingMintPicker = true
        }
    }

    // Routes that genuinely leave this flow + scanner / mint picker / empty state
    @State private var route: SendRoute?
    @State private var showingScanner = false
    @State private var showingMintPicker = false
    @State private var addMintError: String?

    /// Measured height of the compact input-step body (field + methods / empty
    /// states). Drives a content-fit detent so Scan/Ecash/Tap stay thumb-reachable
    /// instead of sitting at the bottom of a `.large` sheet.
    @State private var compactContentHeight: CGFloat = 0

    /// Fixed sheet chrome around measured content: drag indicator + inline nav
    /// bar + a little extra so the sheet sits just above the elements.
    private static let compactSheetChrome: CGFloat = 108
    /// First-frame estimate before geometry lands so the sheet doesn't open tiny.
    private static let compactBodyEstimate: CGFloat = 220

    enum Step: Equatable { case input, amount, confirm, sending, sent, failed }

    enum LockedDestination: Equatable {
        case melt(request: String, mode: MeltView.MeltMode, decoded: PaymentRequestDecodeResult)
        case cashuRequest(CashuPaymentRequestSummary)
    }

    /// Resolved fee for the current creq mint + amount.
    private enum FeeState: Equatable { case idle, loading, free, amount(UInt64), unavailable }

    /// The two destinations that leave the Send flow entirely (presented full-screen,
    /// each keeping its own NavigationStack).
    private enum SendRoute: Identifiable {
        case receiveToken(String)
        case ecash
        var id: String {
            switch self {
            case .receiveToken(let token): return "token-\(token.prefix(48))"
            case .ecash: return "ecash"
            }
        }
    }

    // MARK: Body

    /// Input step (with balance, or empty states) hugs content. Amount / confirm /
    /// status expand to `.large` so the keypad and pay scaffold have room.
    private var prefersCompactSheet: Bool {
        statusPhase == nil && step == .input
    }

    private var compactDetentHeight: CGFloat {
        let body = compactContentHeight > 0 ? compactContentHeight : Self.compactBodyEstimate
        return body + Self.compactSheetChrome
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Amount-keypad step keeps the "To" pill up here; the confirm step renders
                // its own mint + "To" header in the scaffold's floating topAccessory.
                if let locked, step == .amount, statusPhase == nil {
                    toPill(locked)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                Group {
                    if let statusPhase {
                        // Single branch keeps the status screen's identity stable across
                        // processing → sent → failed, so PaymentStatusView owns the morph.
                        statusView(statusPhase)
                            .transition(.opacity)
                    } else {
                        switch step {
                        case .input: inputContent
                        case .amount: amountStep
                        case .confirm: confirmStep
                        case .sending, .sent, .failed: EmptyView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                // Compact input sizes intrinsically so the detent can hug it; later
                // steps fill the large sheet.
                .frame(maxHeight: prefersCompactSheet ? nil : .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(maxHeight: prefersCompactSheet ? nil : .infinity, alignment: .top)
            .animation(.smooth(duration: 0.3), value: step)
            .animation(.smooth(duration: 0.3), value: locked != nil)
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingScanner) {
                ScannerWrapperView(onScanned: handleScannedDestination)
                    .environmentObject(walletManager)
                    .canvasSheetBackground()
            }
            .sheet(isPresented: $showingMintPicker) { mintPickerSheet }
            .sheet(item: $topUpContext) { context in
                CashuTopUpInvoiceSheet(context: context, onComplete: {
                    topUpContext = nil
                    onClose()
                })
                .environmentObject(walletManager)
                .canvasSheetBackground()
            }
            .fullScreenCover(item: $route) { routeView($0).canvasSheetBackground() }
            .onChange(of: destination) { handleDestinationChange() }
            .onChange(of: entryUnit) { oldUnit, newUnit in
                amountString = AmountFormatter.entryConverted(raw: amountString, from: oldUnit, to: newUnit)
            }
            .onAppear {
                guard !didConsumeInitialDestination,
                      let initialDestination,
                      !initialDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                didConsumeInitialDestination = true
                destination = initialDestination
                advanceNow(raw: initialDestination)
            }
            .onDisappear {
                autoAdvanceTask?.cancel()
                feeTask?.cancel()
            }
        }
        // Own the sheet chrome so the detent can follow the step: compact for
        // input, `.large` + flat canvas for amount/confirm/status.
        .presentationDetents(prefersCompactSheet ? [.height(compactDetentHeight)] : [.large])
        .presentationDragIndicator(.visible)
        .modifier(UnifiedSendSheetBackground(compact: prefersCompactSheet))
    }

    // MARK: Input step

    @ViewBuilder
    private var inputContent: some View {
        if walletManager.mints.isEmpty {
            noMintsState
        } else if !walletManager.hasAnyBalance {
            noBalanceState
        } else {
            inputForm
        }
    }

    private var inputForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                destinationField
                    .padding(.horizontal)
                    .padding(.top, 12)

                if let inputHint {
                    InlineNotice(message: inputHint, severity: .caution)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }

                // A centered row of round Liquid Glass icon buttons — the primary
                // "ways to send" (Scan · Ecash · Tap), one-word label under each.
                sendMethodRow
                    .padding(.horizontal)
                    .padding(.top, 32)
            }
            .padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                compactContentHeight = newHeight
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Send-method buttons

    /// The primary "ways to send" as a centered row of round filled icon
    /// buttons (Apple's sheet-action-circle pattern; same component as Receive).
    private var sendMethodRow: some View {
        HStack(spacing: 40) {
            sendMethodButton(icon: "qrcode.viewfinder", label: "Scan",
                             a11y: "Scan QR code", action: openScanner)

            sendMethodButton(icon: "banknote", label: "Ecash",
                             a11y: "Create ecash") {
                HapticFeedback.selection()
                route = .ecash
            }

            if NFCNDEFReaderSession.readingAvailable {
                sendMethodButton(icon: "wave.3.right", label: "Tap",
                                 a11y: "Contactless, tap to pay nearby") {
                    HapticFeedback.selection()
                    onContactless()
                }
            }
        }
        .frame(maxWidth: .infinity)   // center the group on the leading-aligned canvas
    }

    /// One round filled icon button with a one-word caption on the canvas below it.
    /// Delegates to the shared `CircularGlassIconButton` so the Send and Receive
    /// sheets stay pixel-identical.
    private func sendMethodButton(
        icon: String, label: String, a11y: String,
        action: @escaping () -> Void
    ) -> some View {
        CircularGlassIconButton(icon: icon, label: label, a11y: a11y, action: action)
    }

    private var destinationField: some View {
        HStack(alignment: .top, spacing: 12) {
            TextField("Address, invoice, or Cashu Request", text: $destination, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if UIPasteboard.general.hasStrings {
                    Button("Paste", action: pasteFromClipboard)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Paste from clipboard")
                }
            } else {
                Button {
                    HapticFeedback.selection()
                    destination = ""
                } label: {
                    // Padding expands the hit area; the negative outer padding
                    // cancels the layout growth so the field row keeps its height.
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .contentShape(Rectangle())
                        .padding(-10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding()
        .liquidGlassInput(in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Pinned "To" pill

    private func toPill(_ locked: LockedDestination) -> some View {
        Button(action: editFromPill) {
            HStack(spacing: 10) {
                Text("To")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(pillValue(locked))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .liquidGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(statusPhase != nil)
        .accessibilityLabel("Recipient \(pillValue(locked))")
        .accessibilityHint("Double-tap to change the recipient")
    }

    /// Confirm-step header: the standard top mint selector stacked over the "To" pill.
    /// Lives in the scaffold's floating `topAccessory` so neither pill shifts the
    /// anchored amount hero (see `PayFlowScaffold`). The mint is `nil` for Cashu-request
    /// states with no held mint — those keep an actionable row in the details instead.
    @ViewBuilder
    private func confirmHeader(mint: MintInfo?, locked: LockedDestination?) -> some View {
        if let locked {
            VStack(spacing: 8) {
                if let mint {
                    MintConfirmSelectorRow(mint: mint, onTap: { showingMintPicker = true })
                }
                toPill(locked)
            }
            .padding(.horizontal)
            .padding(.top, 12)
        }
    }

    private func pillValue(_ locked: LockedDestination) -> String {
        switch locked {
        case .melt(let request, _, let decoded):
            if case .lightningAddress(let addr) = decoded { return addr }
            return PaymentRequestDecoder.shortRepresentation(request, result: decoded)
        case .cashuRequest(let summary):
            // Mirror the Lightning pill: show the opaque request string, truncated. The
            // memo still surfaces in the confirm's dedicated Memo detail row.
            return PaymentRequestDecoder.middleTruncated(summary.encoded)
        }
    }

    private func editFromPill() {
        HapticFeedback.selection()
        suppressedValue = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        meltQuote = nil
        feeTask?.cancel()
        feeState = .idle
        errorMessage = nil
        withAnimation(.smooth(duration: 0.3)) { step = .input }
    }

    // MARK: Auto-advance

    private func handleDestinationChange() {
        autoAdvanceTask?.cancel()
        inputHint = nil
        guard step == .input else { return }
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suppressed = suppressedValue {
            if trimmed == suppressed { return }   // unchanged after a pill-edit — don't bounce
            suppressedValue = nil                  // text genuinely changed — resume
        }
        guard !trimmed.isEmpty else { return }
        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, step == .input,
                  destination.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            let result = PaymentRequestDecoder.decode(
                trimmed, includeCashuPaymentRequests: true, preferCashuPaymentRequests: true
            )
            advance(result, raw: trimmed)
        }
    }

    /// Skip the typing debounce — used for paste, scan, and recents (discrete,
    /// high-confidence events).
    private func advanceNow(raw: String) {
        autoAdvanceTask?.cancel()
        let result = PaymentRequestDecoder.decode(
            raw, includeCashuPaymentRequests: true, preferCashuPaymentRequests: true
        )
        advance(result, raw: raw)
    }

    /// Lock the destination and move to the right step. Setting `step` away from
    /// `.input` makes any in-flight debounce bail on its own re-check.
    private func advance(_ result: PaymentRequestDecodeResult, raw: String) {
        switch result {
        case .bolt11, .bolt12:
            if let notice = result.amountlessMeltCaution {
                // Amountless invoice/offer can't be paid without an amount we don't
                // collect here — stay on input with a clean caution instead of routing
                // to a quote that only fails with raw mint jargon.
                inputHint = notice
                return
            }
            let request = PaymentRequestDecoder.encodedLightningRequest(from: raw)
                ?? PaymentRequestParser.normalizeLightningRequest(raw)
            lockMelt(request: request, mode: .lightning, decoded: result)
            startMeltConfirm()   // amount carried by the invoice
        case .lightningAddress(let address):
            lockMelt(request: address, mode: .lightning, decoded: result)
            goToAmount()
        case .onchain:
            lockMelt(request: PaymentRequestParser.normalizeBitcoinRequest(raw), mode: .onchain, decoded: result)
            goToAmount()
        case .cashuPaymentRequest(let summary):
            // Prefer ecash when a held mint can pay; otherwise fall back to a
            // bundled bolt11 (BIP-321) rather than dead-ending on an unheld mint.
            switch walletManager.routeForCashuPaymentRequest(summary, rawContent: raw) {
            case .payWithEcash, .acquireThenPay:
                locked = .cashuRequest(summary)
                activeRouteExplanation = nil
                selectedMint = nil
                errorMessage = nil
                HapticFeedback.selection()
                if summary.amount != nil {
                    withAnimation(.smooth(duration: 0.3)) { step = .confirm }
                    recomputeFee()
                } else {
                    goToAmount()
                }
            case .payBolt11Fallback(let bolt11):
                lockMelt(
                    request: bolt11,
                    mode: .lightning,
                    decoded: PaymentRequestDecoder.decode(bolt11),
                    routeExplanation: CashuRequestRouteExplanation(state: .lightningFallback)
                )
                startMeltConfirm()
            }
        case .unrecognized:
            if let token = TokenParser.normalizedToken(from: raw) {
                HapticFeedback.selection()
                route = .receiveToken(token)
            } else {
                inputHint = "Unrecognized — try a Lightning address, invoice, Bitcoin address, or Cashu Request"
            }
        }
    }

    private func lockMelt(
        request: String,
        mode: MeltView.MeltMode,
        decoded: PaymentRequestDecodeResult,
        routeExplanation: CashuRequestRouteExplanation? = nil
    ) {
        locked = .melt(request: request, mode: mode, decoded: decoded)
        activeRouteExplanation = routeExplanation
        selectedMint = nil
        meltQuote = nil
        errorMessage = nil
    }

    private func goToAmount() {
        amountString = ""
        HapticFeedback.selection()
        withAnimation(.smooth(duration: 0.3)) { step = .amount }
    }

    private func startMeltConfirm() {
        HapticFeedback.selection()
        withAnimation(.smooth(duration: 0.3)) { step = .confirm }
        fetchMeltQuote()
    }

    // MARK: Amount step

    private var amountStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    CurrencyAmountDisplay(
                        sats: amountSats,
                        primary: $settings.amountDisplayPrimary,
                        entryRaw: amountString
                    )
                    .padding(.top, 24)

                    if let mint = currentAmountMint {
                        amountMintRow(mint)
                            .padding(.horizontal)
                    }

                    if let errorMessage {
                        errorNotice(errorMessage)
                            .padding(.horizontal)
                    }
                }
            }

            NumberPadAmountInput(amountString: $amountString, unit: entryUnit)
                .padding(.horizontal, 24)

            Button(action: continueFromAmount) {
                Text("Continue")
            }
            .glassButton()
            .disabled(amountSats == 0)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private func amountMintRow(_ mint: MintInfo) -> some View {
        MintAmountSelectorRow(
            mint: mint,
            balanceText: AmountFormatter.sats(mint.balance, useBitcoinSymbol: settings.useBitcoinSymbol),
            onChooseMint: {
                HapticFeedback.selection()
                showingMintPicker = true
            },
            onUseMax: useMax
        )
    }

    private func useMax() {
        guard let mint = currentAmountMint else { return }
        HapticFeedback.selection()
        amountString = AmountFormatter.entryConverted(raw: String(mint.balance), from: .sats, to: entryUnit)
    }

    private func continueFromAmount() {
        guard amountSats > 0 else { return }
        HapticFeedback.selection()
        switch locked {
        case .melt:
            withAnimation(.smooth(duration: 0.3)) { step = .confirm }
            fetchMeltQuote()
        case .cashuRequest:
            withAnimation(.smooth(duration: 0.3)) { step = .confirm }
            recomputeFee()
        case nil:
            break
        }
    }

    // MARK: Confirm step

    @ViewBuilder
    private var confirmStep: some View {
        switch locked {
        case .melt:
            meltConfirmBody
        case .cashuRequest(let summary):
            creqConfirmBody(summary)
        case nil:
            EmptyView()
        }
    }

    /// Melt confirm: the amount is the only prominent element; the mint, fee, and
    /// (on-chain) destination sit beneath as equal-weight detail rows.
    private var meltConfirmBody: some View {
        let displayAmount = meltQuote?.amount ?? knownMeltAmount ?? 0
        let canPay = meltQuote.map { hasSufficientBalance(for: $0) } ?? false
        // One scaffold for both the in-flight and resolved states so the amount hero shows
        // the instant paste → confirm lands and the fee rows fill in place (see
        // `meltConfirmRows`) — no bare-spinner screen, no view swap, matching the Cashu-
        // request confirm. Quote failures stay on this confirmation screen with an inline
        // error and retry action; only an actual `meltTokens` attempt may enter the shared
        // payment-failure screen.
        return VStack(spacing: 0) {
            PayFlowScaffold {
                CurrencyAmountDisplay(sats: displayAmount, primary: $settings.amountDisplayPrimary)
            } details: {
                meltConfirmRows(meltQuote)

                if let quote = meltQuote,
                   !hasSufficientBalance(for: quote),
                   let balance = mintInfo(for: quote)?.balance {
                    InlineNotice(
                        message: "This mint holds \(AmountFormatter.sats(balance, useBitcoinSymbol: settings.useBitcoinSymbol)); the payment reserves up to \(AmountFormatter.sats(quote.totalAmount, useBitcoinSymbol: settings.useBitcoinSymbol)).",
                        severity: .caution
                    )
                    .padding(.top, 12)
                    .padding(.horizontal)
                }

                if let errorMessage {
                    errorNotice(errorMessage)
                        .padding(.top, 12)
                        .padding(.horizontal)
                }
            } footer: {
                EmptyView()
            } topAccessory: {
                confirmHeader(mint: meltQuote.flatMap(mintInfo(for:)) ?? activeMeltMint, locked: locked)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: {
                if meltQuote == nil {
                    fetchMeltQuote()
                } else {
                    payMelt()
                }
            }) {
                if isWorking {
                    ProgressView()
                } else if meltQuote == nil {
                    Text("Retry Quote")
                } else {
                    Text("Pay \(displayAmount) sat")
                }
            }
            .glassButton()
            .disabled(isWorking || (meltQuote != nil && !canPay))
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private var meltCompatibleMints: [MintInfo] {
        availableMeltMints.filter { $0.supportedMeltMethods.contains(meltPaymentMethod) }
    }

    /// Read-only summary rows: the on-chain destination (where the pill truncates), the
    /// network fee, and the total that leaves the balance — all equal-weight details
    /// beneath the amount. The source mint now lives in the top header pill.
    private func meltConfirmRows(_ quote: MeltQuoteInfo?) -> some View {
        // While the mint quote is in flight (`quote == nil`) the fee + total render as
        // skeleton placeholders that fill in place when it lands. The on-chain "To" row is
        // driven by the locked mode (not the quote) so it holds its slot across the fill-in.
        let isLoading = quote == nil
        let isOnchain: Bool = { if case .melt(_, .onchain, _) = locked { return true } else { return false } }()
        return VStack(spacing: 0) {
            if isOnchain, case let .melt(request, _, _) = locked {
                creqDetailRow(icon: "arrow.up.right", label: "To", value: request)
                creqDivider
            }
            if let explanation = activeRouteExplanation {
                CashuRequestRouteExplanationRow(explanation: explanation)
                creqDivider
            }
            creqDetailRow(
                icon: "arrow.up.arrow.down",
                label: "Network fee",
                value: AmountFormatter.sats(quote?.feeReserve ?? 0, useBitcoinSymbol: settings.useBitcoinSymbol)
            )
            .redacted(reason: isLoading ? .placeholder : [])
            creqDivider
            creqDetailRow(
                icon: "creditcard",
                label: "Total",
                value: AmountFormatter.sats(quote?.totalAmount ?? 0, useBitcoinSymbol: settings.useBitcoinSymbol)
            )
            .redacted(reason: isLoading ? .placeholder : [])
        }
        .padding(.top, 16)
        .padding(.horizontal)
        .animation(.smooth(duration: 0.3), value: isLoading)
    }

    /// Shared mint detail row (used by both the melt and Cashu-request confirms):
    /// a "From"/"Mint" label, the mint avatar + name, and a chevron when the mint
    /// can be switched. Tapping a switchable row opens the mint picker.
    @ViewBuilder
    private func mintDetailRow(label: String, mint: MintInfo, switchable: Bool) -> some View {
        let content = HStack(spacing: 8) {
            Label(label, systemImage: "bitcoinsign.bank.building")
                .foregroundStyle(.secondary)
            Spacer()
            MintAvatarView(iconUrl: mint.iconUrl, name: mint.name, size: 22)
            Text(mint.name)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if switchable {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)

        if switchable {
            Button(action: {
                HapticFeedback.selection()
                showingMintPicker = true
            }) {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pay from \(mint.name)")
            .accessibilityHint("Double-tap to choose a different mint")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(label): \(mint.name)")
        }
    }

    // MARK: Sending / sent / failed — shared full-screen status

    /// Maps the three terminal steps onto the shared status screen's phase; nil for
    /// the input/amount/confirm steps.
    private var statusPhase: PaymentStatusView.Phase? {
        switch step {
        case .sending: return .processing
        case .sent:    return .success
        case .failed:
            let terminal: Bool
            if case .melt = locked { terminal = meltFailureIsTerminal } else { terminal = errorIsTerminal }
            return .failure(
                message: errorMessage ?? "Payment failed",
                isCaution: errorSeverity == .caution,
                isTerminal: terminal
            )
        case .confirm: return nil
        default:
            return nil
        }
    }

    /// Full-screen processing → success → failure status, preserving the payment
    /// facts as rows. Branches on the locked destination (melt vs Cashu request).
    private func statusView(_ phase: PaymentStatusView.Phase) -> some View {
        var rows: [PaymentStatusView.DetailRow] = []
        switch locked {
        case .melt(let request, _, _):
            if let quote = meltQuote {
                // Same row order as MeltView's status screen (Method → To → Amount →
                // fee → Mint) so both Lightning/on-chain pay screens read alike and the
                // rows stay stable through processing.
                rows.append(.init(icon: "bolt", label: "Method", value: meltPaymentMethod.displayName))
                if quote.paymentMethod == .onchain {
                    rows.append(.init(icon: "arrow.up.right", label: "To", value: request))
                }
                rows.append(.init(
                    icon: "bitcoinsign",
                    label: "Amount",
                    value: AmountFormatter.sats(quote.amount, useBitcoinSymbol: settings.useBitcoinSymbol)
                ))
                if let explanation = activeRouteExplanation {
                    rows.append(.init(
                        icon: "arrow.triangle.branch",
                        label: "Route",
                        value: explanation.localizedValue
                    ))
                }
                rows.append(.init(
                    icon: "arrow.up.arrow.down",
                    label: "Network fee",
                    value: AmountFormatter.sats(quote.feeReserve, useBitcoinSymbol: settings.useBitcoinSymbol)
                ))
                if let mint = mintInfo(for: quote) ?? activeMeltMint {
                    rows.append(.init(icon: "bitcoinsign.bank.building", label: "Mint", value: mint.name))
                }
            } else if errorShowsMintAction, let mint = activeMeltMint {
                // Insufficient-balance failure (no quote to summarise): show the mint and
                // what's actually there, so the shortfall reads as a fact, not a scold.
                rows.append(.init(icon: "bitcoinsign.bank.building", label: "Mint", value: mint.name))
                rows.append(.init(
                    icon: "banknote",
                    label: "Balance",
                    value: AmountFormatter.sats(mint.balance, useBitcoinSymbol: settings.useBitcoinSymbol)
                ))
            }
        case .cashuRequest(let creq):
            // Fixed slot order (matches CashuPaymentRequestPayView) so late-resolving
            // values (the fee, or the mint in the acquire path) fill their reserved slot
            // in place instead of inserting mid-list and shoving the rows below down.
            rows.append(.init(
                icon: "bitcoinsign",
                label: "Amount",
                value: paymentAmountForCreq.map {
                    AmountFormatter.sats($0, useBitcoinSymbol: settings.useBitcoinSymbol)
                } ?? "",
                isPending: paymentAmountForCreq == nil
            ))
            rows.append(creqStatusMintRow)
            if let explanation = activeRouteExplanation {
                rows.append(.init(
                    icon: "arrow.triangle.branch",
                    label: "Route",
                    value: explanation.localizedValue
                ))
            }
            rows.append(creqStatusFeeRow)
            if let memo = creq.description?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty {
                rows.append(.init(icon: "quote.bubble", label: "Memo", value: memo))
            }
        case nil:
            break
        }
        return PaymentStatusView(
            details: rows,
            phase: phase,
            // An async-accepted (NUT-05) melt — typical for on-chain — isn't settled
            // yet: the mint took the payment and pays out in the background.
            successTitle: meltSettlementPending ? "Payment Processing" : "Payment Sent!",
            failureCTA: meltSwitchMintCTA,
            onDone: onClose,
            onRetry: {
                // Only a failed payment reaches this status screen. Return to its
                // already-created quote so retry still requires an explicit Pay tap.
                withAnimation(.smooth(duration: 0.3)) { step = .confirm }
            }
        )
    }

    // MARK: Melt quote + pay

    private func fetchMeltQuote() {
        guard case let .melt(request, mode, decoded) = locked else { return }
        guard let mint = activeMeltMint else {
            presentError("No mint supports \(meltPaymentMethod.displayName) payments.")
            return
        }
        isWorking = true
        errorMessage = nil
        meltQuote = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let quote: MeltQuoteInfo
                switch mode {
                case .onchain:
                    let amount = amountSats
                    guard amount > 0 else { return }
                    quote = try await walletManager.createOnchainMeltQuote(
                        address: request, amount: amount, preferredMintURL: mint.url
                    )
                case .lightning:
                    if case .lightningAddress = decoded {
                        let amount = amountSats
                        guard amount > 0 else { return }
                        quote = try await walletManager.createHumanReadableMeltQuote(
                            address: request, amount: amount, preferredMintURL: mint.url
                        )
                    } else {
                        quote = try await walletManager.createMeltQuote(
                            request: request, preferredMintURL: mint.url
                        )
                    }
                }
                meltQuote = quote
                if let resolved = mintInfo(for: quote) { selectedMint = resolved }
            } catch {
                // Quote creation is a preflight, not a payment. Keep its failure inline
                // on confirm so it can never be presented as a failed melt.
                withAnimation(.smooth(duration: 0.3)) { presentError(from: error) }
            }
        }
    }

    private func payMelt() {
        guard let quote = meltQuote else { return }
        HapticFeedback.impact(.medium)
        errorMessage = nil
        withAnimation(.smooth(duration: 0.3)) { step = .sending }
        Task { @MainActor in
            do {
                let result = try await walletManager.meltTokens(quoteId: quote.id, mintUrl: quote.mintUrl)
                meltSettlementPending = result.settlement == .pending
                withAnimation(.smooth(duration: 0.3)) { step = .sent }
            } catch {
                // Keep errorMessage set so the confirm screen's notice + switch-mint
                // CTA reappear when the user taps Try Again.
                presentError(from: error)
                withAnimation(.smooth(duration: 0.3)) { step = .failed }
            }
        }
    }

    // MARK: Melt mint helpers (mirror MeltView)

    private var availableMeltMints: [MintInfo] {
        walletManager.mints.isEmpty
            ? (walletManager.activeMint.map { [$0] } ?? [])
            : walletManager.mints
    }

    private var meltPaymentMethod: PaymentMethodKind {
        guard case let .melt(_, mode, decoded) = locked else { return .bolt11 }
        if mode == .onchain { return .onchain }
        if case .bolt12 = decoded { return .bolt12 }
        return .bolt11
    }

    private var meltMinAmount: UInt64? { amountSats > 0 ? amountSats : nil }

    /// Amount known before the mint quote returns — from the invoice (bolt11/bolt12) or,
    /// for a Lightning address / on-chain send, the amount entered on the amount step. Lets
    /// the confirm show its amount hero while the quote is still in flight.
    private var knownMeltAmount: UInt64? {
        guard case let .melt(_, _, decoded) = locked else { return nil }
        switch decoded {
        case .bolt11(let amount, _), .bolt12(let amount, _):
            return amount ?? (amountSats > 0 ? amountSats : nil)
        default:
            return amountSats > 0 ? amountSats : nil
        }
    }

    private var activeMeltMint: MintInfo? {
        let compatible = availableMeltMints.filter { $0.supportedMeltMethods.contains(meltPaymentMethod) }
        if let selectedMint, let match = compatible.first(where: { $0.id == selectedMint.id }) {
            return match
        }
        return recommendedMeltMint(for: meltPaymentMethod, minimumAmount: meltMinAmount)
    }

    private func recommendedMeltMint(for paymentMethod: PaymentMethodKind, minimumAmount: UInt64?) -> MintInfo? {
        let compatible = availableMeltMints.filter { $0.supportedMeltMethods.contains(paymentMethod) }
        guard !compatible.isEmpty else { return nil }
        let affordable = compatible.filter { mint in
            guard let minimumAmount else { return true }
            return mint.balance >= minimumAmount
        }
        let candidates = affordable.isEmpty ? compatible : affordable
        if let active = walletManager.activeMint, candidates.contains(where: { $0.id == active.id }) {
            return active
        }
        return candidates.sorted { lhs, rhs in
            lhs.balance == rhs.balance
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : lhs.balance > rhs.balance
        }.first
    }

    private func mintInfo(for quote: MeltQuoteInfo) -> MintInfo? {
        walletManager.mints.first { $0.url == quote.mintUrl }
            ?? (walletManager.activeMint?.url == quote.mintUrl ? walletManager.activeMint : nil)
    }

    private func mintDisplayName(for quote: MeltQuoteInfo) -> String {
        mintInfo(for: quote)?.name ?? URL(string: quote.mintUrl)?.host ?? quote.mintUrl
    }

    private func hasSufficientBalance(for quote: MeltQuoteInfo) -> Bool {
        guard let balance = mintInfo(for: quote)?.balance else { return true }
        return balance >= quote.totalAmount
    }

    // MARK: Shared amount-entry helpers

    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    private var amountSats: UInt64 { AmountFormatter.entrySats(raw: amountString, unit: entryUnit) }

    private var currentAmountMint: MintInfo? {
        switch locked {
        case .melt: return activeMeltMint
        case .cashuRequest: return selectedPaymentMint
        case nil: return nil
        }
    }

    // MARK: Mint picker (branches on the locked destination)

    @ViewBuilder
    private var mintPickerSheet: some View {
        switch locked {
        case .melt:
            MintSelectorSheet(
                selectedMint: $selectedMint,
                paymentMethod: meltPaymentMethod,
                minimumAmount: meltMinAmount,
                onSelect: { mint in
                    selectedMint = mint
                    errorMessage = nil
                    if step == .confirm { fetchMeltQuote() }
                }
            )
            .environmentObject(walletManager)
        case .cashuRequest:
            MintSelectorSheet(
                selectedMint: $selectedMint,
                mints: candidateMints,
                minimumAmount: paymentAmountForCreq,
                onSelect: { mint in
                    selectedMint = mint
                    errorMessage = nil
                    recomputeFee()
                }
            )
            .environmentObject(walletManager)
        case nil:
            EmptyView()
        }
    }

    // MARK: Cashu-request confirm (ported from CashuPaymentRequestPayView)

    private var currentCreq: CashuPaymentRequestSummary? {
        if case .cashuRequest(let summary) = locked { return summary }
        return nil
    }

    private func creqConfirmBody(_ creq: CashuPaymentRequestSummary) -> some View {
        // Shared Pay-flow scaffold so the request facts sit at the same Y as the
        // processing / success screens.
        PayFlowScaffold {
            CurrencyAmountDisplay(
                sats: paymentAmountForCreq ?? 0,
                primary: $settings.amountDisplayPrimary
            )
        } details: {
            creqRequestDetails(creq)

            if !creq.isSatUnit {
                InlineNotice(
                    message: "This wallet can only pay sat-denominated Cashu Requests.",
                    severity: .caution
                )
                .padding(.top, 12)
                .padding(.horizontal)
            }

            if let errorMessage {
                errorNotice(errorMessage)
                    .padding(.top, 12)
                    .padding(.horizontal)
            }
        } footer: {
            Button(action: payCreq) {
                Text(creqPayButtonTitle)
            }
            .glassButton()
            .disabled(!creqCanPay)
            .padding(.horizontal)
            .padding(.bottom, 16)
            .sheet(isPresented: $addMintChooserPresented) {
                AddMintToPaySheet(mints: currentCreq?.mints ?? []) { mintURL in
                    selectedAddMintURL = mintURL
                    if let amount = paymentAmountForCreq, amount > 0 {
                        runCreqAcquireAndPay(targetMintURL: mintURL, amount: amount)
                    }
                }
                .environmentObject(walletManager)
            }
        } topAccessory: {
            confirmHeader(mint: creqTopMint(creq), locked: .cashuRequest(creq))
        }
    }

    private func payCreq() {
        // Can't pay from current ecash — add/fund the target mint, then pay.
        if needsAcquire {
            if acquireAddsNewMint, let creq = currentCreq, creq.mints.count > 1, selectedAddMintURL == nil {
                addMintChooserPresented = true
                return
            }
            guard let target = acquireTargetURL, let amount = paymentAmountForCreq, amount > 0 else { return }
            runCreqAcquireAndPay(targetMintURL: target, amount: amount)
            return
        }

        guard let creq = currentCreq, creqCanPay, let mint = selectedPaymentMint else { return }
        activeRouteExplanation = creqRouteExplanation
        HapticFeedback.impact(.medium)
        errorMessage = nil
        withAnimation(.smooth(duration: 0.3)) { step = .sending }
        Task { @MainActor in
            do {
                try await walletManager.payCashuPaymentRequest(
                    encoded: creq.encoded,
                    customAmountSats: creq.amount == nil ? paymentAmountForCreq : nil,
                    preferredMintURL: mint.url
                )
                withAnimation(.smooth(duration: 0.3)) { step = .sent }
            } catch {
                presentError(from: error)
                withAnimation(.smooth(duration: 0.3)) { step = .failed }
            }
        }
    }

    /// Add/fund the target mint over Lightning, then pay the request. Falls back
    /// to a top-up QR (`NeedsExternalTopUp`) when no held mint can bankroll it.
    private func runCreqAcquireAndPay(targetMintURL: String, amount: UInt64) {
        guard let creq = currentCreq else { return }
        activeRouteExplanation = creqRouteExplanation
        HapticFeedback.impact(.medium)
        errorMessage = nil
        withAnimation(.smooth(duration: 0.3)) { step = .sending }
        Task { @MainActor in
            do {
                try await walletManager.addMintAndPayCashuRequest(
                    creq,
                    amount: amount,
                    targetMintURL: targetMintURL,
                    onStage: { _ in }
                )
                withAnimation(.smooth(duration: 0.3)) { step = .sent }
            } catch let topUp as NeedsExternalTopUp {
                // No held mint can fund it — return to confirm, then show the top-up QR.
                withAnimation(.smooth(duration: 0.3)) { step = .confirm }
                try? await Task.sleep(nanoseconds: 300_000_000)
                topUpContext = TopUpContext(
                    summary: creq,
                    amount: amount,
                    targetMintURL: topUp.targetMintURL,
                    quote: topUp.targetQuote
                )
            } catch is MintSettling {
                presentError(
                    "Still settling — your balance will update shortly. Try again in a moment.",
                    severity: .caution
                )
                withAnimation(.smooth(duration: 0.3)) { step = .failed }
            } catch {
                presentError(from: error)
                withAnimation(.smooth(duration: 0.3)) { step = .failed }
            }
        }
    }

    private var paymentAmountForCreq: UInt64? {
        guard let creq = currentCreq else { return nil }
        return creq.amount ?? (amountSats > 0 ? amountSats : nil)
    }

    private var creqCanPay: Bool {
        guard let creq = currentCreq, creq.isSatUnit, !isWorking else { return false }
        guard let amount = paymentAmountForCreq, amount > 0 else { return false }
        if needsAcquire { return true }
        guard let mint = selectedPaymentMint else { return false }
        return mint.balance >= amount
    }

    private var candidateMints: [MintInfo] {
        guard let creq = currentCreq else { return [] }
        guard !creq.mints.isEmpty else { return walletManager.mints }
        let requested = Set(creq.mints.map(normalizedMintURL))
        return walletManager.mints.filter { requested.contains(normalizedMintURL($0.url)) }
    }

    private var selectedPaymentMint: MintInfo? {
        if let selectedMint, let match = candidateMints.first(where: { $0.id == selectedMint.id }) {
            return match
        }
        return recommendedPaymentMint()
    }

    private func recommendedPaymentMint() -> MintInfo? {
        guard !candidateMints.isEmpty else { return nil }
        let candidates: [MintInfo]
        if let amount = paymentAmountForCreq, amount > 0 {
            let affordable = candidateMints.filter { $0.balance >= amount }
            candidates = affordable.isEmpty ? candidateMints : affordable
        } else {
            candidates = candidateMints
        }
        if let active = walletManager.activeMint, let match = candidates.first(where: { $0.id == active.id }) {
            return match
        }
        return candidates.sorted { lhs, rhs in
            lhs.balance == rhs.balance
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : lhs.balance > rhs.balance
        }.first
    }

    private func normalizedMintURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        var normalized = host
        if let port = url.port { normalized += ":\(port)" }
        normalized += url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized
    }

    private func extractMintHost(_ url: String) -> String { URL(string: url)?.host ?? url }

    // creq "add mint & pay" recovery

    /// The mint URL to acquire ecash at when the request can't be paid from current
    /// ecash: a held-but-underfunded required mint → that mint; nothing held → a
    /// requested mint to add. Nil when already payable or when there's nothing to
    /// target (any-mint request with nothing held).
    private var acquireTargetURL: String? {
        guard let creq = currentCreq, creq.isSatUnit,
              let amount = paymentAmountForCreq, amount > 0 else { return nil }
        if let mint = selectedPaymentMint {
            return mint.balance >= amount ? nil : mint.url
        }
        guard !creq.mints.isEmpty else { return nil }
        if creq.mints.count == 1 { return creq.mints.first }
        return selectedAddMintURL ?? creq.mints.first
    }

    private var acquireTargetHost: String? { acquireTargetURL.map(extractMintHost) }
    private var needsAcquire: Bool { acquireTargetURL != nil }
    private var acquireAddsNewMint: Bool { selectedPaymentMint == nil }

    private var creqRouteExplanation: CashuRequestRouteExplanation? {
        guard let creq = currentCreq, creq.isSatUnit, paymentAmountForCreq != nil else {
            return CashuRequestRouteExplanation(state: .unavailable)
        }
        guard needsAcquire else {
            return CashuRequestRouteExplanation(state: .compatibleMint)
        }
        let state: CashuRequestRouteExplanation.State = acquireAddsNewMint
            ? .addRequestedMint(targetMintURL: acquireTargetURL)
            : .topUpTargetMint(targetMintURL: acquireTargetURL)
        return CashuRequestRouteExplanation(state: state)
    }

    private var creqPayButtonTitle: String {
        guard needsAcquire else { return "Pay" }
        if acquireAddsNewMint {
            if let creq = currentCreq, creq.mints.count > 1, selectedAddMintURL == nil {
                return "Add a mint & pay"
            }
            return acquireTargetHost.map { "Add \($0) & pay" } ?? "Add mint & pay"
        }
        return acquireTargetHost.map { "Fund \($0) & pay" } ?? "Fund mint & pay"
    }

    // creq fee

    private func recomputeFee() {
        feeTask?.cancel()
        guard let creq = currentCreq, creq.isSatUnit,
              let mint = selectedPaymentMint,
              let amount = paymentAmountForCreq, amount > 0 else {
            feeState = .idle
            return
        }
        if let ppk = feePpkByMint[mint.url], ppk == 0 {
            feeState = .free
            return
        }
        feeState = .loading
        let mintURL = mint.url
        feeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let ppk: UInt64?
            if let cached = feePpkByMint[mintURL] {
                ppk = cached
            } else {
                ppk = await walletManager.mintInputFeePpk(mintURL: mintURL)
                if let ppk { feePpkByMint[mintURL] = ppk }
            }
            if Task.isCancelled { return }
            guard let ppk else { feeState = .unavailable; return }
            if ppk == 0 { feeState = .free; return }
            let fee = await walletManager.estimateCashuPaymentFee(amountSats: amount, mintURL: mintURL)
            if Task.isCancelled { return }
            feeState = fee.map { $0 == 0 ? .free : .amount($0) } ?? .unavailable
        }
    }

    /// The paying mint as a status detail row, always present so its slot is reserved:
    /// the held mint's name; in the acquire path the target host; a spinner only if
    /// neither is known yet.
    private var creqStatusMintRow: PaymentStatusView.DetailRow {
        let icon = "bitcoinsign.bank.building"
        if let mint = selectedPaymentMint {
            return .init(icon: icon, label: "Mint", value: mint.name)
        }
        if let host = acquireTargetHost {
            return .init(icon: icon, label: "Mint", value: host)
        }
        return .init(icon: icon, label: "Mint", value: "", isPending: true)
    }

    /// The swap fee as a status detail row, always present so its slot is reserved.
    /// Mirrors `creqFeeValueText`: a spinner while the fee computes, then the value;
    /// acquiring a mint routes over Lightning, whose reserve is confirmed later.
    private var creqStatusFeeRow: PaymentStatusView.DetailRow {
        let icon = "arrow.up.arrow.down"
        if needsAcquire {
            return .init(icon: icon, label: "Fees", value: "Network fee")
        }
        switch feeState {
        case .loading:
            return .init(icon: icon, label: "Fees", value: "", isPending: true)
        case .free:
            return .init(icon: icon, label: "Fees", value: "No fee")
        case .amount(let fee):
            return .init(
                icon: icon,
                label: "Fees",
                value: AmountFormatter.sats(fee, useBitcoinSymbol: settings.useBitcoinSymbol)
            )
        case .idle, .unavailable:
            return .init(icon: icon, label: "Fees", value: "—")
        }
    }

    // creq mint-identity header + detail rows

    private enum CreqMintPresentation {
        case picker(selected: MintInfo)
        case fixed(MintInfo)
        case unavailable(requiredHosts: [String])
    }

    private func creqMintPresentation(_ creq: CashuPaymentRequestSummary) -> CreqMintPresentation {
        guard let selected = selectedPaymentMint else {
            return .unavailable(requiredHosts: creq.mints.map(extractMintHost))
        }
        if creq.mints.count == 1 { return .fixed(selected) }
        return .picker(selected: selected)
    }

    /// The mint shown in the top header pill — only the switchable `.picker` state, since
    /// that pill is tappable-to-change. A `.fixed` required mint (can't switch) stays a
    /// read-only "Mint" detail row, and the acquire/unavailable states keep their
    /// actionable rows; a plain mint pill can't honestly represent any of those.
    private func creqTopMint(_ creq: CashuPaymentRequestSummary) -> MintInfo? {
        if case .picker(let selected) = creqMintPresentation(creq) { return selected }
        return nil
    }

    private func creqMemo(_ creq: CashuPaymentRequestSummary) -> String? {
        guard let description = creq.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return description
    }

    /// Detail rows beneath the amount: the memo and the live fee. The source mint now
    /// lives in the top header pill for the payable states; only the acquire/unavailable
    /// states (no held mint) keep their actionable mint row here.
    @ViewBuilder
    private func creqRequestDetails(_ creq: CashuPaymentRequestSummary) -> some View {
        if creq.isSatUnit {
            VStack(spacing: 0) {
                if creqTopMint(creq) == nil {
                    creqMintRow(creq)
                    creqDivider
                }
                if let explanation = creqRouteExplanation {
                    CashuRequestRouteExplanationRow(explanation: explanation)
                    creqDivider
                }
                if let memo = creqMemo(creq) {
                    creqDetailRow(icon: "quote.bubble", label: "Memo", value: memo)
                    creqDivider
                }
                creqFeesRow
            }
            .padding(.top, 16)
            .padding(.horizontal)
        }
    }

    /// The mint as a detail row: switchable for an any-/multi-mint request, read-only
    /// for a required mint, or a warning when the user holds none of the requested mints.
    @ViewBuilder
    private func creqMintRow(_ creq: CashuPaymentRequestSummary) -> some View {
        switch creqMintPresentation(creq) {
        case .picker(let selected):
            mintDetailRow(label: "From", mint: selected, switchable: true)
        case .fixed(let mint):
            if needsAcquire {
                creqActionableMintRow(host: mint.name, subtitle: "Balance too low — fund to pay")
            } else {
                mintDetailRow(label: "Mint", mint: mint, switchable: false)
            }
        case .unavailable(let hosts):
            // Recoverable: add the required mint and fund it — a neutral action, not a warning.
            if needsAcquire {
                let host = hosts.count == 1 ? (hosts.first ?? "a mint") : "Add a mint"
                let subtitle = hosts.count == 1 ? "Tap Add & pay to fund it" : "This request accepts \(hosts.count) mints"
                creqActionableMintRow(host: host, subtitle: subtitle)
            } else {
                HStack(spacing: 8) {
                    Label("Mint", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Text(hosts.isEmpty ? "Add a mint to pay"
                            : (hosts.count == 1 ? hosts[0] : "You hold none of these"))
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.subheadline)
                .padding(.horizontal, 4)
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The mint row when the request isn't payable from ecash yet but is
    /// recoverable — names the target mint with a quiet "what to do" subtitle,
    /// no alarming color (the CTA does the work).
    private func creqActionableMintRow(host: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Label("Mint", systemImage: "bitcoinsign.bank.building")
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(host)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var creqFeesRow: some View {
        HStack {
            Label("Fees", systemImage: "arrow.up.arrow.down")
                .foregroundStyle(.secondary)
            Spacer()
            creqFeeValueText
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var creqFeeValueText: some View {
        if needsAcquire {
            // Funding the mint routes over Lightning, which always carries a fee;
            // the exact reserve is confirmed during the transfer and in History.
            Text("Network fee").fontWeight(.medium).foregroundStyle(.secondary)
        } else {
            switch feeState {
            case .loading:
                ProgressView().controlSize(.mini)
            case .free:
                Text("No fee").fontWeight(.medium)
            case .amount(let fee):
                Text(AmountFormatter.sats(fee, useBitcoinSymbol: settings.useBitcoinSymbol))
                    .fontWeight(.medium)
            case .idle, .unavailable:
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private func creqDetailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var creqDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.horizontal, 4)
    }

    // MARK: Input actions

    private func openScanner() {
        HapticFeedback.selection()
        showingScanner = true
    }

    private func handleScannedDestination(_ scanned: String) {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        destination = trimmed
        advanceNow(raw: trimmed)
    }

    private func pasteFromClipboard() {
        guard let content = UIPasteboard.general.string else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HapticFeedback.selection()
        destination = trimmed
        advanceNow(raw: trimmed)
    }

    @ViewBuilder
    private func routeView(_ route: SendRoute) -> some View {
        switch route {
        case .receiveToken(let token):
            ReceiveTokenDetailView(
                tokenString: token,
                onComplete: { self.route = nil; onClose() }
            )
            .environmentObject(walletManager)
        case .ecash:
            SendView()
                .environmentObject(walletManager)
        }
    }

    // MARK: Empty states (reproduced from the old send chooser)

    private var noMintsState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect a mint first")
                        .font(.title3.weight(.medium))
                    Text("Mints issue the ecash you send and receive. Add one to get started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                SuggestedMintsSection(
                    existingURLs: Set(walletManager.mints.map(\.url)),
                    onAdd: addMint
                )

                if let addMintError {
                    InlineNotice(message: addMintError, severity: .error)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                Button(action: onAddCustomMint) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add custom mint URL")
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .textLinkButton()
                .padding(.top, 4)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                compactContentHeight = newHeight
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var noBalanceState: some View {
        // `.section` keeps intrinsic height so the sheet can hug this empty state;
        // fullScreen would expand to infinity and defeat the content-fit detent.
        NativeEmptyState(
            title: "Nothing to send yet",
            systemImage: "arrow.down.circle",
            description: "Receive some ecash before you can send.",
            style: .section,
            actionTitle: "Receive",
            action: onReceive
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            compactContentHeight = newHeight
        }
    }

    private func addMint(_ url: String) {
        addMintError = nil
        Task {
            do {
                try await walletManager.addMint(url: url)
            } catch {
                addMintError = "Couldn't connect to that mint. Try another."
            }
        }
    }
}

/// Compact input keeps the system translucent sheet; amount/confirm/status pin
/// the flat canvas so they read seamless once the detent expands to `.large`.
private struct UnifiedSendSheetBackground: ViewModifier {
    let compact: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if compact {
            content
        } else {
            content.canvasSheetBackground()
        }
    }
}

struct MeltView: View {
    enum MeltMode: String, CaseIterable {
        case lightning
        case onchain

        var displayName: String {
            switch self {
            case .lightning:
                return "Lightning"
            case .onchain:
                return "On-chain"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    private let autoQuoteOnAppear: Bool
    private let routeExplanation: CashuRequestRouteExplanation?
    private let onComplete: (() -> Void)?

    @State private var requestInput: String
    @State private var amountString: String
    @State private var meltMode: MeltMode
    @State private var meltQuote: MeltQuoteInfo?
    /// True while an auto-quote for an amount-carrying invoice is in flight (from mount, or
    /// from a paste/scan into this field) until it resolves (success, failure, or a guard
    /// that prevents fetching). Keeps the screen on the confirm layout (in a loading state)
    /// instead of flashing / lingering on the input screen. Seeded in `init` for the
    /// scanned/deep-link mount case and set in `applyDecodedSuggestion` for paste/scan; see
    /// `meltViewStateKey`.
    @State private var isPreparingInitialQuote: Bool
    @State private var isGettingQuote = false
    @State private var isPaying = false
    /// True when the mint accepted the melt for asynchronous (NUT-05) settlement —
    /// typical for on-chain — so the success screen says "processing", not "sent".
    @State private var meltSettlementPending = false
    @State private var errorMessage: String?
    @State private var errorSeverity: ErrorSeverity = .error
    @State private var errorShowsMintAction = false

    /// Drives the full-screen processing → success → failure status screen.
    /// nil while the user is still on input/confirm.
    @State private var paymentPhase: PaymentStatusView.Phase?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func presentError(_ message: String, severity: ErrorSeverity = .error) {
        errorMessage = message
        errorSeverity = severity
        errorShowsMintAction = false
    }

    private func presentError(from error: Error) {
        let walletMessage = error.walletMessage
        errorMessage = walletMessage.text
        errorSeverity = walletMessage.severity
        errorShowsMintAction = error.isInsufficientBalanceError
    }

    private var meltInsufficientDetail: String? {
        guard let mint = displayMeltMint else { return nil }
        return "You have \(AmountFormatter.sats(mint.balance, useBitcoinSymbol: settings.useBitcoinSymbol)) in \(mint.name)."
    }

    @ViewBuilder
    private func errorNotice(_ message: String) -> some View {
        InlineNotice(
            message: message,
            severity: errorSeverity,
            detail: errorShowsMintAction ? meltInsufficientDetail : nil,
            tinted: true
        )
    }

    // Inline scan + clipboard suggestion
    @State private var showingScanner = false
    @State private var showingMintPicker = false
    @State private var selectedMeltMint: MintInfo?
    @State private var clipboardSuggestion: PaymentRequestDecodeResult?
    @State private var clipboardSuggestionRaw: String?
    @State private var dismissedClipboardSuggestion = false

    private var meltViewStateKey: String {
        // All three payment phases share one key so switching between them doesn't
        // re-insert the status screen — the icon morph is owned by PaymentStatusView.
        if paymentPhase != nil { return "status" }
        // Loading and confirmed share one key so they render as the SAME view identity —
        // the quote fills in place, no screen swap. (See `quoteConfirmView`.)
        if meltQuote != nil || isPreparingInitialQuote { return "quote" }
        return "input"
    }

    init(
        initialRequest: String = "",
        initialAmount: String = "",
        initialMode: MeltMode = .lightning,
        autoQuoteOnAppear: Bool = false,
        routeExplanation: CashuRequestRouteExplanation? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.autoQuoteOnAppear = autoQuoteOnAppear
        self.routeExplanation = routeExplanation
        self.onComplete = onComplete
        _requestInput = State(initialValue: initialRequest)
        _amountString = State(initialValue: initialAmount)
        _meltMode = State(initialValue: initialMode)

        // Seed the loading-confirm state for the very first frame so a scanned / auto-quoted
        // invoice slides up into the confirm layout, never the input screen. Only qualifies
        // amount-carrying BOLT11/BOLT12 — the cases where the `.onAppear` auto-quote is
        // guaranteed to fire and land on the confirm screen. Decode is synchronous.
        let hasKnownAmount: Bool
        switch PaymentRequestDecoder.decode(initialRequest) {
        case .bolt11(let amount, _), .bolt12(let amount, _):
            hasKnownAmount = amount != nil
        default:
            hasKnownAmount = false
        }
        _isPreparingInitialQuote = State(initialValue: autoQuoteOnAppear && hasKnownAmount)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let paymentPhase {
                    statusView(paymentPhase)
                        .transition(.opacity)
                } else if meltQuote != nil || isPreparingInitialQuote {
                    // One branch for both loading (quote == nil) and confirmed — the fee
                    // rows fill in place when the mint quote lands, no view swap.
                    quoteConfirmView(quote: meltQuote)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    requestInputView
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.smooth(duration: 0.3), value: meltViewStateKey)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(screenTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }
            }
            .sheet(isPresented: $showingScanner) {
                ScannerWrapperView(onScanned: handleScannedRequest)
                    .environmentObject(walletManager)
                    .canvasSheetBackground()
            }
            .sheet(isPresented: $showingMintPicker) {
                MintSelectorSheet(
                    selectedMint: meltMintSelection,
                    paymentMethod: selectedMeltPaymentMethod,
                    minimumAmount: knownPaymentAmount,
                    onSelect: selectMeltMint
                )
                    .environmentObject(walletManager)
            }
            .onAppear {
                syncMeltModeWithAvailableMints()
                syncSelectedMeltMint()
                detectClipboardSuggestion()
                if autoQuoteOnAppear,
                   !requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !amountRequired {
                    getQuote()
                } else {
                    // Auto-quote won't fire (amountless / on-chain / manual) — drop the
                    // loading seed so the input screen shows instead of a stuck spinner.
                    isPreparingInitialQuote = false
                }
            }
            .onChange(of: walletManager.activeMint?.id) {
                syncMeltModeWithAvailableMints()
                if meltQuote == nil {
                    syncSelectedMeltMint()
                    errorMessage = nil
                }
            }
            .onChange(of: meltMode) {
                errorMessage = nil
                if meltMode == .onchain {
                    requestInput = PaymentRequestParser.normalizeBitcoinRequest(requestInput)
                }
                syncSelectedMeltMint()
            }
            .onChange(of: requestInput) {
                syncSelectedMeltMint()
                // Surface the amountless caution the moment a request is pasted/typed —
                // no Get Quote tap needed to discover it carries no amount. Any other
                // stale notice clears when the destination changes.
                if let notice = PaymentRequestDecoder.decode(requestInput).amountlessMeltCaution {
                    presentError(notice, severity: .caution)
                } else {
                    errorMessage = nil
                }
            }
            .onChange(of: entryUnit) { oldUnit, newUnit in
                amountString = AmountFormatter.entryConverted(raw: amountString, from: oldUnit, to: newUnit)
            }
        }
    }

    private var supportsOnchainMelt: Bool {
        availableMeltMints.contains { $0.supportedMeltMethods.contains(.onchain) }
    }

    private var availableMeltMints: [MintInfo] {
        if walletManager.mints.isEmpty {
            return walletManager.activeMint.map { [$0] } ?? []
        }
        return walletManager.mints
    }

    private var selectedMeltPaymentMethod: PaymentMethodKind {
        if meltMode == .onchain {
            return .onchain
        }

        if isHumanReadableAddress {
            return .bolt11
        }

        return PaymentRequestParser.paymentMethod(for: requestInput) ?? .bolt11
    }

    /// The unit the keypad is entering in: fiat only when fiat is primary AND a
    /// price is loaded, else sats (mirrors `CurrencyAmountDisplay.effectivePrimary`).
    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    /// Satoshis represented by the typed amount, interpreted per `entryUnit`.
    private var amountSats: UInt64 { AmountFormatter.entrySats(raw: amountString, unit: entryUnit) }

    private var knownPaymentAmount: UInt64? {
        let entered = amountSats
        if entered > 0 {
            return entered
        }

        switch PaymentRequestDecoder.decode(requestInput) {
        case .bolt11(let amount, _), .bolt12(let amount, _):
            return amount
        case .lightningAddress, .onchain, .cashuPaymentRequest, .unrecognized:
            return nil
        }
    }

    private var resolvedSelectedMeltMint: MintInfo? {
        guard let selectedMeltMint else { return nil }
        return availableMeltMints.first { $0.id == selectedMeltMint.id } ?? selectedMeltMint
    }

    private var displayMeltMint: MintInfo? {
        if let mint = resolvedSelectedMeltMint,
           mint.supportedMeltMethods.contains(selectedMeltPaymentMethod) {
            return mint
        }

        return recommendedMeltMint(
            for: selectedMeltPaymentMethod,
            minimumAmount: knownPaymentAmount
        )
    }

    private var meltMintSelection: Binding<MintInfo?> {
        Binding(
            get: { displayMeltMint },
            set: { newMint in
                if let newMint {
                    selectMeltMint(newMint)
                } else {
                    selectedMeltMint = nil
                }
            }
        )
    }

    private var screenTitle: String {
        meltMode == .onchain ? "Pay On-chain" : "Pay Lightning"
    }

    private var isHumanReadableAddress: Bool {
        meltMode == .lightning && PaymentRequestParser.isHumanReadableLightningAddress(requestInput)
    }

    private var isBitcoinAddress: Bool {
        PaymentRequestParser.isBitcoinAddress(requestInput)
    }

    private var amountRequired: Bool {
        meltMode == .onchain || isHumanReadableAddress
    }

    private var canGetQuote: Bool {
        guard !requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if amountRequired {
            guard amountSats > 0 else { return false }
        }

        if meltMode == .onchain {
            return isBitcoinAddress
        }

        return true
    }

    private func mintInfo(for quote: MeltQuoteInfo) -> MintInfo? {
        walletManager.mints.first { $0.url == quote.mintUrl }
            ?? (walletManager.activeMint?.url == quote.mintUrl ? walletManager.activeMint : nil)
    }

    private func hasSufficientBalance(for quote: MeltQuoteInfo) -> Bool {
        guard let balance = mintInfo(for: quote)?.balance else { return true }
        return balance >= quote.totalAmount
    }

    private var requestPlaceholder: String {
        switch meltMode {
        case .lightning:
            return "Lightning address, invoice, or BOLT12 offer"
        case .onchain:
            return "Bitcoin address"
        }
    }

    private var requestInputView: some View {
        VStack(spacing: 0) {
            if let mint = displayMeltMint {
                MintConfirmSelectorRow(mint: mint, onTap: { showingMintPicker = true })
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            HStack(alignment: .top, spacing: 12) {
                TextField(requestPlaceholder, text: $requestInput, axis: .vertical)
                    .font(.body)
                    .lineLimit(3...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack(spacing: 6) {
                    Button(action: openScanner) {
                        Image(systemName: "viewfinder")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scan QR Code")

                    Button(action: pasteFromClipboard) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Paste from clipboard")
                }
            }
            .padding()
            .liquidGlass(in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 16)

            // The decode hint ("BOLT11 invoice — set amount") is redundant once a notice
            // is showing — the notice carries the same information, in a clearer voice.
            if errorMessage == nil {
                liveDecodeFeedback
                    .padding(.top, 6)
                    .padding(.horizontal)
            }

            if amountRequired {
                amountEntrySection
                    .padding(.top, 16)
            }

            if displayMeltMint == nil, !availableMeltMints.isEmpty {
                InlineNotice(
                    message: "No mint supports \(selectedMeltPaymentMethod.displayName) payments.",
                    severity: .caution,
                    tinted: true
                )
                .padding(.top, 12)
                .padding(.horizontal)
            }

            if let error = errorMessage {
                errorNotice(error)
                    .padding(.top, 12)
                    .padding(.horizontal)
            }

            if amountRequired {
                NumberPadAmountInput(amountString: $amountString, unit: entryUnit)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            } else {
                launchpadSection
                    .padding(.top, 16)
                    .padding(.horizontal)
                Spacer(minLength: 0)
            }

            Button(action: getQuote) {
                if isGettingQuote {
                    ProgressView()
                } else {
                    Text("Get Quote")
                }
            }
            .glassButton()
            .disabled(!canGetQuote || isGettingQuote)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Launchpad (clipboard chip)

    @ViewBuilder
    private var launchpadSection: some View {
        VStack(spacing: 12) {
            if let suggestion = clipboardSuggestion,
               let raw = clipboardSuggestionRaw,
               !dismissedClipboardSuggestion,
               requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ClipboardPaymentChip(
                    raw: raw,
                    result: suggestion,
                    onTap: { applyDecodedSuggestion(suggestion, raw: raw) },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dismissedClipboardSuggestion = true
                        }
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: requestInput.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: dismissedClipboardSuggestion)
    }

    @ViewBuilder
    private var liveDecodeFeedback: some View {
        let trimmed = requestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let result = PaymentRequestDecoder.decode(trimmed)
            HStack(spacing: 6) {
                Image(systemName: result == .unrecognized ? "exclamationmark.circle" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                Text(liveDecodeText(for: result))
                    .font(.caption)
            }
            .foregroundStyle(result == .unrecognized ? Color.red : Color.secondary)
            .transition(.opacity)
            .accessibilityLabel(liveDecodeText(for: result))
        }
    }

    private func liveDecodeText(for result: PaymentRequestDecodeResult) -> String {
        switch result {
        case .lightningAddress:
            return "Lightning address"
        case .bolt11(let amount, _):
            return amount.map { "BOLT11 invoice — \($0) sat" } ?? "BOLT11 invoice — set amount"
        case .bolt12(let amount, _):
            return amount.map { "BOLT12 offer — \($0) sat" } ?? "BOLT12 offer — set amount"
        case .onchain:
            return "Bitcoin address"
        case .cashuPaymentRequest:
            return "Cashu payment request"
        case .unrecognized:
            return "Unrecognized — try a Lightning address, invoice, or Bitcoin address"
        }
    }

    private var amountEntrySection: some View {
        CurrencyAmountDisplay(
            sats: amountSats,
            primary: $settings.amountDisplayPrimary,
            primarySize: 48,
            entryRaw: amountString
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Payment amount")
        .accessibilityValue("\(amountString.isEmpty ? "0" : amountString) sats")
    }


    /// Renders the confirm layout for both the loading state (`quote == nil`, before the mint
    /// melt-quote lands) and the resolved state. The `quote != nil` render path is unchanged;
    /// while loading the amount hero shows the synchronously-decoded invoice amount and the
    /// fee / required-balance rows are skeleton placeholders that fill in place when the quote
    /// arrives — no view swap, so the sheet never flashes the input screen on present.
    private func quoteConfirmView(quote: MeltQuoteInfo?) -> some View {
        let isLoading = quote == nil
        let displayAmount = quote?.amount ?? knownPaymentAmount ?? 0
        let methodName = quote?.paymentMethod.displayName ?? meltMode.displayName
        let selectorMint = quote.flatMap(mintInfo(for:)) ?? displayMeltMint
        let canPay = quote.map { hasSufficientBalance(for: $0) } ?? false

        // Shared Pay-flow scaffold (see `PayFlowScaffold`) so the details block sits
        // at the same Y here as on the processing / success screens.
        return PayFlowScaffold {
            CurrencyAmountDisplay(
                sats: displayAmount,
                primary: $settings.amountDisplayPrimary
            )
        } details: {
            VStack(spacing: 0) {
                meltDetailRow(icon: "bolt", label: "Method", value: methodName)
                if let routeExplanation {
                    meltDivider
                    CashuRequestRouteExplanationRow(explanation: routeExplanation)
                }
                meltDivider
                if quote?.paymentMethod == .onchain {
                    meltDetailRow(
                        icon: "arrow.up.right",
                        label: "To",
                        value: PaymentRequestParser.normalizeBitcoinRequest(requestInput)
                    )
                    meltDivider
                }
                meltDetailRow(icon: "bitcoinsign", label: "Amount", value: "\(displayAmount) sat")
                meltDivider
                meltDetailRow(icon: "arrow.up.arrow.down", label: "Max fee", value: "\(quote?.feeReserve ?? 0) sat")
                    .redacted(reason: isLoading ? .placeholder : [])
                // Reserve the Required-balance row while loading (we don't yet know the fee)
                // so the common fee-bearing case doesn't shift when the quote lands.
                if isLoading || (quote?.feeReserve ?? 0) > 0 {
                    meltDivider
                    meltDetailRow(icon: "creditcard", label: "Required balance", value: "\(quote?.totalAmount ?? 0) sat")
                        .redacted(reason: isLoading ? .placeholder : [])
                }
                // The paying mint is already shown in the selector chip above (with
                // balance + switch), so no redundant "Mint" row.
            }
            .padding(.horizontal)
            .animation(.smooth(duration: 0.3), value: isLoading)

            // Transient notices sit below the details block (the flexible zone) so
            // they never push the details anchor.
            if let quote,
               !hasSufficientBalance(for: quote),
               let balance = mintInfo(for: quote)?.balance {
                InlineNotice(
                    message: "Selected mint has \(balance) sat; this quote can reserve up to \(quote.totalAmount) sat.",
                    severity: .caution
                )
                .padding(.horizontal)
                .padding(.top, 12)
            }

            if let error = errorMessage {
                errorNotice(error)
                    .padding(.top, 12)
                    .padding(.horizontal)
            }
        } footer: {
            Button(action: payRequest) {
                if isPaying || isLoading {
                    ProgressView()
                } else {
                    Text("Pay \(displayAmount) sat")
                }
            }
            .glassButton()
            .disabled(isLoading || isPaying || !canPay)
            .padding(.horizontal)
            .padding(.bottom, 16)
        } topAccessory: {
            if let mint = selectorMint {
                MintConfirmSelectorRow(mint: mint, onTap: { showingMintPicker = true })
                    .padding(.horizontal)
                    .padding(.top, 12)
            }
        }
    }

    private func meltDetailRow(icon: String, label: String, value: String) -> some View {
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
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    /// Hairline row separator matching CashuPaymentRequestPayView's `canvasDivider`
    /// so the two pay screens read as one system (no boxed background).
    private var meltDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.horizontal, 4)
    }

    /// Full-screen processing → success → failure status, preserving the payment
    /// facts (amount / method / on-chain destination / max fee / mint) as rows.
    private func statusView(_ phase: PaymentStatusView.Phase) -> some View {
        var rows: [PaymentStatusView.DetailRow] = []
        if let quote = meltQuote {
            // Same row order as `quoteConfirmView` so the rows hold their positions on
            // the confirm → processing transition (only the amount hero morphs into the
            // spinner). The mint — a top chip on confirm, which the status scaffold has
            // no room for — becomes the trailing row here.
            rows.append(.init(icon: "bolt", label: "Method", value: quote.paymentMethod.displayName))
            if let routeExplanation {
                rows.append(.init(
                    icon: "arrow.triangle.branch",
                    label: "Route",
                    value: routeExplanation.localizedValue
                ))
            }
            if quote.paymentMethod == .onchain {
                rows.append(.init(
                    icon: "arrow.up.right",
                    label: "To",
                    value: PaymentRequestParser.normalizeBitcoinRequest(requestInput)
                ))
            }
            rows.append(.init(icon: "bitcoinsign", label: "Amount", value: "\(quote.amount) sat"))
            rows.append(.init(icon: "arrow.up.arrow.down", label: "Max fee", value: "\(quote.feeReserve) sat"))
            if let mint = mintInfo(for: quote) {
                rows.append(.init(icon: "bitcoinsign.bank.building", label: "Mint", value: mint.name))
            }
        }
        return PaymentStatusView(
            details: rows,
            phase: phase,
            // An async-accepted (NUT-05) melt — typical for on-chain — isn't settled
            // yet: the mint took the payment and pays out in the background.
            successTitle: meltSettlementPending ? "Payment Processing" : "Payment Sent!",
            onDone: close,
            onRetry: { withAnimation(.smooth(duration: 0.3)) { paymentPhase = nil } }
        )
    }

    private func syncMeltModeWithAvailableMints() {
        guard supportsOnchainMelt || meltMode != .onchain else {
            meltMode = .lightning
            presentError("No mint supports On-chain payments.")
            return
        }
    }

    private func syncSelectedMeltMint() {
        if let mint = resolvedSelectedMeltMint,
           mint.supportedMeltMethods.contains(selectedMeltPaymentMethod) {
            return
        }

        selectedMeltMint = recommendedMeltMint(
            for: selectedMeltPaymentMethod,
            minimumAmount: knownPaymentAmount
        )
    }

    private func recommendedMeltMint(
        for paymentMethod: PaymentMethodKind,
        minimumAmount: UInt64?
    ) -> MintInfo? {
        let compatible = availableMeltMints.filter {
            $0.supportedMeltMethods.contains(paymentMethod)
        }

        guard !compatible.isEmpty else {
            return nil
        }

        let affordable = compatible.filter { mint in
            guard let minimumAmount else { return true }
            return mint.balance >= minimumAmount
        }
        let candidates = affordable.isEmpty ? compatible : affordable

        if let activeMint = walletManager.activeMint,
           candidates.contains(where: { $0.id == activeMint.id }) {
            return activeMint
        }

        return candidates.sorted { lhs, rhs in
            if lhs.balance == rhs.balance {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.balance > rhs.balance
        }.first
    }

    private func selectMeltMint(_ mint: MintInfo) {
        selectedMeltMint = mint
        if meltQuote != nil {
            meltQuote = nil
        }
        errorMessage = nil
        HapticFeedback.selection()
    }

    private func pasteFromClipboard() {
        guard let content = UIPasteboard.general.string else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HapticFeedback.selection()
        let result = PaymentRequestDecoder.decode(trimmed)
        applyDecodedSuggestion(result, raw: trimmed)
    }

    private func openScanner() {
        HapticFeedback.selection()
        showingScanner = true
    }

    private func handleScannedRequest(_ scanned: String) {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = PaymentRequestDecoder.decode(trimmed)
        applyDecodedSuggestion(result, raw: trimmed)
    }

    private func detectClipboardSuggestion() {
        guard !dismissedClipboardSuggestion,
              clipboardSuggestion == nil,
              requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let content = UIPasteboard.general.string else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = PaymentRequestDecoder.decode(trimmed)
        guard result != .unrecognized else { return }
        clipboardSuggestion = result
        clipboardSuggestionRaw = trimmed
    }

    private func applyDecodedSuggestion(_ result: PaymentRequestDecodeResult, raw: String) {
        // Choose mode based on suggestion (if we can switch).
        if let suggested = PaymentRequestDecoder.suggestedMode(result),
           suggested != meltMode,
           suggested != .onchain || supportsOnchainMelt {
            withAnimation(.snappy) { meltMode = suggested }
        }

        // Fill input with normalized request.
        switch result {
        case .onchain:
            requestInput = PaymentRequestParser.normalizeBitcoinRequest(raw)
        case .bolt11, .bolt12:
            requestInput = PaymentRequestDecoder.encodedLightningRequest(from: raw)
                ?? PaymentRequestParser.normalizeLightningRequest(raw)
        case .lightningAddress, .cashuPaymentRequest, .unrecognized:
            requestInput = raw
        }

        // Hide the chip after a tap.
        dismissedClipboardSuggestion = true
        errorMessage = nil

        // Auto-quote when amount is locked. Flip to the loading-confirm layout first so the
        // paste/scan slides into the confirm (amount hero + skeleton fees) instead of
        // lingering on the input screen with a spinner in the Get Quote button — matches the
        // scanned-invoice mount path. `requestInput` is already set above, so the confirm's
        // amount hero reads the invoice amount immediately.
        if PaymentRequestDecoder.amountLocked(result) {
            isPreparingInitialQuote = true
            getQuote()
        }
    }

    private func getQuote() {
        let trimmedInput = requestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        if meltMode == .lightning,
           PaymentRequestParser.paymentMethod(for: trimmedInput) == .onchain {
            // Switching to on-chain (or bailing) needs an amount the user must enter — fall
            // back to the input screen rather than staying on the loading-confirm state.
            isPreparingInitialQuote = false
            guard supportsOnchainMelt else {
                presentError("No mint supports On-chain payments.")
                return
            }

            meltMode = .onchain
            syncSelectedMeltMint()
            presentError("Switched to On-chain. Enter an amount to continue.", severity: .info)
            requestInput = PaymentRequestParser.normalizeBitcoinRequest(trimmedInput)
            return
        }

        if let notice = PaymentRequestDecoder.decode(trimmedInput).amountlessMeltCaution {
            // Amountless invoice/offer can't be quoted without an amount we don't collect
            // here — surface the clean caution up-front instead of a raw mint error.
            isPreparingInitialQuote = false
            presentError(notice, severity: .caution)
            return
        }

        guard let quoteMint = displayMeltMint else {
            // The inline notice under the field already explains this whenever the user
            // has mints; only fall back to the error surface when they have none, so the
            // two notices never stack the same message.
            isPreparingInitialQuote = false
            if availableMeltMints.isEmpty {
                presentError("No mint supports \(selectedMeltPaymentMethod.displayName) payments.")
            }
            return
        }

        isGettingQuote = true
        errorMessage = nil

        Task { @MainActor in
            defer { isGettingQuote = false }

            do {
                switch meltMode {
                case .lightning:
                    if isHumanReadableAddress {
                        let amount = amountSats
                        guard amount > 0 else { return }
                        let quote = try await walletManager.createHumanReadableMeltQuote(
                            address: trimmedInput,
                            amount: amount,
                            preferredMintURL: quoteMint.url
                        )
                        setMeltQuote(quote)
                    } else {
                        let request = PaymentRequestDecoder.encodedLightningRequest(from: trimmedInput) ?? trimmedInput
                        let quote = try await walletManager.createMeltQuote(
                            request: request,
                            preferredMintURL: quoteMint.url
                        )
                        setMeltQuote(quote)
                    }
                case .onchain:
                    let amount = amountSats
                    guard amount > 0 else { return }
                    let quote = try await walletManager.createOnchainMeltQuote(
                        address: trimmedInput,
                        amount: amount,
                        preferredMintURL: quoteMint.url
                    )
                    setMeltQuote(quote)
                }
            } catch {
                // Fetch failed — leave the loading-confirm state so the input screen
                // reappears with the error notice.
                isPreparingInitialQuote = false
                presentError(from: error)
            }
        }
    }

    private func setMeltQuote(_ quote: MeltQuoteInfo) {
        meltQuote = quote
        isPreparingInitialQuote = false
        if let mint = mintInfo(for: quote) {
            selectedMeltMint = mint
        }
    }

    private func payRequest() {
        guard let quote = meltQuote else { return }

        isPaying = true
        errorMessage = nil
        HapticFeedback.impact(.medium)
        withAnimation(.smooth(duration: 0.3)) { paymentPhase = .processing }

        Task { @MainActor in
            do {
                let result = try await walletManager.meltTokens(quoteId: quote.id, mintUrl: quote.mintUrl)
                meltSettlementPending = result.settlement == .pending
                withAnimation(.smooth(duration: 0.3)) { paymentPhase = .success }
            } catch {
                let walletMessage = error.walletMessage
                // Keep errorMessage populated so the confirm screen's notice reappears
                // if the user taps Try Again.
                presentError(walletMessage.text, severity: walletMessage.severity)
                withAnimation(.smooth(duration: 0.3)) {
                    paymentPhase = .failure(
                        message: walletMessage.text,
                        isCaution: walletMessage.severity == .caution,
                        isTerminal: walletMessage.recoverability == .terminal
                    )
                }
            }
            isPaying = false
        }
    }

    private func close() {
        onComplete?()
        dismiss()
    }
}

// MARK: - Melt View With Pre-filled Invoice

struct MeltViewWithInvoice: View {
    let invoice: String
    var onComplete: (() -> Void)?

    var body: some View {
        MeltView(
            initialRequest: invoice,
            initialMode: .lightning,
            autoQuoteOnAppear: true,
            onComplete: onComplete
        )
    }
}

// MARK: - Melt View With Pre-filled Address

struct MeltViewWithAddress: View {
    let address: String
    var onComplete: (() -> Void)?

    var body: some View {
        MeltView(
            initialRequest: address,
            initialMode: .onchain,
            onComplete: onComplete
        )
    }
}

// MARK: - Mint Selector Sheet (for Send/Receive flows)

/// Bottom-sheet unit chooser for the Send / Create-Ecash flow. Lists the units
/// a mint advertises; the current one is checkmarked. Mirrors `MintSelectorSheet`.
struct UnitSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let units: [String]
    let selectedUnit: String
    let onSelect: (String) -> Void

    /// Measured height of the rows, driving a content-fit detent so the sheet
    /// hugs its units instead of stretching to `.medium`. Mirrors `AddMintToPaySheet`.
    @State private var rowsHeight: CGFloat = 0

    /// Fixed sheet chrome around the measured rows: drag indicator + inline nav
    /// bar + a little bottom breathing room.
    private static let navChrome: CGFloat = 96

    private var detentHeight: CGFloat {
        let rows = rowsHeight > 0 ? rowsHeight : CGFloat(units.count) * 68
        return rows + Self.navChrome
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(units, id: \.self) { unit in
                        Button(action: { select(unit) }) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(unit.uppercased())
                                        .font(.body.weight(.medium))
                                    if let subtitle = unitSubtitle(unit) {
                                        Text(subtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if unit == selectedUnit {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    rowsHeight = newHeight
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Select Unit")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
    }

    private func select(_ unit: String) {
        HapticFeedback.selection()
        onSelect(unit)
        dismiss()
    }

    /// Full currency name (e.g. "Euro"), omitted for a custom unit whose name is
    /// just its own code to avoid a redundant second line.
    private func unitSubtitle(_ unit: String) -> String? {
        let name = CurrencyRegistry.currency(forMintUnit: unit).displayName
        return name.uppercased() == unit.uppercased() ? nil : name
    }
}

struct MintSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @Binding private var selectedMint: MintInfo?
    private let mints: [MintInfo]?
    private let paymentMethod: PaymentMethodKind?
    private let minimumAmount: UInt64?
    private let onSelect: ((MintInfo) -> Void)?

    /// Measured height of the mint rows, driving a content-fit detent so the
    /// sheet hugs its mints instead of stretching to `.medium`. Mirrors
    /// `AddMintToPaySheet`. Only applies to `mintListView` — the empty states
    /// below use a fixed compact height instead, since they're static
    /// messages, not a list to measure.
    @State private var rowsHeight: CGFloat = 0

    /// Fixed sheet chrome around the measured rows: drag indicator + inline nav
    /// bar + a little bottom breathing room.
    private static let navChrome: CGFloat = 96

    /// Fixed height for the empty / no-compatible-mints messages.
    private static let compactStateHeight: CGFloat = 320

    private var detentHeight: CGFloat {
        guard sourceMints.isEmpty == false, displayMints.isEmpty == false else {
            return Self.compactStateHeight
        }
        let rows = rowsHeight > 0 ? rowsHeight : CGFloat(displayMints.count) * 68
        return rows + Self.navChrome
    }

    init(
        selectedMint: Binding<MintInfo?>,
        mints: [MintInfo]? = nil,
        paymentMethod: PaymentMethodKind? = nil,
        minimumAmount: UInt64? = nil,
        onSelect: ((MintInfo) -> Void)? = nil
    ) {
        _selectedMint = selectedMint
        self.mints = mints
        self.paymentMethod = paymentMethod
        self.minimumAmount = minimumAmount
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            if sourceMints.isEmpty {
                emptyStateView
            } else if displayMints.isEmpty {
                noCompatibleMintsView
            } else {
                mintListView
            }
        }
        .navigationTitle("Select Mint")
        .navigationBarTitleDisplayMode(.inline)
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
    }

    private var emptyStateView: some View {
        NativeEmptyState(
            title: "No Mints Available",
            systemImage: "bitcoinsign.bank.building",
            description: "Add a mint from Settings to get started."
        )
    }

    private var noCompatibleMintsView: some View {
        NativeEmptyState(
            title: "No Compatible Mints",
            systemImage: "exclamationmark.triangle",
            description: paymentMethod.map { "None of your mints support \($0.displayName) payments." }
        )
    }

    private var displayMints: [MintInfo] {
        let filteredMints: [MintInfo]
        if let paymentMethod {
            filteredMints = sourceMints.filter {
                $0.supportedMeltMethods.contains(paymentMethod)
            }
        } else {
            filteredMints = sourceMints
        }

        return filteredMints
            .sorted { lhs, rhs in
                let lhsSelected = selectedMint?.id == lhs.id
                let rhsSelected = selectedMint?.id == rhs.id
                if lhsSelected != rhsSelected { return lhsSelected }

                if let minimumAmount {
                    let lhsCanPay = lhs.balance >= minimumAmount
                    let rhsCanPay = rhs.balance >= minimumAmount
                    if lhsCanPay != rhsCanPay { return lhsCanPay }
                }

                if lhs.balance == rhs.balance {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.balance > rhs.balance
            }
    }

    private var sourceMints: [MintInfo] {
        mints ?? walletManager.mints
    }

    private var mintListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(displayMints) { mint in
                    Button(action: { selectMint(mint) }) {
                        HStack(spacing: 12) {
                            mintIcon(for: mint)
                                .overlay(alignment: .bottomTrailing) {
                                    if selectedMint?.id == mint.id {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 12, height: 12)
                                            .overlay(
                                                Circle().stroke(Color(.systemBackground), lineWidth: 2)
                                            )
                                            .offset(x: 2, y: 2)
                                    }
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mint.name)
                                    .font(.body.weight(.medium))
                                Text(mintSubtitle(for: mint))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedMint?.id == mint.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                rowsHeight = newHeight
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func mintSubtitle(for mint: MintInfo) -> String {
        let balance = SettingsManager.shared.formatAmountBalance(mint.balance) + " sat"
        if let minimumAmount, mint.balance < minimumAmount {
            return "\(balance) - below amount"
        }

        guard paymentMethod != nil else {
            return balance
        }

        let methods = mint.supportedMeltMethods
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.displayName)
            .joined(separator: ", ")
        return "\(balance) - \(methods)"
    }

    @ViewBuilder
    private func mintIcon(for mint: MintInfo) -> some View {
        if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
            CachedAsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                mintIconPlaceholder
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            mintIconPlaceholder
        }
    }

    private var mintIconPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "bitcoinsign.bank.building")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
    }

    private func selectMint(_ mint: MintInfo) {
        if let onSelect {
            selectedMint = mint
            onSelect(mint)
            dismiss()
            return
        }

        Task {
            do {
                try await walletManager.setActiveMint(mint)
                await MainActor.run {
                    selectedMint = mint
                    dismiss()
                }
            } catch {
                print("Failed to set active mint: \(error)")
                await MainActor.run {
                    selectedMint = mint
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Add Mint To Pay Sheet

/// Medium-detent picker shown when a Cashu Request can only be paid by adding a
/// mint the user doesn't hold yet. Lists the request's accepted mint URLs as
/// rich rows — real name + icon fetched through CDK
/// (`WalletManager.fetchMintPreviewInfo`), degrading to host + monogram when
/// offline. Tapping a row hands the URL back to the caller, which runs the
/// acquire-then-pay flow (and owns its own haptic). Replaces the old
/// `.confirmationDialog` balloon so this matches the app's other mint pickers.
struct AddMintToPaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager

    let mints: [String]
    let onSelect: (String) -> Void

    /// CDK mint-info previews keyed by mint URL. Rows show host + monogram
    /// immediately and upgrade to real name + icon as these land.
    @State private var previews: [String: MintPreview] = [:]

    private struct MintPreview {
        let name: String?
        let iconUrl: String?
    }

    /// Measured height of the rows, driving a content-fit detent so the sheet
    /// hugs its mints instead of stretching to `.medium`.
    @State private var rowsHeight: CGFloat = 0

    /// Fixed sheet chrome around the measured rows: drag indicator + inline nav
    /// bar + a little bottom breathing room. Device- and width-independent — it's
    /// system chrome, not per-row or per-device layout padding.
    private static let navChrome: CGFloat = 96

    private var detentHeight: CGFloat {
        // Estimate the first frame (before measurement lands) so the sheet opens
        // near the right size instead of growing up from zero.
        let rows = rowsHeight > 0 ? rowsHeight : CGFloat(mints.count) * 68
        return rows + Self.navChrome
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(mints, id: \.self) { url in
                        Button {
                            dismiss()
                            onSelect(url)
                        } label: {
                            row(for: url)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    rowsHeight = newHeight
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Add a mint to pay")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        .onAppear(perform: loadPreviews)
    }

    @ViewBuilder
    private func row(for url: String) -> some View {
        let host = mintHost(url)
        let name = resolvedName(for: url)
        HStack(spacing: 12) {
            MintAvatarView(iconUrl: previews[url]?.iconUrl, name: name ?? host, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? host)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(name == nil ? "Not in your wallet yet" : host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name ?? host)
        .accessibilityHint("Adds this mint and pays")
    }

    private func resolvedName(for url: String) -> String? {
        guard let name = previews[url]?.name, !name.isEmpty else { return nil }
        return name
    }

    private func mintHost(_ url: String) -> String { URL(string: url)?.host ?? url }

    private func loadPreviews() {
        for url in mints where previews[url] == nil {
            Task { @MainActor in
                guard let info = await walletManager.fetchMintPreviewInfo(url: url) else { return }
                previews[url] = MintPreview(name: info.name, iconUrl: info.iconUrl)
            }
        }
    }
}

// MARK: - Method Picker Sheet

/// Content-fit picker for choosing a receive/send rail. Mirrors
/// `MintSelectorSheet`: plain rows with a friendly title + descriptor and a
/// trailing checkmark, dismiss-on-select. Sizes itself to its (2-4) rows
/// instead of stretching to `.medium` — same technique as `AddMintToPaySheet`.
struct MethodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// The live option, for the trailing checkmark + VoiceOver `.isSelected`.
    /// Read-only: the parent owns the (method, isAmountless) state this maps
    /// to, so the parent can react to a pick with side effects (e.g.
    /// auto-create) race-free.
    let selectedOption: ReceiveMethodOption
    let options: [ReceiveMethodOption]
    var onSelect: (ReceiveMethodOption) -> Void

    /// Measured height of the option rows, driving a content-fit detent.
    @State private var rowsHeight: CGFloat = 0

    /// Fixed sheet chrome around the measured rows: drag indicator + inline nav
    /// bar + a little bottom breathing room.
    private static let navChrome: CGFloat = 96

    private var detentHeight: CGFloat {
        let rows = rowsHeight > 0 ? rowsHeight : CGFloat(options.count) * 68
        return rows + Self.navChrome
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options) { option in
                        Button(action: { select(option) }) {
                            HStack(spacing: 12) {
                                optionIcon(for: option)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.friendlyTitle)
                                        .font(.body.weight(.medium))
                                    Text(option.friendlyDescriptor)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedOption == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(option.friendlyTitle). \(option.friendlyDescriptor)")
                        .accessibilityAddTraits(selectedOption == option ? .isSelected : [])
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    rowsHeight = newHeight
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Receive with")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
    }

    private func select(_ option: ReceiveMethodOption) {
        if option != selectedOption {
            HapticFeedback.selection()
        }
        onSelect(option)   // parent mutates state + may auto-create
        dismiss()
    }

    private func optionIcon(for option: ReceiveMethodOption) -> some View {
        Image(systemName: option.navSymbol)
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 24)
            .accessibilityHidden(true)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Cashu Token Share Sheet

/// Share sheet that formats cashu tokens with the cashu: URL scheme
struct CashuTokenShareSheet: UIViewControllerRepresentable {
    let token: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Format token with cashu: URL scheme for easy sharing
        let cashuUrl = "cashu:\(token)"
        return UIActivityViewController(activityItems: [cashuUrl], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SendView()
        .environmentObject(WalletManager())
}
