import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var priceService = PriceService.shared
    @ObservedObject var npcService = NPCService.shared
    @ObservedObject var nostrService = NostrService.shared
    
    @State private var showBackup = false
    @State private var showDeleteConfirm = false
    @State private var copiedLightningAddress = false
    @State private var isCheckingPayments = false
    @State private var showMintPicker = false
    
    // Nostr Key Management
    @State private var showNsec = false
    @State private var copiedNsec = false
    @State private var showImportNsec = false
    @State private var importNsecText = ""
    @State private var showGenerateKeyConfirm = false
    @State private var showResetKeyConfirm = false
    @State private var nostrKeyError: String?
    @State private var relayInput = ""
    @State private var relayError: String?
    @State private var copiedRelay: String?
    @State private var showRestoreFlowAlert = false
    @State private var p2pkImportText = ""
    @State private var showImportP2PK = false
    @State private var p2pkError: String?
    @State private var nwcError: String?
    @State private var expandedP2PKKeys = false
    @State private var activeQRPayload: QRPayload?
    @State private var copiedNWCConnectionId: UUID?
    @State private var copiedP2PKPublicKey: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        sectionHeader("BACKUP & RESTORE")
                        backupRestoreSection

                        sectionHeader("LIGHTNING ADDRESS")
                        npcSection

                        sectionHeader("NOSTR")
                        nostrKeysSection
                        nostrRelaysSection

                        sectionHeader("PAYMENT REQUESTS")
                        paymentRequestsSection

                        sectionHeader("NOSTR WALLET CONNECT")
                        nwcSection

                        sectionHeader("P2PK FEATURES")
                        p2pkSection

                        sectionHeader("PRIVACY")
                        privacySection

                        sectionHeader("APPEARANCE")
                        appearanceSection

                        sectionHeader("WALLET INFO")
                        infoRow(label: "Balance", value: settings.formatAmount(walletManager.balance))
                        infoRow(label: "Mints", value: "\(walletManager.mints.count)")
                        infoRow(label: "Unit", value: settings.unitLabel)
                        infoRow(label: "Version", value: "1.0.0")

                        sectionHeader("ABOUT")
                        linkRow(
                            icon: "globe",
                            title: "Learn about Cashu",
                            subtitle: "cashu.space",
                            url: "https://cashu.space"
                        )
                        linkRow(
                            icon: "doc.text",
                            title: "Protocol Specs (NUTs)",
                            subtitle: "github.com/cashubtc/nuts",
                            url: "https://github.com/cashubtc/nuts"
                        )

                        sectionHeader("ADVANCED")
                        Button(action: { showDeleteConfirm = true }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Wallet")
                            }
                            .foregroundColor(.cashuError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showBackup) {
                BackupView()
                    .environmentObject(walletManager)
            }
            .sheet(isPresented: $showImportP2PK) {
                ImportP2PKSheet(
                    nsecText: $p2pkImportText,
                    onImport: importP2PKNsec
                )
            }
            .sheet(item: $activeQRPayload) { payload in
                QRCodeDetailSheet(title: payload.title, content: payload.content)
            }
            .alert("Open Restore Wizard", isPresented: $showRestoreFlowAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open") {
                    walletManager.needsOnboarding = true
                }
            } message: {
                Text("This will open the restore flow used during onboarding.")
            }
            .alert("Delete Wallet", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteWallet()
                }
            } message: {
                Text("Are you sure you want to delete your wallet? This action cannot be undone. Make sure you have backed up your seed phrase!")
            }
        }
    }

    private var backupRestoreSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingButton(
                icon: "key.fill",
                title: "Backup seed phrase",
                subtitle: "Your seed phrase can restore your wallet. Keep it safe and private."
            ) {
                showBackup = true
            }
            settingButton(
                icon: "arrow.counterclockwise.circle.fill",
                title: "Restore ecash",
                subtitle: "Open the restore wizard to recover ecash from another mnemonic seed phrase."
            ) {
                showRestoreFlowAlert = true
            }
        }
        .padding(.vertical, 8)
    }

    private var paymentRequestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payment requests")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)

            Text("Payment requests allow you to receive payments via Nostr relays.")
                .font(.caption)
                .foregroundColor(.cashuMutedText)

            Toggle(isOn: $settings.enablePaymentRequests.animation(.easeInOut(duration: 0.2))) {
                Text("Enable Payment Requests")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

            if settings.enablePaymentRequests {
                Toggle(isOn: $settings.receivePaymentRequestsAutomatically.animation(.easeInOut(duration: 0.2))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claim automatically")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Text("Receive incoming payments automatically.")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
            }
        }
        .padding(.vertical, 8)
    }

    private var nwcSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nostr Wallet Connect (NWC)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)

            Text("Use NWC to control your wallet from compatible applications.")
                .font(.caption)
                .foregroundColor(.cashuMutedText)

            Toggle(isOn: $settings.enableNWC.animation(.easeInOut(duration: 0.2))) {
                Text("Enable NWC")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

            if settings.enableNWC {
                Text("You can only use NWC for payments from your Bitcoin balance on your active mint.")
                    .font(.caption2)
                    .foregroundColor(.cashuMutedText)

                Button(action: createNWCConnection) {
                    HStack(spacing: 8) {
                        Image(systemName: "link.badge.plus")
                        Text(settings.nwcConnections.isEmpty ? "Create connection" : "Ensure connection")
                    }
                    .font(.subheadline)
                    .foregroundColor(settings.accentColor)
                }

                ForEach(settings.nwcConnections) { connection in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Connection")
                                .font(.caption)
                                .foregroundColor(.cashuMutedText)

                            Spacer()

                            Button(action: { copyNWCConnection(connection) }) {
                                Image(systemName: copiedNWCConnectionId == connection.id ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedNWCConnectionId == connection.id ? .green : settings.accentColor)
                            }
                            .accessibilityLabel("Copy connection string")

                            Button(action: { showQRCode(title: "NWC Connection", content: settings.nwcConnectionString(for: connection)) }) {
                                Image(systemName: "qrcode")
                                    .foregroundColor(settings.accentColor)
                            }
                            .accessibilityLabel("Show connection QR")

                            Button(action: { settings.removeNWCConnection(connection) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.cashuError)
                            }
                            .accessibilityLabel("Remove connection")
                        }

                        Text(settings.nwcConnectionString(for: connection))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack {
                            Text("Allowance left (sat)")
                                .font(.caption2)
                                .foregroundColor(.cashuMutedText)
                            Spacer()
                            TextField("0", text: allowanceBinding(for: connection))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: 100)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.cashuCardBackground)
                    )
                }

                if let nwcError {
                    Text(nwcError)
                        .font(.caption2)
                        .foregroundColor(.cashuError)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var p2pkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P2PK")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)

            Text("Generate a key pair to receive P2PK-locked ecash. Use only small amounts while this remains experimental.")
                .font(.caption)
                .foregroundColor(.cashuMutedText)

            HStack(spacing: 12) {
                Button(action: generateP2PKKey) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Generate key")
                    }
                    .font(.subheadline)
                    .foregroundColor(settings.accentColor)
                }

                Button(action: {
                    p2pkError = nil
                    showImportP2PK = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import nsec")
                    }
                    .font(.subheadline)
                    .foregroundColor(settings.accentColor)
                }
            }

            Toggle(isOn: $settings.showP2PKButtonInDrawer.animation(.easeInOut(duration: 0.2))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick access to lock")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("Show your P2PK locking key in the Receive ecash menu.")
                        .font(.caption)
                        .foregroundColor(.cashuMutedText)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

            if !settings.p2pkKeys.isEmpty {
                DisclosureGroup(
                    isExpanded: $expandedP2PKKeys.animation(.easeInOut(duration: 0.2)),
                    content: {
                        VStack(spacing: 8) {
                            ForEach(settings.p2pkKeys) { key in
                                HStack(spacing: 10) {
                                    Button(action: { copyP2PKPublicKey(key.publicKey) }) {
                                        Image(systemName: copiedP2PKPublicKey == key.publicKey ? "checkmark" : "doc.on.doc")
                                            .foregroundColor(copiedP2PKPublicKey == key.publicKey ? .green : settings.accentColor)
                                    }

                                    Text(key.publicKey)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    if key.used {
                                        Text("used")
                                            .font(.caption2)
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule()
                                                    .fill(settings.accentColor)
                                            )
                                    }

                                    Spacer()

                                    Button(action: { showQRCode(title: "P2PK Public Key", content: key.publicKey) }) {
                                        Image(systemName: "qrcode")
                                            .foregroundColor(settings.accentColor)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.cashuSecondaryBackground)
                                )
                            }
                        }
                        .padding(.top, 8)
                    },
                    label: {
                        Text("Browse \(settings.p2pkKeys.count) keys")
                            .font(.caption)
                            .foregroundColor(settings.accentColor)
                    }
                )
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.cashuCardBackground)
                )
            }

            if let p2pkError {
                Text(p2pkError)
                    .font(.caption2)
                    .foregroundColor(.cashuError)
            }
        }
        .padding(.vertical, 8)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Text("These settings affect your privacy and wallet responsiveness.")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)

                Toggle(isOn: $settings.checkIncomingInvoices) {
                    Text("Check incoming invoice")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

                Toggle(isOn: $settings.checkPendingOnStartup) {
                    Text("Check pending invoices on startup")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

                Toggle(isOn: $settings.periodicallyCheckIncomingInvoices) {
                    Text("Check all invoices")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
                .disabled(!settings.checkIncomingInvoices)
                .opacity(settings.checkIncomingInvoices ? 1.0 : 0.5)

                Toggle(isOn: $settings.checkSentTokens) {
                    Text("Check sent ecash")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

                Toggle(isOn: $settings.useWebsockets) {
                    Text("Use WebSockets")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
                .disabled(!settings.checkIncomingInvoices && !settings.checkSentTokens)
                .opacity((settings.checkIncomingInvoices || settings.checkSentTokens) ? 1 : 0.5)

                Toggle(isOn: $settings.autoPasteEcashReceive) {
                    Text("Paste ecash automatically")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $settings.showFiatBalance) {
                    Text("Get exchange rate from Coinbase")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

                if settings.showFiatBalance {
                    HStack {
                        Text("Fiat Currency")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                        Spacer()
                        Picker("Currency", selection: $settings.bitcoinPriceCurrency) {
                            ForEach(SettingsManager.supportedFiatCurrencies, id: \.self) { currency in
                                Text(currency).tag(currency)
                            }
                        }
                        .labelsHidden()
                        .tint(settings.accentColor)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BTC Price (\(settings.bitcoinPriceCurrency))")
                                .font(.caption)
                                .foregroundColor(.cashuMutedText)

                            if priceService.btcPriceUSD > 0 {
                                Text(formatBTCPrice(priceService.btcPriceUSD))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            } else {
                                Text("Loading...")
                                    .font(.subheadline)
                                    .foregroundColor(.cashuMutedText)
                            }
                        }

                        Spacer()

                        Button(action: {
                            Task { await priceService.fetchPrice() }
                        }) {
                            if priceService.isFetching {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(settings.accentColor)
                            }
                        }
                        .disabled(priceService.isFetching)
                    }

                    if let lastUpdated = priceService.lastUpdated {
                        Text("Updated \(formatRelativeTime(lastUpdated))")
                            .font(.caption2)
                            .foregroundColor(.cashuMutedText)
                    }

                    if let error = priceService.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.cashuError)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("On-screen keyboard")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Text("Use the numeric keyboard for entering amounts.")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)

                Toggle(isOn: $settings.useNumericKeyboard) {
                    Text("Use numeric keyboard")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Bitcoin symbol")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Text("Use ₿ symbol instead of sats.")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)

                Toggle(isOn: $settings.useBitcoinSymbol) {
                    Text("Use ₿ symbol")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Text("Change how your wallet looks.")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                    ForEach(Array(SettingsManager.themeColors.enumerated()), id: \.element.id) { index, theme in
                        themeColorButton(theme: theme, index: index)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - NPC Section
    
    private var npcSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enable/Disable toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("npub.cash Integration")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text("Receive Lightning payments to your wallet using a Lightning address.")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)
                
                Toggle(isOn: $npcService.isEnabled) {
                    Text("Enable Lightning Address")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
                .padding(.top, 8)
            }
            
            if npcService.isEnabled {
                // Lightning Address Display
                if npcService.isInitialized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Lightning Address")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                        
                        // Copyable Lightning address
                        Button(action: copyLightningAddress) {
                            HStack {
                                Text(npcService.lightningAddress)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(settings.accentColor)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
                                Image(systemName: copiedLightningAddress ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedLightningAddress ? .green : settings.accentColor)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.cashuCardBackground)
                            )
                        }
                    }
                    .padding(.top, 8)
                    
                    // Auto-claim toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $npcService.automaticClaim) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-claim payments")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Text("Automatically mint received payments")
                                    .font(.caption)
                                    .foregroundColor(.cashuMutedText)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
                    }
                    .padding(.top, 8)
                    
                    // Mint selection
                    if !walletManager.mints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Receiving Mint")
                                .font(.caption)
                                .foregroundColor(.cashuMutedText)
                            
                            Button(action: { showMintPicker = true }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selectedMintName())
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Text(npcService.selectedMintUrl ?? "Select a mint")
                                            .font(.caption)
                                            .foregroundColor(.cashuMutedText)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.cashuMutedText)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.cashuCardBackground)
                                )
                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    // Manual check button
                    HStack {
                        Button(action: checkForPayments) {
                            HStack {
                                if isCheckingPayments {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Check for Payments")
                            }
                            .font(.subheadline)
                            .foregroundColor(settings.accentColor)
                        }
                        .disabled(isCheckingPayments)
                        
                        Spacer()
                        
                        if let lastCheck = npcService.lastCheck {
                            Text("Last: \(formatRelativeTime(lastCheck))")
                                .font(.caption2)
                                .foregroundColor(.cashuMutedText)
                        }
                    }
                    .padding(.top, 12)
                    
                    // Connection status
                    HStack {
                        Circle()
                            .fill(npcService.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        
                        Text(npcService.isConnected ? "Connected to npubx.cash" : "Connecting...")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                    }
                    .padding(.top, 8)
                    
                    // Error message
                    if let error = npcService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.cashuError)
                            .padding(.top, 4)
                    }
                } else {
                    // Nostr not initialized
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.cashuWarning)
                        Text("Wallet not fully initialized. Please restart the app.")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showMintPicker) {
            MintPickerSheet(
                mints: walletManager.mints,
                selectedMintUrl: $npcService.selectedMintUrl,
                onSelect: { mintUrl in
                    Task {
                        try? await npcService.changeMint(to: mintUrl)
                    }
                }
            )
        }
    }
    
    // MARK: - Nostr Keys Section
    
    private var nostrKeysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Explanation
            Text("Nostr Key Source")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Text("Your Lightning address is derived from your Nostr public key. Choose which key to use.")
                .font(.caption)
                .foregroundColor(.cashuMutedText)
            
            // Signer type selection
            VStack(spacing: 8) {
                ForEach(NostrSignerType.allCases, id: \.self) { type in
                    signerTypeRow(type)
                }
            }
            .padding(.top, 8)
            
            // Current key info
            if nostrService.isInitialized {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Public Key")
                        .font(.caption)
                        .foregroundColor(.cashuMutedText)
                        .padding(.top, 12)
                    
                    // npub display
                    Text(nostrService.npub)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.cashuCardBackground)
                        )
                }
                
                // nsec reveal/copy (only show for current key)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Private Key (nsec)")
                        .font(.caption)
                        .foregroundColor(.cashuMutedText)
                        .padding(.top, 8)
                    
                    HStack {
                        if showNsec {
                            Text(nostrService.nsec)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.cashuWarning)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(String(repeating: "*", count: 20))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.cashuMutedText)
                        }
                        
                        Spacer()
                        
                        // Reveal toggle
                        Button(action: { showNsec.toggle() }) {
                            Image(systemName: showNsec ? "eye.slash" : "eye")
                                .foregroundColor(settings.accentColor)
                        }
                        
                        // Copy button
                        Button(action: copyNsec) {
                            Image(systemName: copiedNsec ? "checkmark" : "doc.on.doc")
                                .foregroundColor(copiedNsec ? .green : settings.accentColor)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.cashuCardBackground)
                    )
                    
                    Text("Keep your private key secret. Anyone with it can control your Lightning address.")
                        .font(.caption2)
                        .foregroundColor(.cashuWarning)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                // Generate new key
                Button(action: { showGenerateKeyConfirm = true }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Generate")
                    }
                    .font(.subheadline)
                    .foregroundColor(settings.accentColor)
                }
                
                Spacer()
                
                // Import nsec
                Button(action: { showImportNsec = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                    .font(.subheadline)
                    .foregroundColor(settings.accentColor)
                }
                
                Spacer()
                
                // Reset to seed (only if using custom key)
                if nostrService.signerType == .privateKey {
                    Button(action: { showResetKeyConfirm = true }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .font(.subheadline)
                        .foregroundColor(.cashuWarning)
                    }
                }
            }
            .padding(.top, 12)
            
            // Error message
            if let error = nostrKeyError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuError)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .alert("Generate New Key", isPresented: $showGenerateKeyConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Generate", role: .destructive) {
                generateNewKey()
            }
        } message: {
            Text("This will create a new random Nostr key. Your Lightning address will change. The old key will be replaced.")
        }
        .alert("Reset to Wallet Seed", isPresented: $showResetKeyConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetToSeedKey()
            }
        } message: {
            Text("This will switch back to the Nostr key derived from your wallet seed. Your custom key will be deleted.")
        }
        .sheet(isPresented: $showImportNsec) {
            ImportNsecSheet(
                nsecText: $importNsecText,
                onImport: importNsec
            )
        }
    }

    private var nostrRelaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Relay servers")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)

            Text("Manage your Nostr relay list for compatible features like npub.cash and backups.")
                .font(.caption)
                .foregroundColor(.cashuMutedText)

            HStack(spacing: 12) {
                TextField("wss://relay.example.com", text: $relayInput)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.cashuCardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.cashuBorder, lineWidth: 1)
                            )
                    )

                Button(action: addRelay) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(relayInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .cashuMutedText : settings.accentColor)
                }
                .disabled(relayInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add relay")
            }

            ForEach(settings.nostrRelays, id: \.self) { relay in
                HStack(spacing: 12) {
                    Text(relay)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button(action: { copyRelay(relay) }) {
                        Image(systemName: copiedRelay == relay ? "checkmark" : "doc.on.doc")
                            .foregroundColor(copiedRelay == relay ? .green : settings.accentColor)
                    }
                    .accessibilityLabel("Copy relay URL")

                    Button(action: { settings.removeNostrRelay(relay) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.cashuError)
                    }
                    .accessibilityLabel("Remove relay")
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.cashuCardBackground)
                )
            }

            if let relayError {
                Text(relayError)
                    .font(.caption2)
                    .foregroundColor(.cashuError)
            }

            Button(action: {
                settings.resetNostrRelaysToDefault()
                relayError = nil
            }) {
                Text("Reset default relays")
                    .font(.caption)
                    .foregroundColor(settings.accentColor)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }
    
    private func signerTypeRow(_ type: NostrSignerType) -> some View {
        Button(action: {
            switchSignerType(to: type)
        }) {
            HStack {
                // Radio button
                Image(systemName: nostrService.signerType == type ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(nostrService.signerType == type ? settings.accentColor : .cashuMutedText)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text(type.description)
                        .font(.caption)
                        .foregroundColor(.cashuMutedText)
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.cashuCardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(nostrService.signerType == type ? settings.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
    }
    
    // MARK: - Nostr Key Actions
    
    private func copyNsec() {
        UIPasteboard.general.string = nostrService.getNsec()
        copiedNsec = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedNsec = false
        }
    }
    
    private func generateNewKey() {
        nostrKeyError = nil
        do {
            try nostrService.generateRandomKeypair()
        } catch {
            nostrKeyError = error.localizedDescription
        }
    }
    
    private func importNsec() {
        nostrKeyError = nil
        let nsec = importNsecText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nsec.isEmpty else {
            nostrKeyError = "Please enter an nsec"
            return
        }
        
        do {
            try nostrService.importNsec(nsec)
            importNsecText = ""
            showImportNsec = false
        } catch {
            nostrKeyError = error.localizedDescription
        }
    }
    
    private func resetToSeedKey() {
        nostrKeyError = nil
        do {
            try nostrService.resetToSeedKey()
        } catch {
            nostrKeyError = error.localizedDescription
        }
    }
    
    private func switchSignerType(to type: NostrSignerType) {
        guard nostrService.signerType != type else { return }
        
        nostrKeyError = nil
        
        // If switching to custom key and no custom key exists, show generate/import options
        if type == .privateKey && !nostrService.hasCustomPrivateKey() {
            showGenerateKeyConfirm = true
            return
        }
        
        do {
            try nostrService.switchSignerType(to: type)
        } catch {
            nostrKeyError = error.localizedDescription
        }
    }

    private func addRelay() {
        relayError = nil
        let trimmed = relayInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lowercased = trimmed.lowercased()
        guard lowercased.hasPrefix("wss://") || lowercased.hasPrefix("ws://") else {
            relayError = "Relay URL must start with ws:// or wss://"
            return
        }
        guard settings.addNostrRelay(trimmed) else {
            relayError = "Relay already added"
            return
        }
        relayInput = ""
    }

    private func copyRelay(_ relay: String) {
        UIPasteboard.general.string = relay
        copiedRelay = relay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedRelay == relay {
                copiedRelay = nil
            }
        }
    }

    private func createNWCConnection() {
        nwcError = nil
        guard settings.generateNWCConnection() != nil else {
            nwcError = "Unable to create an NWC connection."
            return
        }
    }

    private func copyNWCConnection(_ connection: NWCConnection) {
        UIPasteboard.general.string = settings.nwcConnectionString(for: connection)
        copiedNWCConnectionId = connection.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedNWCConnectionId == connection.id {
                copiedNWCConnectionId = nil
            }
        }
    }

    private func allowanceBinding(for connection: NWCConnection) -> Binding<String> {
        Binding(
            get: { String(connection.allowanceLeft) },
            set: { newValue in
                let digits = newValue.filter { $0.isNumber }
                let amount = Int(digits) ?? 0
                settings.updateNWCAllowance(connectionId: connection.id, allowanceLeft: amount)
            }
        )
    }

    private func generateP2PKKey() {
        p2pkError = nil
        guard settings.generateP2PKKey() else {
            p2pkError = "Failed to generate P2PK key."
            return
        }
    }

    private func importP2PKNsec() {
        p2pkError = nil
        do {
            try settings.importP2PKNsec(p2pkImportText)
            p2pkImportText = ""
            showImportP2PK = false
        } catch {
            p2pkError = error.localizedDescription
        }
    }

    private func copyP2PKPublicKey(_ publicKey: String) {
        UIPasteboard.general.string = publicKey
        copiedP2PKPublicKey = publicKey
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedP2PKPublicKey == publicKey {
                copiedP2PKPublicKey = nil
            }
        }
    }

    private func showQRCode(title: String, content: String) {
        activeQRPayload = QRPayload(title: title, content: content)
    }
    
    // MARK: - NPC Helpers
    
    private func copyLightningAddress() {
        let address = npcService.lightningAddress
        UIPasteboard.general.string = address
        copiedLightningAddress = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedLightningAddress = false
        }
    }
    
    private func checkForPayments() {
        isCheckingPayments = true
        Task {
            await npcService.checkAndClaimPayments()
            await MainActor.run {
                isCheckingPayments = false
            }
        }
    }
    
    private func selectedMintName() -> String {
        if let selectedUrl = npcService.selectedMintUrl,
           let mint = walletManager.mints.first(where: { $0.url == selectedUrl }) {
            return mint.name
        }
        return "Select Mint"
    }
    
    // MARK: - Theme Color Button
    
    private func themeColorButton(theme: ThemeColor, index: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.selectedThemeIndex = index
            }
        }) {
            ZStack {
                // Nut/cashew icon shape
                Circle()
                    .fill(theme.color)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.black.opacity(0.3))
                    )
                
                // Selection indicator
                if settings.selectedThemeIndex == index {
                    Circle()
                        .stroke(theme.color, lineWidth: 3)
                        .frame(width: 46, height: 46)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Rectangle()
                .fill(Color.cashuBorder)
                .frame(height: 1)
            
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.cashuMutedText)
                .tracking(2)
            
            Rectangle()
                .fill(Color.cashuBorder)
                .frame(height: 1)
        }
        .padding(.top, 32)
        .padding(.bottom, 16)
    }
    
    private func settingButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(settings.accentColor)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.cashuMutedText)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)
            }
            .padding(.vertical, 12)
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.cashuMutedText)
            Spacer()
            Text(value)
                .foregroundColor(.white)
        }
        .font(.subheadline)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func linkRow(icon: String, title: String, subtitle: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                linkRowLabel(icon: icon, title: title, subtitle: subtitle)
            }
        } else {
            linkRowLabel(icon: icon, title: title, subtitle: subtitle)
        }
    }
    
    private func linkRowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(settings.accentColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)
            }
            
            Spacer()
            
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundColor(.cashuMutedText)
        }
        .padding(.vertical, 12)
    }
    
    private func deleteWallet() {
        try? KeychainService().deleteMnemonic()
        walletManager.needsOnboarding = true
    }
    
    private func formatBTCPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = settings.bitcoinPriceCurrency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "\(settings.bitcoinPriceCurrency) 0"
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct QRPayload: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}

