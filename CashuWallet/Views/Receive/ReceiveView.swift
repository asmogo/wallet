import SwiftUI

struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var selectedOption: ReceiveOption?
    
    enum ReceiveOption: String, Identifiable {
        case paste, scan, lightning, paymentRequest, p2pk
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    // Icon
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.cashuAccent)
                    
                    Text("Receive")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Choose how you want to receive")
                        .font(.subheadline)
                        .foregroundColor(.cashuMutedText)
                    
                    Spacer()
                    
                    // Options
                    VStack(spacing: 12) {
                        // Paste option
                        Button(action: { selectedOption = .paste }) {
                            receiveOptionRow(
                                icon: "doc.on.clipboard",
                                title: "Paste Ecash Token",
                                subtitle: "Paste a token from clipboard"
                            )
                        }
                        
                        // Scan option
                        Button(action: { selectedOption = .scan }) {
                            receiveOptionRow(
                                icon: "qrcode.viewfinder",
                                title: "Scan QR Code",
                                subtitle: "Scan token or invoice"
                            )
                        }
                        
                        // Lightning option
                        Button(action: { selectedOption = .lightning }) {
                            receiveOptionRow(
                                icon: "bolt.fill",
                                title: "Lightning Invoice",
                                subtitle: "Create invoice to receive sats"
                            )
                        }

                        if settings.enablePaymentRequests {
                            Button(action: { selectedOption = .paymentRequest }) {
                                receiveOptionRow(
                                    icon: "arrow.down.doc.fill",
                                    title: "Cashu Payment Request",
                                    subtitle: "Create a reusable ecash payment request"
                                )
                            }
                        }

                        if settings.showP2PKButtonInDrawer {
                            Button(action: openP2PKPublicKey) {
                                receiveOptionRow(
                                    icon: "lock.fill",
                                    title: "P2PK Public Key",
                                    subtitle: "Show a locking key QR for P2PK ecash"
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Cancel button
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .foregroundColor(.cashuMutedText)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $selectedOption) { option in
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
                case .paymentRequest:
                    PaymentRequestReceiveView()
                        .environmentObject(walletManager)
                case .p2pk:
                    ReceiveP2PKKeyView()
                        .environmentObject(walletManager)
                }
            }
        }
    }
    
    private func receiveOptionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.cashuAccent)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cashuCardBackground)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.cashuMutedText)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cashuCardBackground)
        )
    }
    
    private func handleScannedCode(_ code: String) {
        Task { @MainActor in
            if code.lowercased().hasPrefix("cashu") {
                do {
                    let _ = try await walletManager.receiveTokens(tokenString: code)
                    dismiss()
                } catch {
                    print("Error receiving token: \(error)")
                }
            }
        }
    }

    private func openP2PKPublicKey() {
        if settings.p2pkKeys.isEmpty && !settings.generateP2PKKey() {
            return
        }
        selectedOption = .p2pk
    }
}

struct ReceiveEcashView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var tokenInput = ""
    @State private var errorMessage: String?
    @State private var navigateToDetail = false
    @State private var validatedToken: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 48))
                        .foregroundColor(.cashuAccent)
                    
                    Text("Paste Token")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Token input
                    TextEditor(text: $tokenInput)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .frame(height: 120)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.cashuCardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.cashuBorder, lineWidth: 1)
                                )
                        )
                        .padding(.horizontal)
                    
                    // Paste from clipboard
                    Button(action: pasteFromClipboard) {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                            Text("Paste from Clipboard")
                        }
                    }
                    .buttonStyle(CashuSecondaryButtonStyle())
                    .padding(.horizontal)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.cashuError)
                    }
                    
                    Spacer()
                    
                    // Continue button - validates token and navigates to detail view
                    Button(action: validateAndContinue) {
                        Text("CONTINUE")
                    }
                    .buttonStyle(CashuPrimaryButtonStyle(isDisabled: tokenInput.isEmpty))
                    .disabled(tokenInput.isEmpty)
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Receive Ecash")
                        .font(.headline)
                        .foregroundColor(.white)
                }
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
                      clipboardContent.lowercased().hasPrefix("cashu") else { return }
                tokenInput = clipboardContent
            }
        }
    }
    
    private func pasteFromClipboard() {
        if let clipboardContent = UIPasteboard.general.string {
            tokenInput = clipboardContent
        }
    }
    
    private func validateAndContinue() {
        guard !tokenInput.isEmpty else { return }
        
        errorMessage = nil
        
        // Validate that it's a valid cashu token before navigating
        let trimmedToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic validation - check if it looks like a cashu token
        if trimmedToken.lowercased().hasPrefix("cashu") {
            validatedToken = trimmedToken
            navigateToDetail = true
        } else {
            errorMessage = "Invalid token format. Token should start with 'cashu'"
        }
    }
}

