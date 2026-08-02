import SwiftUI
import UIKit

struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared

    @State private var selectedOption: ReceiveOption?
    @State private var lockedReceiveEncoded: String?

    enum ReceiveOption: String, Identifiable {
        case paste, scan, lightning, lockedKey
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: { selectedOption = .paste }) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paste Ecash Token")
                                Text("Paste a token from clipboard")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityLabel("Paste Ecash Token")
                    .accessibilityHint("Paste a cashu token from clipboard to receive ecash")
                    .accessibilityAddTraits(.isButton)

                    Button(action: { selectedOption = .scan }) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan QR Code")
                                Text("Scan a token, payment request, or address")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "viewfinder")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityLabel("Scan QR Code")
                    .accessibilityHint("Opens camera to scan a token or invoice QR code")
                    .accessibilityAddTraits(.isButton)

                    Button(action: { selectedOption = .lightning }) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Payment Request")
                                Text("Create an invoice, offer, or address")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityLabel("Payment Request")
                    .accessibilityHint("Creates a lightning invoice, BOLT12 offer, or bitcoin address to receive sats")
                    .accessibilityAddTraits(.isButton)

                    Button(action: { presentReceiveLockedKey() }) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Receive Locked Ecash")
                                Text("Receive ecash only you can claim")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "lock")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityLabel("Receive Locked Ecash")
                    .accessibilityHint("Shows a request so someone can send ecash only you can claim")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedOption) { option in
                Group {
                    switch option {
                    case .paste:
                        ReceiveEcashView()
                            .environmentObject(walletManager)
                    case .scan:
                        ScannerWrapperView()
                            .environmentObject(walletManager)
                    case .lightning:
                        ReceiveLightningView()
                            .environmentObject(walletManager)
                    case .lockedKey:
                        Group {
                            if let encoded = lockedReceiveEncoded {
                                QRCodeDetailSheet(title: "Receive Locked Ecash", content: encoded)
                            } else {
                                lockedKeyUnavailable
                            }
                        }
                        .presentationDetents([.medium, .large])
                    }
                }
                .canvasSheetBackground()
            }
        }
    }

    /// Builds a NUT-18 Cashu payment request locked to the wallet's primary
    /// (seed-derived) key, so anyone who pays it sends ecash only this wallet can
    /// claim. Routes the proofs back over Nostr.
    private func presentReceiveLockedKey() {
        HapticFeedback.selection()
        lockedReceiveEncoded = LockedReceiveRequest.build()
        selectedOption = .lockedKey
    }

    private var lockedKeyUnavailable: some View {
        let recoveryMessage = CashuRequestNostrReadiness.current().recoveryMessage
            ?? "Set up your primary key in Settings → Locked Ecash, then try again."
        return VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Couldn't create a request")
                .font(.headline)
            Text(recoveryMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

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

    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared

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

    /// The three destinations that leave the receive input, each keeping its own
    /// NavigationStack (bare) or wrapped in one (the request detail).
    private enum ReceiveRoute: Identifiable {
        case token(String)
        case request(CashuRequest)
        case requestFailure(String)
        case lightning
        var id: String {
            switch self {
            case .token(let token): return "token-\(token.prefix(48))"
            case .request(let request): return "request-\(request.id)"
            case .requestFailure: return "request-failure"
            case .lightning: return "lightning"
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
                }

                // A centered row of round Liquid Glass icon buttons — the primary
                // "ways to receive" (Scan · Ecash · Bitcoin), one-word label under each.
                receiveMethodRow
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
                route = .lightning
            }
            .accessibilityIdentifier("wallet-flow-receiveLightning")
        }
        .frame(maxWidth: .infinity)   // center the group on the leading-aligned canvas
    }

    // MARK: Routing out

    @ViewBuilder
    private func routeView(_ route: ReceiveRoute) -> some View {
        switch route {
        case .token(let token):
            ReceiveTokenDetailView(
                tokenString: token,
                onComplete: { self.route = nil; onClose() }
            )
            .environmentObject(walletManager)
        case .request(let request):
            // CashuRequestDetailView renders its chrome via `.toolbar`, so it
            // needs an enclosing NavigationStack (unlike the two self-contained
            // detail views above).
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
        case .lightning:
            ReceiveLightningView()
                .environmentObject(walletManager)
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

    /// A bearer token redeems here; anything else payable is a Send, handed back
    /// to the Send flow. Inverts `UnifiedSendView.advance`'s token special-case.
    private func autoRoute(_ trimmed: String) {
        guard !trimmed.isEmpty, route == nil else { return }
        if let token = TokenParser.normalizedToken(from: trimmed) {
            HapticFeedback.selection()
            route = .token(token)
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
    /// intermediate form (past requests live in History). Reuses the same
    /// builder + store as the legacy `ReceiveEcashView.createNewRequest`.
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

struct ReceiveEcashView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared

    var sheetDetent: Binding<PresentationDetent>? = nil

    @State private var tokenInput = ""
    @State private var errorMessage: String?
    @State private var navigateToDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var validatedToken: String?
    @State private var currentRequest: CashuRequest?
    @State private var requestCreationFailure: String?
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let failure = requestCreationFailure {
                    requestCreationFailureView(failure)
                        .transition(.opacity)
                } else if let request = currentRequest {
                    CashuRequestDetailView(request: request, onClose: { dismiss() })
                        .environmentObject(walletManager)
                        .transition(.opacity)
                } else {
                    formContent
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: currentRequest?.id)
            .animation(.easeInOut(duration: 0.25), value: requestCreationFailure != nil)
        }
    }

    private func requestCreationFailureView(_ message: String) -> some View {
        PaymentStatusView(
            details: [],
            phase: .failure(message: message),
            failureTitle: "Couldn't Create Request",
            onDone: { requestCreationFailure = nil },
            onRetry: { requestCreationFailure = nil }
        )
        .navigationTitle("Receive Ecash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                SheetCloseButton()
            }
        }
    }

    @ViewBuilder
    private var formContent: some View {
        VStack(spacing: 16) {
                GeometryReader { geo in
                    ZStack(alignment: .bottomTrailing) {
                        ZStack(alignment: .topLeading) {
                            // TokenTextEditor (not TextEditor): cashuA base64url uses
                            // "-" which word-wrap treats as a break, leaving short
                            // jagged lines. Android fills each line edge-to-edge.
                            TokenTextEditor(text: $tokenInput)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .accessibilityLabel("Ecash token input")
                                .accessibilityHint("Enter or paste a cashu ecash token")

                            if tokenInput.isEmpty {
                                Text("cashuB…")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 17)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }
                        // Longer/stronger fade matching Android ReceiveEcashScreen:
                        // opaque through ~35%, then dissolve so the clear control
                        // sits on solid fill.
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.35),
                                    .init(color: .black.opacity(0.65), location: 0.55),
                                    .init(color: .black.opacity(0.15), location: 0.75),
                                    .init(color: .clear, location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Smart corner icon: paste when empty, clear when full.
                        // Plain SF Symbol (no circle bg) so we don't stack a
                        // gray dot on the gray text field. Sits outside the fade
                        // mask so it stays fully opaque over dissolving text.
                        Button(action: tokenInput.isEmpty ? pasteFromClipboard : clearInput) {
                            Image(systemName: tokenInput.isEmpty ? "doc.on.clipboard" : "xmark.circle.fill")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tokenInput.isEmpty ? "Paste from clipboard" : "Clear")
                    }
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    // ~15% shorter than the flexible remainder the VStack offers.
                    .frame(width: geo.size.width, height: geo.size.height * 0.85)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal)
                .padding(.top, 12)

                if let error = errorMessage {
                    InlineNotice(message: error, severity: .error)
                        .padding(.horizontal)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale))
                }

                VStack(spacing: 10) {
                    Button(action: validateAndContinue) {
                        Text("Continue")
                    }
                    // Prominent when a token is present (enabled); dimmed fill
                    // while empty — matches Android PrimaryButton inverted ink.
                    .glassButton(prominent: true)
                    .disabled(tokenInput.isEmpty)
                    .accessibilityHint("Validates the token and proceeds to details")

                    Button(action: createNewRequest) {
                        Text("New Request")
                    }
                    .glassButton()
                    .accessibilityHint("Generate a Cashu Request to receive ecash")
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .animation(.easeInOut(duration: 0.2), value: errorMessage)
            .navigationTitle("Receive Ecash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticFeedback.selection()
                        showingScanner = true
                    } label: {
                        Image(systemName: "viewfinder")
                            .font(.body.weight(.semibold))
                            .toolbarIconTapTarget()
                    }
                    .accessibilityLabel("Scan QR Code")
                    .accessibilityHint("Opens the camera to scan an ecash token")
                }
            }
            .sheet(isPresented: $showingScanner) {
                ScannerWrapperView(onScanned: handleScannedToken)
                    .environmentObject(walletManager)
                    .canvasSheetBackground()
            }
            .navigationDestination(isPresented: $navigateToDetail) {
                if let token = validatedToken {
                    ReceiveTokenDetailView(tokenString: token, onComplete: {
                        dismiss()
                    })
                    .environmentObject(walletManager)
                    .navigationBarBackButtonHidden(true)
                }
            }
            .onAppear {
                guard settings.autoPasteEcashReceive else { return }
                guard tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                guard let clipboardContent = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                      TokenParser.isCashuToken(clipboardContent) else { return }
                tokenInput = clipboardContent
            }
    }

    private func pasteFromClipboard() {
        if let clipboardContent = UIPasteboard.general.string {
            HapticFeedback.selection()
            tokenInput = clipboardContent
        }
    }

    private func clearInput() {
        HapticFeedback.selection()
        tokenInput = ""
        errorMessage = nil
    }

    private func createNewRequest() {
        HapticFeedback.selection()
        requestCreationFailure = nil
        let readiness = CashuRequestNostrReadiness.current()
        guard let configuration = readiness.requestConfiguration else {
            errorMessage = readiness.recoveryMessage
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
            sheetDetent?.wrappedValue = .large
            currentRequest = request
        } catch {
            AppLogger.ui.error("createNewRequest failed: \(String(describing: error), privacy: .public)")
            requestCreationFailure = error.userFacingWalletMessage
        }
    }

    private func handleScannedToken(_ scanned: String) {
        tokenInput = scanned
        validateAndContinue()
    }

    private func validateAndContinue() {
        guard !tokenInput.isEmpty else { return }

        errorMessage = nil

        let trimmedToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if let token = TokenParser.normalizedToken(from: trimmedToken) {
            validatedToken = token
            navigateToDetail = true
        } else {
            errorMessage = "Invalid token format. Token should start with 'cashu'"
        }
    }
}

