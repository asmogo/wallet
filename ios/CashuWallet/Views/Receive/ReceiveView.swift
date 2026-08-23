import SwiftUI
import UIKit

// MARK: - Unified receive sheet (Send-style)

/// The single entry point for receiving — the mirror of `UnifiedSendView`'s
/// input step so Send and Receive read as one system. A paste field ("Paste a
/// Cashu token") sits above three full-width destination rows: Scan, Ecash, and
/// Bitcoin. Pasting or scanning a bearer *token*
/// routes into the claim screen; pasting anything else payable (invoice,
/// address, Cashu Request) is really a Send, so it's handed back to the Send
/// flow — the symmetric inverse of `UnifiedSendView` bouncing a pasted token to
/// the receive-this screen. Ecash mints a fresh Cashu Request and shows its QR;
/// Bitcoin opens the mint's Lightning / on-chain receive dialog.
struct UnifiedReceiveView: View {
    let onClose: () -> Void
    /// Hand a pasted / scanned *payable* destination back to Home's Send flow.
    let onSend: (String) -> Void
    /// A pasted/scanned bearer *token* opens the full-screen claim page via
    /// the shell — this sheet closes first, so the claim page's X lands on
    /// the wallet, never back on this input.
    let onOpenReceiveToken: (String) -> Void
    /// Swap the sheet content to the Lightning / on-chain receive flow.
    let onReceiveLightning: () -> Void

    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tokenInput = ""
    @State private var inputHint: String?
    @State private var route: ReceiveRoute?
    @State private var showingScanner = false
    @State private var autoRouteTask: Task<Void, Never>?
    @State private var clipboardCheckTask: Task<Void, Never>?

    /// Measured height of the input body (field + methods). Drives a content-fit
    /// detent so the actions stay thumb-reachable — same technique as
    /// `UnifiedSendView`'s compact input step.
    @State private var compactContentHeight: CGFloat = 0

    /// The freshly-minted Cashu Request detail — the one destination this
    /// sheet still presents itself; its close tears down to the wallet.
    private enum ReceiveRoute: Identifiable {
        case request(CashuRequest)
        case requestFailure(String)
        var id: String {
            switch self {
            case .request(let request): return "request-\(request.id)"
            case .requestFailure: return "request-failure"
            }
        }
    }