struct QRCodeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings = SettingsManager.shared

    let title: String
    let content: String

    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    QRCodeView(content: content, showControls: false)
                        .padding()
                        .frame(width: 280, height: 280)
                        .background(Color.white)
                        .cornerRadius(12)

                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .padding(.horizontal)

                    Button(action: copyToClipboard) {
                        HStack {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy")
                        }
                    }
                    .buttonStyle(CashuSecondaryButtonStyle())
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = content
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

struct ImportP2PKSheet: View {
    @Binding var nsecText: String
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("Import P2PK nsec")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Import an nsec key to add a P2PK locking key.")
                        .font(.subheadline)
                        .foregroundColor(.cashuMutedText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    TextField("nsec1...", text: $nsecText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.cashuCardBackground)
                        )
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    if let validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundColor(.cashuError)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        Button(action: {
                            if validate() {
                                onImport()
                            }
                        }) {
                            Text("Import nsec")
                        }
                        .buttonStyle(CashuPrimaryButtonStyle())
                        .disabled(nsecText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(action: { dismiss() }) {
                            Text("Cancel")
                        }
                        .buttonStyle(CashuSecondaryButtonStyle())
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top, 24)
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
                    Text("Import P2PK")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func validate() -> Bool {
        validationError = nil
        let value = nsecText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.hasPrefix("nsec1") else {
            validationError = "Invalid nsec format"
            return false
        }
        return true
    }
}