#Preview {
    ReceiveView()
        .environmentObject(WalletManager())
}

struct ReceiveP2PKKeyView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    @State private var activeQRContent: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    if let activeKey {
                        Spacer()

                        Image(systemName: "lock.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.cashuAccent)

                        Text("P2PK Public Key")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text(activeKey.used ? "This key has already been used. Generate a fresh key if you want a brand-new locking target." : "Share this public key to receive P2PK-locked ecash.")
                            .font(.subheadline)
                            .foregroundColor(activeKey.used ? .cashuWarning : .cashuMutedText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button(action: { activeQRContent = activeKey.publicKey }) {
                            QRCodeView(content: activeKey.publicKey, showControls: false)
                                .padding()
                                .frame(width: 260, height: 260)
                                .background(Color.white)
                                .cornerRadius(16)
                        }
                        .buttonStyle(.plain)

                        Text(activeKey.publicKey)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .padding(.horizontal)

                        if activeKey.usedCount > 0 {
                            Text("Used \(activeKey.usedCount) time\(activeKey.usedCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.cashuMutedText)
                        }

                        Spacer()

                        VStack(spacing: 12) {
                            Button(action: copyPublicKey) {
                                HStack {
                                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    Text(copied ? "Copied" : "Copy public key")
                                }
                            }
                            .buttonStyle(CashuPrimaryButtonStyle())

                            Button(action: generateNewKey) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Generate new key")
                                }
                            }
                            .buttonStyle(CashuSecondaryButtonStyle())
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                    } else {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                        Text("Preparing P2PK key...")
                            .foregroundColor(.cashuMutedText)
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("P2PK Key")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .sheet(isPresented: qrSheetIsPresented) {
                if let content = activeQRContent {
                    QRCodeDetailSheet(title: "P2PK Public Key", content: content)
                }
            }
            .onAppear {
                if activeKey == nil {
                    _ = settings.generateP2PKKey()
                }
            }
        }
    }

    private var activeKey: P2PKKey? {
        settings.p2pkKeys.last
    }

    private var qrSheetIsPresented: Binding<Bool> {
        Binding(
            get: { activeQRContent != nil },
            set: { isPresented in
                if !isPresented {
                    activeQRContent = nil
                }
            }
        )
    }

    private func copyPublicKey() {
        guard let publicKey = activeKey?.publicKey else { return }
        UIPasteboard.general.string = publicKey
        copied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private func generateNewKey() {
        guard settings.generateP2PKKey() else { return }
        copied = false
    }
}

struct PaymentRequestReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var paymentRequestService = PaymentRequestService.shared

