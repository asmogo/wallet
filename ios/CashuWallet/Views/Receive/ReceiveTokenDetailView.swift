import SwiftUI
import Cdk

/// Immutable review copy derived from a decoded token before the recipient can
/// claim it. Keeping normalization and accessibility text outside the view
/// makes nil/blank handling and the review-before-claim order directly testable.
struct ReceiveTokenReviewPresentation: Equatable {
    struct Memo: Equatable {
        let text: String

        var accessibilityLabel: String { "Memo" }
        var accessibilityValue: String { text }
        var accessibilityIdentifier: String { "receive-token-review-memo" }
    }

    enum ConfirmationElement: Equatable {
        case memo(String)
        case claimAction
    }

    let memo: Memo?

    var claimActionTitle: String { "Receive" }

    init(rawMemo: String?) {
        let trimmed = rawMemo?.trimmingCharacters(in: .whitespacesAndNewlines)
        memo = trimmed.flatMap { $0.isEmpty ? nil : Memo(text: $0) }
    }

    /// The confirmation contract: when a sender memo exists, the recipient
    /// reviews it before the claim action becomes the next flow element.
    var confirmationElements: [ConfirmationElement] {
        var elements = memo.map { [ConfirmationElement.memo($0.text)] } ?? []
        elements.append(.claimAction)
        return elements
    }
}

struct ReceiveTokenDetailView: View {
    let tokenString: String
    var onComplete: (() -> Void)? = nil
    /// Custom redeem path. When set it replaces `walletManager.receiveTokens`
    /// on the Receive tap (the NUT-18 approval flow claims through the
    /// listener so the payment stays linked to its Cashu Request). The owner
    /// of the closure also owns the received-toast notification.
    var claim: (() async throws -> UInt64)? = nil
    /// Replaces the "Receive Later" secondary action when set — approval-flow
    /// payments can't be parked for later, only claimed or declined.
    var secondaryActionTitle: String? = nil
    var onSecondaryAction: (() -> Void)? = nil
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    private let reviewPresentation: ReceiveTokenReviewPresentation
    @State private var tokenAmount: UInt64
    /// The token's own unit ("sat", "eur", "usd", or a custom string). Drives
    /// unit-native amount/fee formatting so a non-sat token isn't shown as sats.
    @State private var tokenUnit: String
    @State private var receiveFee: UInt64?
    @State private var isValidToken = false
    /// The net amount CDK actually credited (token value minus the mint's
    /// receive-swap fee), set once the claim completes. Drives the success
    /// screen so "Amount" matches the balance change instead of the token's
    /// gross value — receiving an 11-sat token that nets 10 must read as 10.
    @State private var claimedAmount: UInt64?
    @State private var mintUrl: String = ""
    @State private var errorMessage: String?
    @State private var isLoadingFee = true
    @State private var p2pkPubkeys: [String] = []
    @State private var tokenLockedToKnownKey = true
    @State private var mintIsKnown = true

    /// Drives the shared full-screen status view once the user taps Receive:
    /// nil = confirm screen, .processing = "Claiming…", .success = "Payment
    /// Received!". A brief `.processing` beat lets the redeem read as an
    /// action that happened rather than an instant jump. Mirrors the send/pay
    /// side (`SendView.paymentPhase`).
    @State private var phase: PaymentStatusView.Phase?

    init(
        tokenString: String,
        onComplete: (() -> Void)? = nil,
        claim: (() async throws -> UInt64)? = nil,
        secondaryActionTitle: String? = nil,
        onSecondaryAction: (() -> Void)? = nil
    ) {
        self.tokenString = tokenString
        self.onComplete = onComplete
        self.claim = claim
        self.secondaryActionTitle = secondaryActionTitle
        self.onSecondaryAction = onSecondaryAction
        // Parse the amount eagerly so the hero starts at the token's value on
        // frame 1. Token.decode is a pure Cdk call (no wallet/settings env), so
        // this is safe in init. Deriving it here avoids the 0 → N flip that
        // parseToken() in .onAppear would otherwise make, which fires
        // CurrencyAmountDisplay's .animation(value: sats) while PayFlowScaffold's
        // GeometryReader is still resolving — sliding the hero in from the
        // top-left. Env-dependent state (mintIsKnown / tokenLockedToKnownKey /
        // fee) still resolves in onAppear; the hero may tick down by the fee
        // once the preview lands (netReceiveAmount), which animates in place.
        let decoded = try? Token.decode(encodedToken: tokenString)
        let amount = decoded.flatMap { try? $0.value().value } ?? 0
        _tokenAmount = State(initialValue: amount)
        let unit = (decoded?.unit() ?? nil).map(PaymentRequestDecoder.unitDescription) ?? "sat"
        _tokenUnit = State(initialValue: unit)
        reviewPresentation = ReceiveTokenReviewPresentation(rawMemo: decoded?.memo())
    }