// MARK: - Backup View

struct BackupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var showWords = false
    @State private var copiedToClipboard = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Warning
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.cashuWarning)
                            
                            Text("Keep Your Seed Phrase Safe")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Anyone with these words can access your funds. Never share them with anyone.")
                                .font(.subheadline)
                                .foregroundColor(.cashuMutedText)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        
                        let words = walletManager.getMnemonicWords()
                        let mnemonic = words.joined(separator: " ")
                        let hiddenMnemonic = words.map { String(repeating: "•", count: max(3, $0.count)) }.joined(separator: " ")

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Seed phrase")
                                .font(.caption)
                                .foregroundColor(.cashuMutedText)

                            HStack(spacing: 10) {
                                Text(showWords ? mnemonic : hiddenMnemonic)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(showWords ? .white : .cashuMutedText)
                                    .lineLimit(4)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)

                                VStack(spacing: 8) {
                                    Button(action: { showWords.toggle() }) {
                                        Image(systemName: showWords ? "eye.slash" : "eye")
                                            .foregroundColor(settings.accentColor)
                                    }

                                    Button(action: copyToClipboard) {
                                        Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                            .foregroundColor(copiedToClipboard ? .green : settings.accentColor)
                                    }
                                }
                            }
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
                        .padding(.horizontal)
                        
                        Spacer(minLength: 50)
                        
                        Button(action: { dismiss() }) {
                            Text("DONE")
                        }
                        .buttonStyle(CashuSecondaryButtonStyle())
                        .padding(.horizontal)
                        .padding(.bottom, 30)
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
                    Text("Backup")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private func copyToClipboard() {
        let words = walletManager.getMnemonicWords().joined(separator: " ")
        UIPasteboard.general.string = words
        copiedToClipboard = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copiedToClipboard = false
        }
    }
}

