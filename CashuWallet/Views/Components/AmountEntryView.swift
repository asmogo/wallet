import SwiftUI

// MARK: - Amount Entry View
/// Full-screen amount entry matching cashu.me's SendTokenDialog/CreateInvoiceDialog
/// Features: Close button, title, unit toggle, mint selector, amount display, keyboard

struct AmountEntryView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Configuration
    let title: String
    let buttonLabel: String
    var showMintSelector: Bool = true
    var maxAmount: UInt64?
    var isLoading: Bool = false
    var onSubmit: ((UInt64) -> Void)?
    
    // State
    @State private var amountString: String = ""
    @State private var showMintPicker: Bool = false
    
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    
    // Computed
    private var amount: UInt64 {
        UInt64(amountString) ?? 0
    }
    
    private var insufficientFunds: Bool {
        guard let max = maxAmount else { return false }
        return amount > max
    }
    
    private var isButtonDisabled: Bool {
        amount == 0 || insufficientFunds || isLoading
    }
    
    var body: some View {
        ZStack {
            Color.cashuBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Mint selector
                if showMintSelector {
                    mintSelectorSection
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                
                // Amount display area
                Spacer()
                amountDisplaySection
                Spacer()
                
                // Keyboard panel
                keyboardSection
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            // Close button (floating left)
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundColor(.cashuMutedText)
            }
            
            Spacer()
            
            // Title
            Text(title)
                .font(.cashuDialogHeader)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Unit toggle button
            Button(action: { settings.useBitcoinSymbol.toggle() }) {
                Text(settings.unitLabel)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(settings.accentColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    // MARK: - Mint Selector Section
    
    private var mintSelectorSection: some View {
        Button(action: { showMintPicker = true }) {
            HStack(spacing: 12) {
                // Mint icon
                Circle()
                    .fill(Color.cashuCardBackground)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "building.columns")
                            .font(.system(size: 16))
                            .foregroundColor(.cashuMutedText)
                    )
                
                // Mint info
                VStack(alignment: .leading, spacing: 2) {
                    if let mint = walletManager.activeMint {
                        Text(mint.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        
                        if let maxAmount = maxAmount {
                            Text("\(settings.formatAmountShort(maxAmount)) \(settings.unitSuffix) available")
                                .font(.caption)
                                .foregroundColor(.cashuMutedText)
                        }
                    } else {
                        Text("Select Mint")
                            .font(.subheadline)
                            .foregroundColor(.cashuMutedText)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cashuCardBackground)
            )
        }
    }
    
    // MARK: - Amount Display Section
    
    private var amountDisplaySection: some View {
        VStack(spacing: 8) {
            // Main amount display
            Text(amountString.isEmpty ? "0" : amountString)
                .font(.system(size: 64, weight: .bold, design: .default))
                .foregroundColor(amountColor)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .animation(.spring(response: 0.3), value: amountString)
            
            // Unit label
            if !settings.useBitcoinSymbol {
                Text("sat")
                    .font(.title3)
                    .foregroundColor(.cashuMutedText)
            }
            
            // Warning message
            if insufficientFunds && amount > 0 {
                Text("Insufficient balance")
                    .font(.subheadline)
                    .foregroundColor(.cashuMutedText)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.2), value: insufficientFunds)
    }
    
    private var amountColor: Color {
        if insufficientFunds && amount > 0 {
            return .cashuMutedText
        }
        return settings.accentColor
    }
    
    // MARK: - Keyboard Section
    
    private var keyboardSection: some View {
        VStack(spacing: 0) {
            // Numeric keyboard
            NumericKeyboard(text: $amountString)
            .padding(.top, 16)
            .padding(.bottom, 16)
            
            // Action button
            Button(action: submitAction) {
                if isLoading {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text(buttonLabel)
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .buttonStyle(CashuPrimaryButtonStyle(isDisabled: isButtonDisabled))
            .disabled(isButtonDisabled)
            .padding(.horizontal, 20)
            .padding(.bottom, safeAreaBottom + 20)
        }
        .background(Color.cashuBackground)
    }
    
    private var safeAreaBottom: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.bottom ?? 0
    }
    
    // MARK: - Actions
    
    private func submitAction() {
        guard amount > 0, !insufficientFunds else { return }
        onSubmit?(amount)
    }
}

// MARK: - Mint Picker View

struct MintPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(walletManager.mints) { mint in
                            mintRow(mint)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Select Mint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
    
    private func mintRow(_ mint: MintInfo) -> some View {
        Button(action: {
            Task {
                try? await walletManager.setActiveMint(mint)
                dismiss()
            }
        }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.cashuCardBackground)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "building.columns")
                            .foregroundColor(settings.accentColor)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mint.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("\(mint.balance) sat")
                        .font(.caption)
                        .foregroundColor(.cashuMutedText)
                }
                
                Spacer()
                
                if walletManager.activeMint?.id == mint.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(settings.accentColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cashuCardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                walletManager.activeMint?.id == mint.id ? settings.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
        }
    }
}

// MARK: - Send Amount Entry View
/// Specialized amount entry for sending ecash

struct SendAmountEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    
    @State private var amount: UInt64 = 0
    @State private var isGenerating = false
    @State private var generatedToken: String?
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if let token = generatedToken {
                TokenDisplayView(
                    token: token,
                    amount: amount,
                    onDismiss: { dismiss() }
                )
            } else {
                AmountEntryView(
                    title: "Send Ecash",
                    buttonLabel: "Send",
                    showMintSelector: true,
                    maxAmount: walletManager.activeMint?.balance ?? 0,
                    isLoading: isGenerating,
                    onSubmit: generateToken
                )
                .environmentObject(walletManager)
            }
        }
    }
    
    private func generateToken(_ amount: UInt64) {
        self.amount = amount
        isGenerating = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                let token = try await walletManager.sendTokens(amount: amount, memo: nil)
                generatedToken = token.token
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}

// MARK: - Token Display View
/// Displays generated token with QR code

struct TokenDisplayView: View {
    let token: String
    let amount: UInt64
    var onDismiss: (() -> Void)?
    
    @State private var copied = false
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        ZStack {
            Color.cashuBackground
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                HStack {
                    Button(action: { onDismiss?() }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundColor(.cashuMutedText)
                    }
                    
                    Spacer()
                    
                    Text("Ecash Token")
                        .font(.cashuDialogHeader)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // Share button
                    ShareLink(item: token) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundColor(settings.accentColor)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
                
                // QR Code
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(width: 280, height: 280)
                    
                    QRCodeView(content: token)
                        .frame(width: 250, height: 250)
                }
                
                // Amount
                Text("\(settings.formatAmountShort(amount)) \(settings.unitSuffix)")
                    .font(.cashuBalanceSmall)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Copy button
                Button(action: copyToken) {
                    HStack {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy")
                    }
                }
                .buttonStyle(CashuPrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func copyToken() {
        UIPasteboard.general.string = token
        copied = true
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

// MARK: - Preview

#Preview("Amount Entry") {
    AmountEntryView(
        title: "Send Ecash",
        buttonLabel: "Send",
        maxAmount: 100000
    )
    .environmentObject(WalletManager())
}

#Preview("Token Display") {
    TokenDisplayView(
        token: "cashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbXSwibWludCI6Imh0dHBzOi8vbWludC5taW5pYml0cy5jYXNoIn1dfQ",
        amount: 21000
    )
}