    /// Whether the token is denominated in sats (the common path — keep the
    /// sats↔fiat hero) versus a mint account unit (eur/usd/custom).
    private var isSatUnit: Bool { tokenUnit.lowercased() == "sat" }

    /// What claiming will actually credit: the token's gross value minus the
    /// previewed receive-swap fee. The hero and the success estimate both show
    /// this — a 5001-sat token that redeems for 5000 must read as 5000, with
    /// the fee row accounting for the difference. Equals the gross value until
    /// the async fee preview lands.
    private var netReceiveAmount: UInt64 { tokenAmount - min(receiveFee ?? 0, tokenAmount) }

    private var unitCurrency: any Currency { CurrencyRegistry.currency(forMintUnit: tokenUnit) }

    /// Format a base-unit amount in the token's unit: sats keep the existing
    /// style; other units render via their `Currency` (e.g. "€5.00", "500 EUR").
    private func formatAmount(_ base: UInt64) -> String {
        isSatUnit
            ? AmountFormatter.sats(base, useBitcoinSymbol: settings.useBitcoinSymbol)
            : CurrencyAmount(value: base, currency: unitCurrency).formatted()
    }

    /// Fee formatted in the token's unit, honoring the ₿-symbol setting exactly
    /// as `formatAmount` does — a screen must never pair "₿1" with "1 sat".
    private func formatFee(_ base: UInt64) -> String {
        isSatUnit
            ? AmountFormatter.sats(base, useBitcoinSymbol: settings.useBitcoinSymbol)
            : CurrencyAmount(value: base, currency: unitCurrency).formatted()
    }