// MARK: - Mint Picker Sheet

struct MintPickerSheet: View {
    let mints: [MintInfo]
    @Binding var selectedMintUrl: String?
    let onSelect: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(mints, id: \.url) { mint in
                            Button(action: {
                                selectedMintUrl = mint.url
                                onSelect(mint.url)
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(mint.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                        
                                        Text(mint.url)
                                            .font(.caption)
                                            .foregroundColor(.cashuMutedText)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedMintUrl == mint.url {
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
                                                .stroke(selectedMintUrl == mint.url ? settings.accentColor : Color.clear, lineWidth: 2)
                                        )
                                )
                            }
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
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Select Mint")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Import Nsec Sheet

struct ImportNsecSheet: View {
    @Binding var nsecText: String
    let onImport: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings = SettingsManager.shared
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Instructions
                    VStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 48))
                            .foregroundColor(settings.accentColor)
                        
                        Text("Import Nostr Key")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("Enter your nsec (Nostr private key) to use it for your Lightning address.")
                            .font(.subheadline)
                            .foregroundColor(.cashuMutedText)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    
                    // nsec input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("nsec")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                        
                        TextField("nsec1...", text: $nsecText)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.cashuCardBackground)
                            )
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal)
                    
                    // Paste from clipboard button
                    Button(action: pasteFromClipboard) {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                            Text("Paste from Clipboard")
                        }
                        .font(.subheadline)
                        .foregroundColor(settings.accentColor)
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.cashuError)
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            if validateNsec() {
                                onImport()
                            }
                        }) {
                            Text("Import Key")
                        }
                        .buttonStyle(CashuPrimaryButtonStyle())
                        .disabled(nsecText.isEmpty)
                        
                        Button(action: { dismiss() }) {
                            Text("Cancel")
                        }
                        .buttonStyle(CashuSecondaryButtonStyle())
                    }
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
                    Text("Import Key")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private func pasteFromClipboard() {
        if let text = UIPasteboard.general.string {
            nsecText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    private func validateNsec() -> Bool {
        errorMessage = nil
        let trimmed = nsecText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard trimmed.hasPrefix("nsec1") else {
            errorMessage = "Invalid format. nsec must start with 'nsec1'"
            return false
        }
        
        guard trimmed.count >= 59 else {
            errorMessage = "nsec is too short"
            return false
        }
        
        return true
    }
}

#Preview {
    SettingsView()
        .environmentObject(WalletManager())
}