    var body: some View {
        NavigationStack {
            inputForm
                .frame(maxWidth: .infinity, alignment: .top)
                .navigationTitle("Receive")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingScanner) {
                    ScannerWrapperView(onScanned: handleScanned)
                        .environmentObject(walletManager)
                        .canvasSheetBackground()
                }
                .fullScreenCover(item: $route) { routeView($0).canvasSheetBackground() }
                .onChange(of: tokenInput) { handleInputChange() }
                .onAppear {
                    guard let token = Self.automaticReceiveClipboardToken(
                        enabled: settings.autoPasteEcashReceive,
                        currentInput: tokenInput,
                        clipboardText: { UIPasteboard.general.string }
                    ) else { return }
                    clipboardCheckTask = Task { @MainActor in
                        await autoPasteClipboardToken(token)
                    }
                }
                .onDisappear { autoRouteTask?.cancel(); clipboardCheckTask?.cancel() }
        }
        .contentFitDetent(compactContentHeight)
        .presentationDragIndicator(.visible)
        .compactBottomSheetSurface()
    }

    /// The clipboard token to auto-paste when the receive input appears, if
    /// any. Honors the privacy setting and never replaces explicit input —
    /// mirrors Android `ReceiveEcashScreen.automaticReceiveClipboardToken`.
    static func automaticReceiveClipboardToken(
        enabled: Bool,
        currentInput: String,
        clipboardText: () -> String?
    ) -> String? {
        guard enabled,
              currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let clipboardText = clipboardText() else { return nil }
        return TokenParser.normalizedToken(from: clipboardText)
    }

    /// Whether an auto-pasted clipboard token should fill the input (and
    /// thereby auto-route to the claim page). Only a *confirmed-spent* token
    /// is suppressed — when the spent check can't run (offline, unreachable
    /// mint, undecodable token) we paste anyway and let the claim page
    /// surface its own error. Mirrors Android `shouldAutoPasteClipboardToken`.
    static func shouldAutoPasteClipboardToken(spent: Bool?) -> Bool {
        spent != true
    }

    /// Auto-pasting skips this sheet via the typed-input auto-route, so gate
    /// it on a NUT-07 spent check: a spent token would otherwise hijack every
    /// Receive tap just to fail on the claim page. Show a hint instead and
    /// leave the field empty so something else can be received.
    @MainActor
    private func autoPasteClipboardToken(_ token: String) async {
        let spent: Bool?
        if let mintUrl = TokenParser.mintUrl(from: token) {
            spent = try? await walletManager.checkTokenSpent(token: token, mintUrl: mintUrl)
        } else {
            spent = nil
        }
        // Don't clobber input the user typed while the check was in flight.
        guard !Task.isCancelled,
              tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if Self.shouldAutoPasteClipboardToken(spent: spent) {
            tokenInput = token
        } else {
            inputHint = "The token in your clipboard was already redeemed."
        }
    }

    // MARK: Input step

    private var inputForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            destinationField
                .padding(.horizontal)
                .padding(.top, 12)

            if let inputHint {
                InlineNotice(message: inputHint, severity: .caution)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                    )
            }

            receiveMethodList
                .padding(.horizontal)
                .padding(.top, 24)
        }
        .padding(.bottom, 24)
        // Animate on the measured body, inside the content-fit ScrollView, so the
        // hint's entrance and the detent's resize run as one motion.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25), value: inputHint != nil)
        .contentFitMeasured { compactContentHeight = $0 }
        .scrollDismissesKeyboard(.interactively)
    }

    private var destinationField: some View {
        HStack(alignment: .top, spacing: 12) {
            TextField("Paste a Cashu token", text: $tokenInput, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                    tokenInput = ""
                } label: {
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

    // MARK: Receive-method actions

    private var receiveMethodList: some View {
        VStack(spacing: 12) {
            MethodActionRow(
                icon: "qrcode.viewfinder",
                title: "Scan",
                subtitle: "Scan an ecash token",
                accessibilityLabel: "Scan QR code"
            ) {
                HapticFeedback.selection()
                showingScanner = true
            }

            MethodActionRow(
                icon: "banknote",
                title: "Ecash",
                subtitle: "Create an ecash request",
                accessibilityLabel: "Create a Cashu request",
                action: createNewRequest
            )
                .accessibilityIdentifier("wallet-flow-receiveEcash")

            MethodActionRow(
                icon: "bitcoinsign",
                title: "Bitcoin",
                subtitle: "Lightning or on-chain",
                accessibilityLabel: "Receive over Lightning or on-chain",
                enabled: walletManager.activeMint != nil,
                status: walletManager.activeMint == nil ? "Mint needed" : nil
            ) {
                HapticFeedback.selection()
                onReceiveLightning()
            }
            .accessibilityIdentifier("wallet-flow-receiveLightning")
        }
    }

    // MARK: Routing out

    @ViewBuilder
    private func routeView(_ route: ReceiveRoute) -> some View {
        switch route {
        case .request(let request):
            // CashuRequestDetailView renders its chrome via `.toolbar`, so it
            // needs an enclosing NavigationStack.
            NavigationStack {
                CashuRequestDetailView(
                    request: request,
                    onClose: { self.route = nil; onClose() }
                )
                .environmentObject(walletManager)
            }
        case .requestFailure(let message):
            NavigationStack {
                PaymentStatusView(
                    details: [],
                    phase: .failure(message: message),
                    failureTitle: "Couldn't Create Request",
                    onDone: { self.route = nil },
                    onRetry: { self.route = nil }
                )
                .navigationTitle("Receive Ecash")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCloseButton(action: { self.route = nil })
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func pasteFromClipboard() {
        guard let content = UIPasteboard.general.string else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HapticFeedback.selection()
        tokenInput = trimmed
        autoRouteNow(trimmed)
    }

    private func handleScanned(_ scanned: String) {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tokenInput = trimmed
        autoRouteNow(trimmed)
    }

    /// Typed input settles for a beat before routing (mirrors Send). Paste and
    /// scan are discrete high-confidence events and skip the debounce.
    private func handleInputChange() {
        autoRouteTask?.cancel()
        inputHint = nil
        let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        autoRouteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled,
                  tokenInput.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            autoRoute(trimmed)
        }
    }

    private func autoRouteNow(_ raw: String) {
        autoRouteTask?.cancel()
        autoRoute(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A bearer token redeems on the full-screen claim page; anything else
    /// payable is a Send, handed back to the Send flow. Inverts
    /// `UnifiedSendView.advance`'s token special-case.
    private func autoRoute(_ trimmed: String) {
        guard !trimmed.isEmpty, route == nil else { return }
        if let token = TokenParser.normalizedToken(from: trimmed) {
            HapticFeedback.selection()
            onOpenReceiveToken(token)
            return
        }
        let decoded = PaymentRequestDecoder.decode(
            trimmed, includeCashuPaymentRequests: true, preferCashuPaymentRequests: true
        )
        if case .unrecognized = decoded {
            inputHint = "That doesn't look like a Cashu token. Paste an ecash token to receive."
        } else {
            HapticFeedback.selection()
            onSend(trimmed)
        }
    }

    /// Mint a fresh NUT-18 Cashu Request and show its shareable QR — no
    /// intermediate form (past requests live in History).
    private func createNewRequest() {
        HapticFeedback.selection()
        let readiness = CashuRequestNostrReadiness.current()
        guard let configuration = readiness.requestConfiguration else {
            inputHint = readiness.recoveryMessage
            return
        }
        let id = CashuRequest.newId()
        do {
            let encoded = try PaymentRequestBuilder.build(
                id: id,
                amount: nil,
                unit: "sat",
                mints: [],
                description: nil,
                nostrPubkeyHex: configuration.publicKeyHex,
                relays: configuration.relays
            )
            let request = CashuRequestStore.shared.createNew(
                id: id,
                amount: nil,
                unit: "sat",
                mints: [],
                memo: nil,
                encoded: encoded
            )
            route = .request(request)
        } catch {
            AppLogger.ui.error("createNewRequest failed: \(String(describing: error), privacy: .public)")
            route = .requestFailure(error.userFacingWalletMessage)
        }
    }
}

#Preview {
    UnifiedReceiveView(
        onClose: {},
        onSend: { _ in },
        onOpenReceiveToken: { _ in },
        onReceiveLightning: {}
    )
    .environmentObject(WalletManager())
}