    var body: some View {
        NavigationStack {
            Group {
            if let phase {
                statusView(phase)
            } else {
                confirmContent
            }
            }
            .animation(.smooth(duration: 0.3), value: phase)
            // Opacity-only fade on screen entry (once). Sits OUTSIDE the phase-morph
            // scope above; each .animation keys on a different value, so the entry
            // fade and the confirm→success morph never cross-animate each other.
            .screenEntryFade()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton {
                        switch phase {
                        case .none:              dismiss()
                        case .success, .failure: finish()
                        default:                 break   // .processing — button stays disabled
                        }
                    }
                    .disabled(phase == .processing)
                }

                ToolbarItem(placement: .principal) {
                    Text("Receive Ecash")
                        .font(.headline)
                }
            }
        }
        .task(id: tokenString) {
            await parseToken()
        }
        .interactiveDismissDisabled(phase == .processing)
    }

    /// The confirm step, on the shared `PayFlowScaffold` so its details block
    /// sits at the SAME locked Y as the success screen (`PaymentStatusView`
    /// uses the same scaffold). Tapping Receive then morphs the hero
    /// (amount → checkmark + title) in place, with no layout jump — and the
    /// rows are hairline-on-canvas, matching every other detail surface.
    private var confirmContent: some View {
        PayFlowScaffold {
            if isSatUnit {
                CurrencyAmountDisplay(
                    sats: netReceiveAmount,
                    primary: $settings.amountDisplayPrimary
                )
            } else {
                // Non-sat account unit: show it directly, no BTC-price flip.
                AmountLockup(
                    parts: AmountParts.parse(formatAmount(netReceiveAmount)),
                    role: .amountHero,
                    value: Double(netReceiveAmount)
                )
            }
        } details: {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    if isLoadingFee {
                        HStack {
                            Text("Fee")
                                .foregroundStyle(.secondary)
                            Spacer()
                            ProgressView().scaleEffect(0.8)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 14)
                    } else if let receiveFee {
                        // Prospective charge (docs/product/copy-guidance.md):
                        // "No fee" states the user is charged nothing; a bare
                        // "0 sat" reads as an accounting figure.
                        detailRow(
                            label: "Fee",
                            value: receiveFee == 0 ? "No fee" : formatFee(receiveFee)
                        )
                    } else {
                        HStack {
                            Text("Fee unavailable")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") {
                                Task { await calculateFee() }
                            }
                            .disabled(!isValidToken)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 14)
                    }
                    detailRow(label: "Mint", value: shortMintUrl(mintUrl))
                    if let memo = reviewPresentation.memo {
                        memoRow(memo)
                    }
                    if !p2pkPubkeys.isEmpty {
                        lockedToRow
                    }
                }
                .padding(.horizontal)

                if !mintIsKnown && !mintUrl.isEmpty {
                    InlineNotice(
                        message: "You haven't used \(shortMintUrl(mintUrl)) before. Receiving adds it to your wallet — only continue if you trust it.",
                        title: "New mint",
                        severity: .caution
                    )
                    .padding(.horizontal)
                }

                if let error = errorMessage {
                    InlineNotice(message: error, severity: .error)
                        .padding(.horizontal)
                }
            }
        } footer: {
            VStack(spacing: 12) {
                Button(action: receiveToken) {
                    Text(reviewPresentation.claimActionTitle)
                }
                .glassButton()
                .disabled(!isValidToken || !tokenLockedToKnownKey || isLoadingFee || receiveFee == nil)

                if let secondaryActionTitle, let onSecondaryAction {
                    Button(action: onSecondaryAction) {
                        Text(secondaryActionTitle)
                    }
                    .ctaStackTextLinkButton()
                } else {
                    Button(action: receiveLater) {
                        Text("Receive Later")
                    }
                    .ctaStackTextLinkButton()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    /// Full-screen status shown once the user taps Receive — the exact same
    /// `PaymentStatusView` the pay/send flows use, so receiving reads
    /// identically (spinner → checkmark → title → detail block → Done). Passing
    /// the live `phase` through keeps one mounted instance, so the ring morphs
    /// into the check in place and the success haptic fires exactly once.
    private func statusView(_ phase: PaymentStatusView.Phase) -> some View {
        PaymentStatusView(
            details: successRows,
            phase: phase,
            processingTitle: "Claiming…",
            successTitle: "Payment Received!",
            failureTitle: "Couldn't Receive",
            onDone: { finish() },
            onRetry: { withAnimation(.smooth(duration: 0.3)) { self.phase = nil } }   // back to the confirm screen
        )
    }

    /// Status rows for the processing/success screen. "Amount" is the net
    /// credited to the balance: the estimate (token value − previewed fee)
    /// while claiming, then the exact net CDK returned. The fee row likewise
    /// firms up from the preview to the actually charged fee; a zero fee
    /// omits the row — receipts never render "0 sat" (accounting value,
    /// docs/product/copy-guidance.md).
    private var successRows: [PaymentStatusView.DetailRow] {
        let paidFee = claimedAmount.map { tokenAmount - min($0, tokenAmount) }
        var rows: [PaymentStatusView.DetailRow] = [
            .init(
                label: "Amount",
                value: formatAmount(claimedAmount ?? netReceiveAmount)
            ),
        ]
        let settledFee = paidFee ?? receiveFee ?? 0
        if settledFee > 0 {
            rows.append(.init(label: "Fee", value: formatFee(settledFee)))
        }
        if !mintUrl.isEmpty {
            rows.append(.init(
                label: "Mint",
                value: shortMintUrl(mintUrl)
            ))
        }
        return rows
    }

    /// Finalize the flow (Done / close after success): hand control back to the
    /// presenter if it owns dismissal, otherwise dismiss directly.
    private func finish() {
        if let onComplete = onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }

    // MARK: - Helpers

    /// The "locked to" row: shows "Your key" when the wallet holds the matching
    /// key, otherwise the npub the ecash is locked to plus a caution glyph.
    private var lockedToRow: some View {
        HStack {
            Text("Locked to")
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Text(lockedKeyLabel)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: tokenLockedToKnownKey ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(tokenLockedToKnownKey ? Color.secondary : Color.orange)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    private var lockedKeyLabel: String {
        if tokenLockedToKnownKey { return "Your key" }
        if let first = p2pkPubkeys.first { return P2PKKeyDisplay.shortLabel(forPubkey: first) }
        return "Unknown key"
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
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

    /// Sender-provided prose stays fully reviewable instead of inheriting the
    /// single-line, middle-truncated treatment used for identifiers.
    private func memoRow(_ memo: ReceiveTokenReviewPresentation.Memo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(memo.accessibilityLabel)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            Text(memo.text)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(memo.accessibilityLabel)
        .accessibilityValue(memo.accessibilityValue)
        .accessibilityIdentifier(memo.accessibilityIdentifier)
    }

    func shortMintUrl(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    // MARK: - Actions

    private func parseToken() async {
        isValidToken = false
        do {
            let token = try walletManager.decodeToken(tokenString: tokenString)
            // `tokenAmount` is parsed eagerly in init (same Token.decode path), so
            // the hero already holds the final value — no reassignment here, which
            // would be a no-op at best and re-trigger the entry animation at worst.
            let mint = try token.mintUrl()
            self.mintUrl = mint.url
            self.mintIsKnown = walletManager.isMintKnown(url: mint.url)
            isValidToken = true

            let tokenP2PKPubkeys = token.p2pkPubkeys()
            self.p2pkPubkeys = tokenP2PKPubkeys
            let hasMatch = tokenP2PKPubkeys.contains { settings.isKnownP2PKPublicKey($0) }
            self.tokenLockedToKnownKey = tokenP2PKPubkeys.isEmpty || hasMatch
            if !self.tokenLockedToKnownKey {
                errorMessage = "This ecash is locked to a key you don't hold. Ask the sender to lock it to your key instead."
            }

            await calculateFee()
        } catch {
            errorMessage = "Invalid token. \(error.userFacingWalletMessage)"
            isLoadingFee = false
        }
    }

    private func calculateFee() async {
        guard !Task.isCancelled else { return }
        isLoadingFee = true
        receiveFee = nil
        do {
            let fee = try await walletManager.calculateReceiveFee(tokenString: tokenString)
            guard !Task.isCancelled else { return }
            receiveFee = fee
        } catch {
            guard !Task.isCancelled else { return }
        }
        isLoadingFee = false
    }

    func receiveToken() {
        guard phase != .processing, isValidToken, !isLoadingFee, receiveFee != nil else { return }
        guard tokenLockedToKnownKey else {
            errorMessage = "This token is locked to a key you don't have. Ask the sender to lock it to your key instead."
            return
        }

        errorMessage = nil
        withAnimation(.smooth(duration: 0.3)) { phase = .processing }
        Task {
            // Minimum on-screen time for the "Claiming…" spinner, run
            // concurrently with the real redeem so we wait max(network, 0.5s) —
            // a legible beat when redemption is instant, no extra cost when it
            // isn't. Not a fake delay: the redeem itself hits the mint.
            async let minHold: Void = Task.sleep(nanoseconds: 500_000_000)
            do {
                let receivedAmount: UInt64
                if let claim {
                    receivedAmount = try await claim()
                } else {
                    receivedAmount = try await walletManager.receiveTokens(tokenString: tokenString)
                }
                try? await minHold
                await MainActor.run {
                    // CDK returns the net amount credited; the difference to the
                    // token's gross value is the mint's receive-swap fee.
                    claimedAmount = receivedAmount
                    let paidFee = tokenAmount - min(receivedAmount, tokenAmount)
                    // Post the home-screen receipt toast (seen after Done), then
                    // morph the spinner into the shared full-screen success. It
                    // owns the success haptic on the transition, so don't buzz here.

                    // A custom claim path posts its own notification, so don't
                    // double up here.
                    if claim == nil {
                        NotificationCenter.default.post(
                            name: .cashuTokenReceived,
                            object: nil,
                            userInfo: ["amount": receivedAmount, "fee": paidFee, "unit": tokenUnit]
                        )
                    }
                    withAnimation(.smooth(duration: 0.3)) { phase = .success }
                }
            } catch {
                try? await minHold   // let the spinner settle before the failure
                await MainActor.run {
                    // Route redeem failures through the SAME full-screen status view
                    // as success (red X + terminal-aware CTA), mirroring the send/pay
                    // side — not the inline confirm-screen notice. PaymentStatusView
                    // owns the error haptic, so don't buzz here.
                    let message = error.walletMessage
                    withAnimation(.smooth(duration: 0.3)) {
                        phase = .failure(
                            message: message.text,
                            isCaution: message.severity == .caution,
                            isTerminal: message.recoverability == .terminal
                        )
                    }
                }
            }
        }
    }

    func receiveLater() {
        guard isValidToken, phase != .processing else { return }
        let pendingReceive = PendingReceiveToken(
            tokenId: UUID().uuidString,
            token: tokenString,
            amount: tokenAmount,
            unit: tokenUnit,
            date: Date(),
            mintUrl: mintUrl,
            memo: reviewPresentation.memo?.text
        )
        walletManager.savePendingReceiveToken(pendingReceive)
        // Rebuild History so the parked token shows as a claimable row right away.
        Task { await walletManager.loadTransactions() }
        if let onComplete = onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }
}