    @State private var amountString = ""
    @State private var memo = ""
    @State private var isCreating = false
    @State private var claimingPaymentId: String?
    @State private var errorMessage: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 10) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.cashuAccent)

                            Text("Payment Request")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Text("Create a Cashu payment request that compatible wallets can pay over Nostr.")
                                .font(.subheadline)
                                .foregroundColor(.cashuMutedText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 12)

                        VStack(spacing: 12) {
                            TextField("Amount in sats (leave empty for any amount)", text: $amountString)
                                .keyboardType(.numberPad)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.cashuCardBackground)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.cashuBorder, lineWidth: 1)
                                        )
                                )

                            TextField("Memo (optional)", text: $memo)
                                .font(.body)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.cashuCardBackground)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.cashuBorder, lineWidth: 1)
                                        )
                                )

                            Button(action: createPaymentRequest) {
                                if isCreating {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text("CREATE REQUEST")
                                }
                            }
                            .buttonStyle(CashuPrimaryButtonStyle())
                            .disabled(isCreating)

                            if let activeMint = walletManager.activeMint {
                                Text("Restricting to mint: \(activeMint.name)")
                                    .font(.caption2)
                                    .foregroundColor(.cashuMutedText)
                            } else {
                                Text("No active mint selected. The request will allow any compatible mint.")
                                    .font(.caption2)
                                    .foregroundColor(.cashuWarning)
                            }
                        }

                        if let request = paymentRequestService.currentPaymentRequest {
                            VStack(spacing: 16) {
                                HStack {
                                    Text("Current Request")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    if paymentRequestService.ourPaymentRequests.count > 1 {
                                        Text("\(min(paymentRequestService.selectedRequestIndex + 1, paymentRequestService.ourPaymentRequests.count))/\(paymentRequestService.ourPaymentRequests.count)")
                                            .font(.caption)
                                            .foregroundColor(.cashuMutedText)
                                    }
                                }

                                QRCodeView(content: request.encoded, showControls: false)
                                    .padding()
                                    .frame(width: 260, height: 260)
                                    .background(Color.white)
                                    .cornerRadius(16)

                                Text(request.memo ?? "No memo")
                                    .font(.subheadline)
                                    .foregroundColor(.white)

                                Text(request.encoded)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.cashuMutedText)
                                    .lineLimit(3)
                                    .truncationMode(.middle)
                                    .padding(.horizontal)

                                HStack(spacing: 12) {
                                    Button(action: {
                                        paymentRequestService.selectPreviousRequest()
                                    }) {
                                        Label("Prev", systemImage: "chevron.left")
                                    }
                                    .buttonStyle(CashuSecondaryButtonStyle())
                                    .disabled(paymentRequestService.ourPaymentRequests.count <= 1)

                                    Button(action: copyCurrentRequest) {
                                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    }
                                    .buttonStyle(CashuPrimaryButtonStyle())

                                    Button(action: {
                                        paymentRequestService.selectNextRequest()
                                    }) {
                                        Label("Next", systemImage: "chevron.right")
                                    }
                                    .buttonStyle(CashuSecondaryButtonStyle())
                                    .disabled(paymentRequestService.ourPaymentRequests.count <= 1)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.cashuCardBackground)
                            )
                        }

                        if !paymentRequestService.incomingPayments.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Incoming Payments")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                ForEach(paymentRequestService.incomingPayments) { payment in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("\(payment.amount) \(payment.unit)")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text(payment.state == .claimed ? "Claimed" : "Pending")
                                                .font(.caption)
                                                .foregroundColor(payment.state == .claimed ? .cashuSuccess : .cashuWarning)
                                        }

                                        if let memo = payment.memo, !memo.isEmpty {
                                            Text(memo)
                                                .font(.caption)
                                                .foregroundColor(.cashuMutedText)
                                        }

                                        Text(payment.mintUrl)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.cashuMutedText)
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        if payment.state == .pending {
                                            Button(action: { claim(payment) }) {
                                                if claimingPaymentId == payment.id {
                                                    ProgressView()
                                                        .tint(.black)
                                                } else {
                                                    Text("CLAIM PAYMENT")
                                                }
                                            }
                                            .buttonStyle(CashuPrimaryButtonStyle())
                                            .disabled(claimingPaymentId == payment.id)
                                        }
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.cashuSecondaryBackground)
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.cashuError)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Payment Request")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func createPaymentRequest() {
        let amount = UInt64(amountString.trimmingCharacters(in: .whitespacesAndNewlines))
        isCreating = true
        errorMessage = nil

        do {
            _ = try paymentRequestService.createPaymentRequest(
                amount: amount,
                memo: memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : memo.trimmingCharacters(in: .whitespacesAndNewlines),
                mintUrl: walletManager.activeMint?.url
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreating = false
    }

    private func copyCurrentRequest() {
        guard let request = paymentRequestService.currentPaymentRequest else { return }
        UIPasteboard.general.string = request.encoded
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private func claim(_ payment: IncomingPaymentRequestPayment) {
        claimingPaymentId = payment.id
        errorMessage = nil

        Task {
            do {
                _ = try await paymentRequestService.claimIncomingPayment(payment)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                claimingPaymentId = nil
            }
        }
    }
}

struct PaymentRequestPayView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var paymentRequestService = PaymentRequestService.shared

    let initialEncodedRequest: String?
    let onComplete: (() -> Void)?

    @State private var requestInput: String
    @State private var decodedRequest: NUT18PaymentRequest?
    @State private var customAmount = ""
    @State private var isPaying = false
    @State private var errorMessage: String?

    init(initialEncodedRequest: String? = nil, onComplete: (() -> Void)? = nil) {
        self.initialEncodedRequest = initialEncodedRequest
        self.onComplete = onComplete
        _requestInput = State(initialValue: initialEncodedRequest ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if decodedRequest == nil {
                            VStack(spacing: 16) {
                                Image(systemName: "arrow.up.doc.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.cashuAccent)

                                Text("Pay Payment Request")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                TextEditor(text: $requestInput)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.white)
                                    .scrollContentBackground(.hidden)
                                    .frame(height: 160)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.cashuCardBackground)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.cashuBorder, lineWidth: 1)
                                            )
                                    )

                                Button(action: pasteFromClipboard) {
                                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                                }
                                .buttonStyle(CashuSecondaryButtonStyle())

                                Button(action: decodeRequest) {
                                    Text("CONTINUE")
                                }
                                .buttonStyle(CashuPrimaryButtonStyle(isDisabled: requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                                .disabled(requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else if let decodedRequest {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Review Request")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                paymentRequestDetailRow(label: "Description", value: decodedRequest.description() ?? "None")

                                if let amount = decodedRequest.amount()?.value {
                                    paymentRequestDetailRow(label: "Amount", value: "\(amount) sat")
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Amount")
                                            .font(.caption)
                                            .foregroundColor(.cashuMutedText)

                                        TextField("Enter amount in sats", text: $customAmount)
                                            .keyboardType(.numberPad)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.white)
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.cashuCardBackground)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color.cashuBorder, lineWidth: 1)
                                                    )
                                            )
                                    }
                                }

                                paymentRequestDetailRow(
                                    label: "Mint Restrictions",
                                    value: decodedRequest.mints()?.joined(separator: "\n") ?? "Any compatible mint"
                                )

                                paymentRequestDetailRow(
                                    label: "Transport",
                                    value: decodedRequest.transports().map { transport in
                                        "\(String(describing: transport.transportType)): \(transport.target)"
                                    }.joined(separator: "\n")
                                )

                                HStack(spacing: 12) {
                                    Button(action: resetRequest) {
                                        Text("Change")
                                    }
                                    .buttonStyle(CashuSecondaryButtonStyle())

                                    Button(action: payRequest) {
                                        if isPaying {
                                            ProgressView()
                                                .tint(.black)
                                        } else {
                                            Text("PAY REQUEST")
                                        }
                                    }
                                    .buttonStyle(CashuPrimaryButtonStyle(isDisabled: isPayDisabled))
                                    .disabled(isPayDisabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.cashuError)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Pay Request")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .onAppear {
                guard initialEncodedRequest != nil else { return }
                decodeRequest()
            }
        }
    }

    private var isPayDisabled: Bool {
        if isPaying || decodedRequest == nil {
            return true
        }
        if decodedRequest?.amount() == nil {
            return UInt64(customAmount.trimmingCharacters(in: .whitespacesAndNewlines)) == nil
        }
        return false
    }

    private func pasteFromClipboard() {
        guard let clipboard = UIPasteboard.general.string else { return }
        requestInput = clipboard
    }

    private func decodeRequest() {
        errorMessage = nil
        do {
            decodedRequest = try paymentRequestService.decode(requestInput.trimmingCharacters(in: .whitespacesAndNewlines))
            if let amount = decodedRequest?.amount()?.value {
                customAmount = "\(amount)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetRequest() {
        decodedRequest = nil
        customAmount = ""
        errorMessage = nil
    }

    private func payRequest() {
        let trimmedRequest = requestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = decodedRequest?.amount() == nil ? UInt64(customAmount.trimmingCharacters(in: .whitespacesAndNewlines)) : nil

        isPaying = true
        errorMessage = nil

        Task {
            do {
                try await paymentRequestService.payPaymentRequest(encoded: trimmedRequest, customAmount: amount)
                await MainActor.run {
                    isPaying = false
                    onComplete?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isPaying = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func paymentRequestDetailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.cashuMutedText)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cashuCardBackground)
        )
    }
}
