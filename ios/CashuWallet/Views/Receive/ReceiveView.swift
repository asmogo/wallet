import SwiftUI
import UIKit

// MARK: - Unified receive sheet (Send-style)

/// The single entry point for receiving — the mirror of `UnifiedSendView`'s
/// input step so Send and Receive read as one system. A paste field ("Paste a
/// Cashu token") sits above a centered row of round glass buttons: Scan · Ecash
/// · Bitcoin, each with a one-word caption. Pasting or scanning a bearer *token*
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

    /// Measured height of the input body (field + methods). Drives a content-fit
    /// detent so the buttons stay thumb-reachable — same technique as
    /// `UnifiedSendView`'s compact input step.
    @State private var compactContentHeight: CGFloat = 0

    /// Fixed sheet chrome around measured content: drag indicator + inline nav
    /// bar + a little extra. Mirrors `UnifiedSendView`.
    private static let compactSheetChrome: CGFloat = 108
    private static let compactBodyEstimate: CGFloat = 220

    /// The freshly-minted Cashu Request detail — the one destination this
    /// sheet still presents itself; its close tears down to the wallet.
    private enum ReceiveRoute: Identifiable {
        case request(CashuRequest)
        var id: String {
            switch self {
            case .request(let request): return "request-\(request.id)"
            }
        }
    }

    private var compactDetentHeight: CGFloat {
        let body = compactContentHeight > 0 ? compactContentHeight : Self.compactBodyEstimate
        return body + Self.compactSheetChrome
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
                    tokenInput = token
                }
                .onDisappear { autoRouteTask?.cancel() }
        }
        .presentationDetents([.height(compactDetentHeight)])
        .presentationDragIndicator(.visible)
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

    // MARK: Input step

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
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                        )
                }

                // A centered row of round Liquid Glass icon buttons — the primary
                // "ways to receive" (Scan · Ecash · Bitcoin), one-word label under each.
                receiveMethodRow
                    .padding(.horizontal)
                    .padding(.top, 32)
            }
            .padding(.bottom, 24)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25), value: inputHint != nil)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                compactContentHeight = newHeight
            }
        }
        .scrollBounceBehavior(.basedOnSize)
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

    // MARK: Receive-method buttons

    /// The primary "ways to receive" — a centered row of round filled icon
    /// buttons (Apple's sheet-action-circle pattern; same component as Send).
    private var receiveMethodRow: some View {
        HStack(spacing: 40) {
            CircularGlassIconButton(icon: "qrcode.viewfinder", label: "Scan",
                                    a11y: "Scan QR code") {
                HapticFeedback.selection()
                showingScanner = true
            }

            CircularGlassIconButton(icon: "banknote", label: "Ecash",
                                    a11y: "Create a Cashu request",
                                    action: createNewRequest)
                .accessibilityIdentifier("wallet-flow-receiveEcash")

            CircularGlassIconButton(icon: "bitcoinsign", label: "Bitcoin",
                                    a11y: "Receive over Lightning or on-chain") {
                HapticFeedback.selection()
                onReceiveLightning()
            }
            .accessibilityIdentifier("wallet-flow-receiveLightning")
        }
        .frame(maxWidth: .infinity)   // center the group on the leading-aligned canvas
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
            inputHint = "Couldn't create the request. Please try again."
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
