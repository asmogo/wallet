import SwiftUI

// MARK: - Wallet surfaces

/// The home bottom-sheet slot, bound by `MainWalletView`'s single
/// `.sheet(item:)`. Exactly one flow sheet is ever presented: story
/// progression swaps the case in place (SwiftUI morphs the open sheet), and
/// any transition to a *different* surface goes through
/// `NavigationManager.present` so the outgoing dismissal finishes first.
enum WalletSheet: Identifiable {
    case receive
    case send(prefill: String?)
    case sendEdit(prefill: String)
    case sendAmount(SendAmountDestination)
    case cashuRequestPay(CashuPaymentRequestSummary)
    case scanner
    case sendEcash
    case receiveLightning
    case meltInvoice(String)
    case connectMint
    case discoverMints

    var id: String {
        switch self {
        case .receive: return "receive"
        // Prefill rides the payload without changing identity, so handing a
        // pasted payable from Receive to Send morphs the open sheet instead
        // of tearing it down and re-presenting.
        case .send: return "send"
        case .sendEdit: return "sendEdit"
        case .sendAmount: return "sendAmount"
        case .cashuRequestPay(let summary): return "creq-\(Data(summary.encoded.utf8).sha256().base64EncodedString())"
        case .scanner: return "scanner"
        case .sendEcash: return "sendEcash"
        case .receiveLightning: return "receiveLightning"
        case .meltInvoice(let invoice): return "meltInvoice-\(Data(invoice.utf8).sha256().base64EncodedString())"
        case .connectMint: return "connectMint"
        case .discoverMints: return "discoverMints"
        }
    }
}

/// The full-screen flow-page slot, bound by `ContentView`'s single
/// `.fullScreenCover(item:)`: payment pages that read as a brand-new screen
/// with nothing visible beneath (token claim, scan-routed melts, held approval).
enum FlowCover: Identifiable {
    case receiveToken(String)
    case heldApproval(PendingReceiveToken)
    case melt(
        request: String,
        mode: MeltView.MeltMode,
        autoQuote: Bool,
        explanation: CashuRequestRouteExplanation?
    )

    var id: String {
        switch self {
        case .receiveToken(let token): return "token-\(Data(token.utf8).sha256().base64EncodedString())"
        case .heldApproval(let pending): return "held-\(pending.tokenId)"
        case .melt(let request, let mode, _, _): return "melt-\(mode)-\(Data(request.utf8).sha256().base64EncodedString())"
        }
    }
}

/// One of the two mutually exclusive flow-surface slots.
enum FlowSurface {
    case sheet(WalletSheet)
    case cover(FlowCover)
}

// MARK: - Navigation Manager

/// The single owner of the app's payment surfaces, and the deep-link entry
/// point for the cashu: URL scheme.
///
/// Contract (mirror of Android's `AuthenticatedShell`): at most one flow
/// surface is open at a time; progression replaces, never stacks; dismissing
/// a surface lands on the screen beneath it; unprompted surfaces (deep-linked
/// tokens, incoming NUT-18 approvals) defer until the shell is idle.
@MainActor
final class NavigationManager: ObservableObject {

    // MARK: Surface slots

    /// The home bottom sheet. Direct assignment swaps content in place (the
    /// iOS analogue of Android's AnimatedContent flow swap); use `present`
    /// when another surface may still be up.
    @Published var activeWalletSheet: WalletSheet? {
        didSet {
            if oldValue != nil, activeWalletSheet == nil { dismissalInFlight = true }
        }
    }

    /// The full-screen flow page.
    @Published var activeFlowCover: FlowCover? {
        didSet {
            if oldValue != nil, activeFlowCover == nil { dismissalInFlight = true }
        }
    }

    /// True from a surface starting to dismiss (programmatic nil or user
    /// swipe — both nil the slot) until its `onDismiss` callback. Presenting
    /// inside that window must park, not stack.
    @Published private(set) var dismissalInFlight = false

    /// Parked destination, promoted when the outgoing surface's dismiss
    /// animation completes — the analogue of Android's
    /// `WalletFlowHandoffCoordinator`. Consume-once; last request wins.
    private var pendingSurface: FlowSurface?

    /// Deep-linked tokens held until the shell is idle. Nothing is dropped:
    /// the queue drains one token per idle transition.
    @Published private(set) var heldDeepLinkTokens: [String] = []

    var isFlowSurfaceOpen: Bool {
        activeWalletSheet != nil || activeFlowCover != nil || dismissalInFlight
    }

    // MARK: Presenting

    /// Present `surface` now if the shell is idle; otherwise dismiss whatever
    /// is up and park `surface` to present once the dismissal completes.
    func present(_ surface: FlowSurface) {
        guard isFlowSurfaceOpen else {
            apply(surface)
            return
        }
        pendingSurface = surface
        if activeWalletSheet != nil { activeWalletSheet = nil }
        if activeFlowCover != nil { activeFlowCover = nil }
    }

    /// Wire to the home sheet's `onDismiss` — SwiftUI fires it after the
    /// dismiss animation, the equivalent of Android's `invokeOnCompletion`.
    func sheetDidDismiss() { surfaceDidDismiss() }

    /// Wire to the flow cover's `onDismiss`.
    func coverDidDismiss() { surfaceDidDismiss() }

    private func surfaceDidDismiss() {
        dismissalInFlight = false
        if let pending = pendingSurface {
            pendingSurface = nil
            apply(pending)
        }
    }

    private func apply(_ surface: FlowSurface) {
        switch surface {
        case .sheet(let sheet): activeWalletSheet = sheet
        case .cover(let cover): activeFlowCover = cover
        }
    }

    // MARK: Deep links