/// Monospaced token paste field. `TextEditor` word-wraps at ASCII `-`
/// (common in cashuA base64url), which fragments the token into short lines.
/// Android fills each line edge-to-edge; we match that by displaying `-` as
/// non-breaking hyphens while keeping ASCII `-` in the bound string.
private struct TokenTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byCharWrapping
        textView.adjustsFontForContentSizeCategory = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.keyboardType = .asciiCapable
        textView.tintColor = .label
        textView.typingAttributes = Self.typingAttributes()
        textView.attributedText = Self.displayString(for: text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.typingAttributes = Self.typingAttributes()
        textView.textContainer.lineBreakMode = .byCharWrapping
        let display = Self.displayString(for: text)
        if textView.attributedText?.string != display.string {
            let selected = textView.selectedRange
            textView.attributedText = display
            let maxLength = (textView.text as NSString).length
            if NSMaxRange(selected) <= maxLength {
                textView.selectedRange = selected
            }
        }
    }

    /// U+2011 NON-BREAKING HYPHEN — same glyph as `-`, not a line-break opportunity.
    private static let nonBreakingHyphen = "\u{2011}"

    private static func monoBodyFont() -> UIFont {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let mono = UIFont.monospacedSystemFont(ofSize: body.pointSize, weight: .regular)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: mono)
    }

    private static func typingAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.hyphenationFactor = 0
        return [
            .font: monoBodyFont(),
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ]
    }

    private static func displayString(for raw: String) -> NSAttributedString {
        let display = raw.replacingOccurrences(of: "-", with: nonBreakingHyphen)
        return NSAttributedString(string: display, attributes: typingAttributes())
    }

    private static func storageString(from display: String) -> String {
        display.replacingOccurrences(of: nonBreakingHyphen, with: "-")
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TokenTextEditor

        init(_ parent: TokenTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let display = textView.text ?? ""
            let storage = TokenTextEditor.storageString(from: display)
            if parent.text != storage {
                parent.text = storage
            }
            // Keep typed ASCII hyphens non-breaking without fighting the cursor.
            let normalized = display.replacingOccurrences(of: "-", with: TokenTextEditor.nonBreakingHyphen)
            if display != normalized {
                let selected = textView.selectedRange
                textView.attributedText = TokenTextEditor.displayString(
                    for: TokenTextEditor.storageString(from: normalized)
                )
                textView.typingAttributes = TokenTextEditor.typingAttributes()
                let maxLength = (textView.text as NSString).length
                if NSMaxRange(selected) <= maxLength {
                    textView.selectedRange = selected
                }
            }
        }
    }
}

#Preview {
    ReceiveView()
        .environmentObject(WalletManager())
}