    /// Handle an incoming cashu: URL. The token is queued, never presented
    /// directly — `ContentView` presents it once the shell is idle and the
    /// wallet runtime is ready. An open payment flow is never interrupted.
    func handleDeepLink(url: URL) {
        // Format: cashu:cashuA... or cashu://cashuA...
        guard url.scheme?.lowercased() == "cashu" else { return }

        var token: String
        if let host = url.host {
            token = host + url.path
        } else {
            token = String(url.absoluteString.dropFirst("cashu:".count))
        }
        token = token.removingPercentEncoding ?? token

        guard TokenParser.isCashuDeepLinkToken(token) else {
            AppLogger.wallet.debug("Invalid cashu token in deep link")
            return
        }
        heldDeepLinkTokens.append(token)
    }

    /// Pop the next queued deep-link token. Call only when about to present it.
    func consumeHeldDeepLinkToken() -> String? {
        guard !heldDeepLinkTokens.isEmpty else { return nil }
        return heldDeepLinkTokens.removeFirst()
    }

    // MARK: Home-scanner intake

    /// Judge a payload scanned on the home scanner: junk is rejected inline
    /// (the scanner shows the error and re-arms), a mint URL is copied and
    /// confirmed, everything routable is accepted. The clipboard copy lives
    /// here so the notice and its side effect can't diverge.
    func classifyScannedPayload(_ content: String, walletManager: WalletManager) -> ScanIntake {
        switch ScanRouter.route(
            content,
            routeForCashuPaymentRequest: walletManager.routeForCashuPaymentRequest
        ) {
        case .receiveToken, .cashuRequestPay, .melt:
            return .accept
        case .mintURL(let url):
            UIPasteboard.general.string = url
            return .notice(message: "Mint URL copied to clipboard")
        case .unrecognized:
            return .reject(
                message: "This QR code isn't a payment code we recognize. Scan a Lightning invoice, ecash token, or Cashu Request."
            )
        }
    }

    /// Route an accepted home-scan payload. The scanner sheet is still up
    /// when this fires, so `present` always parks — the scanner closes
    /// first, then the result surface presents (Android scanner parity).
    func routeScannedPayload(_ content: String, walletManager: WalletManager) {
        switch ScanRouter.route(
            content,
            routeForCashuPaymentRequest: walletManager.routeForCashuPaymentRequest
        ) {
        case .receiveToken(let token):
            present(.cover(.receiveToken(token)))
        case .cashuRequestPay(let summary):
            present(.sheet(.cashuRequestPay(summary)))
        case .melt(let request, let mode, let autoQuote, let explanation):
            present(.cover(.melt(
                request: request,
                mode: mode,
                autoQuote: autoQuote,
                explanation: explanation
            )))
        case .mintURL, .unrecognized:
            break   // resolved inline by `classifyScannedPayload`
        }
    }
}

// MARK: - Scanned-payload routing

/// The scanner's verdict on a payload: deliver it, reject it inline and
/// re-arm, or show a neutral confirmation and close.
enum ScanIntake: Equatable {
    case accept
    case reject(message: String)
    case notice(message: String)
}

/// Where a scanned payload leads — mirrors Android's `routeScannedPayload`
/// decode table so the two scanners route identically.
enum ScannedPayloadRoute {
    case receiveToken(String)
    case cashuRequestPay(CashuPaymentRequestSummary)
    case melt(
        request: String,
        mode: MeltView.MeltMode,
        autoQuote: Bool,
        explanation: CashuRequestRouteExplanation?
    )
    case mintURL(String)
    case unrecognized
}

enum ScanRouter {
    /// Decode a scanned payload. Pure aside from the injected Cashu-request
    /// routing policy, so unit tests can drive the whole table.
    static func route(
        _ content: String,
        routeForCashuPaymentRequest: (CashuPaymentRequestSummary, String) -> CashuRequestRoute
    ) -> ScannedPayloadRoute {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token = TokenParser.normalizedToken(from: trimmed) {
            return .receiveToken(token)
        }
        if case .cashuPaymentRequest(let summary) = PaymentRequestDecoder.decode(
            trimmed, includeCashuPaymentRequests: true, preferCashuPaymentRequests: true
        ) {
            // Prefer ecash when a held mint can pay; otherwise fall back to a
            // bundled bolt11 (BIP-321) rather than dead-ending on an unheld mint.
            switch routeForCashuPaymentRequest(summary, trimmed) {
            case .payWithEcash, .acquireThenPay:
                return .cashuRequestPay(summary)
            case .payBolt11Fallback(let bolt11):
                return .melt(
                    request: bolt11,
                    mode: .lightning,
                    autoQuote: true,
                    explanation: CashuRequestRouteExplanation(state: .lightningFallback)
                )
            }
        }
        let decoded = PaymentRequestDecoder.decode(trimmed)
        switch decoded {
        case .bolt11, .bolt12:
            let request = PaymentRequestDecoder.encodedLightningRequest(from: trimmed)
                ?? PaymentRequestParser.normalizeLightningRequest(trimmed)
            return .melt(
                request: request,
                mode: .lightning,
                autoQuote: PaymentRequestDecoder.amountLocked(decoded),
                explanation: nil
            )
        case .onchain:
            return .melt(
                request: PaymentRequestParser.normalizeBitcoinRequest(trimmed),
                mode: .onchain,
                autoQuote: false,
                explanation: nil
            )
        case .lightningAddress:
            return .melt(request: trimmed, mode: .lightning, autoQuote: false, explanation: nil)
        case .cashuPaymentRequest, .unrecognized:
            if trimmed.lowercased().hasPrefix("https://"), trimmed.contains("mint") {
                return .mintURL(trimmed)
            }
            return .unrecognized
        }
    }
}
