import AppIntents
import CoreNFC
import Foundation

struct CreateEcashTokenIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Ecash Token"
    static var description = IntentDescription(
        "Create a Cashu ecash token and open the wallet to show its QR code."
    )
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    @Parameter(
        title: "Amount",
        description: "Amount in satoshis",
        requestValueDialog: "How many sats should the token contain?"
    )
    var amount: Int

    @Parameter(
        title: "Mint",
        description: "Mint URL or host, for example 8333.space",
        default: "",
        requestValueDialog: "Which mint should be used?"
    )
    var mint: String

    @Parameter(
        title: "Memo",
        description: "Optional note for the token",
        default: "",
        requestValueDialog: "What memo should be included?"
    )
    var memo: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$amount) sat ecash from \(\.$mint)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            throw CreateEcashTokenIntentError.invalidAmount
        }

        let normalizedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = SiriCreateTokenRequest(
            amountSats: UInt64(amount),
            mint: mint.trimmingCharacters(in: .whitespacesAndNewlines),
            memo: normalizedMemo.isEmpty ? nil : normalizedMemo
        )
        SiriIntentHandoffPersistence.saveCreateTokenRequest(request)

        await SiriIntentHandoffStore.shared.requestCreateToken(
            amountSats: request.amountSats,
            mint: request.mint,
            memo: request.memo
        )

        if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
            try await continueInForeground(
                "Opening Cashu Wallet to create the token.",
                alwaysConfirm: false
            )
        }

        return .result(dialog: "Opening Cashu Wallet to create the token.")
    }
}

struct GetWalletBalanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Wallet Balance"
    static var description = IntentDescription(
        "Read the latest Cashu Wallet balance snapshot."
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SiriIntentHandoffPersistence.loadWalletSnapshot() else {
            await SiriIntentHandoffStore.shared.requestWalletAction(.wallet)

            if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
                try await continueInForeground(
                    "Opening Cashu Wallet to update Siri balance.",
                    alwaysConfirm: false
                )
            }

            return .result(dialog: "Open Cashu Wallet once so Siri can read your latest balance.")
        }

        var dialog = "Your Cashu Wallet balance is \(siriFormattedSats(snapshot.balanceSats))."
        if snapshot.pendingBalanceSats > 0 {
            dialog += " Pending: \(siriFormattedSats(snapshot.pendingBalanceSats))."
        }
        if let activeMintName = snapshot.activeMintName, !activeMintName.isEmpty {
            dialog += " Active mint: \(activeMintName)."
        }
        dialog += " \(siriSnapshotRecency(snapshot.updatedAt))."

        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct ListWalletMintsIntent: AppIntent {
    static var title: LocalizedStringResource = "List Wallet Mints"
    static var description = IntentDescription(
        "List the mints saved in Cashu Wallet and their latest cached balances."
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SiriIntentHandoffPersistence.loadWalletSnapshot() else {
            await SiriIntentHandoffStore.shared.requestWalletAction(.showMints)

            if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
                try await continueInForeground(
                    "Opening Cashu Wallet to show mints.",
                    alwaysConfirm: false
                )
            }

            return .result(dialog: "Open Cashu Wallet once so Siri can read your mints.")
        }

        guard !snapshot.mints.isEmpty else {
            return .result(dialog: "Cashu Wallet does not have any saved mints yet.")
        }

        let visibleMints = snapshot.mints.prefix(5).map { mint in
            let active = mint.isActive ? " active" : ""
            return "\(mint.name), \(siriFormattedSats(mint.balanceSats))\(active)"
        }
        var dialog = "Your mints are: \(visibleMints.joined(separator: "; "))."
        if snapshot.mints.count > visibleMints.count {
            dialog += " And \(snapshot.mints.count - visibleMints.count) more."
        }
        dialog += " \(siriSnapshotRecency(snapshot.updatedAt))."

        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

enum SiriWalletDestination: String, AppEnum, Codable, Sendable {
    case wallet
    case receiveEcash
    case receiveLightning
    case sendEcash
    case payLightning
    case scanner
    case history
    case mints
    case settings

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cashu Wallet Destination")

    static var caseDisplayRepresentations: [SiriWalletDestination: DisplayRepresentation] = [
        .wallet: DisplayRepresentation(title: "Wallet"),
        .receiveEcash: DisplayRepresentation(title: "Receive Ecash"),
        .receiveLightning: DisplayRepresentation(title: "Receive Lightning"),
        .sendEcash: DisplayRepresentation(title: "Send Ecash"),
        .payLightning: DisplayRepresentation(title: "Pay Lightning"),
        .scanner: DisplayRepresentation(title: "QR Scanner"),
        .history: DisplayRepresentation(title: "History"),
        .mints: DisplayRepresentation(title: "Mints"),
        .settings: DisplayRepresentation(title: "Settings")
    ]

    var walletAction: SiriWalletAction {
        switch self {
        case .wallet:
            return .wallet
        case .receiveEcash:
            return .receiveEcash
        case .receiveLightning:
            return .receiveLightning
        case .sendEcash:
            return .sendEcash
        case .payLightning:
            return .payLightning
        case .scanner:
            return .scanQRCode
        case .history:
            return .showHistory
        case .mints:
            return .showMints
        case .settings:
            return .showSettings
        }
    }
}

struct OpenCashuWalletIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Cashu Wallet"
    static var description = IntentDescription(
        "Open a specific Cashu Wallet screen or payment flow."
    )
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    @Parameter(
        title: "Destination",
        requestValueDialog: "What should Cashu Wallet open?"
    )
    var destination: SiriWalletDestination

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$destination)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await SiriIntentHandoffStore.shared.requestWalletAction(destination.walletAction)

        if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
            try await continueInForeground(
                "Opening \(destination.displayTitle) in Cashu Wallet.",
                alwaysConfirm: false
            )
        }

        return .result(dialog: IntentDialog(stringLiteral: "Opening \(destination.displayTitle) in Cashu Wallet."))
    }
}

struct OpenReceiveEcashIntent: AppIntent {
    static var title: LocalizedStringResource = "Receive Ecash"
    static var description = IntentDescription("Open Cashu Wallet to receive an ecash token.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await SiriIntentHandoffStore.shared.requestWalletAction(.receiveEcash)

        if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
            try await continueInForeground(
                "Opening Cashu Wallet to receive ecash.",
                alwaysConfirm: false
            )
        }

        return .result(dialog: "Opening Cashu Wallet to receive ecash.")
    }
}

struct OpenReceiveLightningIntent: AppIntent {
    static var title: LocalizedStringResource = "Receive Lightning"
    static var description = IntentDescription("Open Cashu Wallet to create a Lightning invoice.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await SiriIntentHandoffStore.shared.requestWalletAction(.receiveLightning)

        if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
            try await continueInForeground(
                "Opening Cashu Wallet to receive Lightning.",
                alwaysConfirm: false
            )
        }

        return .result(dialog: "Opening Cashu Wallet to receive Lightning.")
    }
}

struct OpenSendEcashIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Ecash"
    static var description = IntentDescription("Open Cashu Wallet to send ecash.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await SiriIntentHandoffStore.shared.requestWalletAction(.sendEcash)

        if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
            try await continueInForeground(
                "Opening Cashu Wallet to send ecash.",
                alwaysConfirm: false
            )
        }

        return .result(dialog: "Opening Cashu Wallet to send ecash.")
    }
}

struct OpenPayLightningIntent: AppIntent {
    static var title: LocalizedStringResource = "Pay Lightning"
    static var description = IntentDescription("Open Cashu Wallet to pay a Lightning invoice.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await SiriIntentHandoffStore.shared.requestWalletAction(.payLightning)

        if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
            try await continueInForeground(
                "Opening Cashu Wallet to pay Lightning.",
                alwaysConfirm: false
            )
        }

        return .result(dialog: "Opening Cashu Wallet to pay Lightning.")
    }
}

struct OpenQRScannerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open QR Scanner"
    static var description = IntentDescription("Open the Cashu Wallet QR scanner.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await SiriIntentHandoffStore.shared.requestWalletAction(.scanQRCode)

        if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
            try await continueInForeground(
                "Opening the Cashu Wallet QR scanner.",
                alwaysConfirm: false
            )
        }

        return .result(dialog: "Opening the Cashu Wallet QR scanner.")
    }
}

struct StartContactlessPaymentIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Contactless Payment"
    static var description = IntentDescription(
        "Open Cashu Wallet and start the native NFC payment scanner."
    )
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        [.background, .foreground(.dynamic)]
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard NFCNDEFReaderSession.readingAvailable else {
            throw SiriWalletIntentError.nfcUnavailable
        }

        await SiriIntentHandoffStore.shared.requestWalletAction(.contactlessPayment)

        if #available(iOS 26.0, *), systemContext.currentMode.canContinueInForeground {
            try await continueInForeground(
                "Opening Cashu Wallet for contactless payment.",
                alwaysConfirm: false
            )
        }

        return .result(dialog: "Opening Cashu Wallet for contactless payment.")
    }
}

struct CashuWalletShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateEcashTokenIntent(),
            phrases: [
                "Create an ecash token in \(.applicationName)",
                "Create a Cashu token in \(.applicationName)",
                "Make an ecash token with \(.applicationName)",
                "Make a Cashu token with \(.applicationName)",
                "Send ecash with \(.applicationName)"
            ],
            shortTitle: "Create Ecash",
            systemImageName: "qrcode"
        )
        AppShortcut(
            intent: GetWalletBalanceIntent(),
            phrases: [
                "Get my balance in \(.applicationName)",
                "Check my Cashu balance in \(.applicationName)",
                "Show my wallet balance in \(.applicationName)"
            ],
            shortTitle: "Balance",
            systemImageName: "bitcoinsign.circle"
        )
        AppShortcut(
            intent: ListWalletMintsIntent(),
            phrases: [
                "List my mints in \(.applicationName)",
                "Show my Cashu mints in \(.applicationName)",
                "Which mints are in \(.applicationName)"
            ],
            shortTitle: "List Mints",
            systemImageName: "bitcoinsign.bank.building"
        )
        AppShortcut(
            intent: OpenReceiveEcashIntent(),
            phrases: [
                "Receive ecash in \(.applicationName)",
                "Open receive ecash in \(.applicationName)",
                "Get an ecash token in \(.applicationName)"
            ],
            shortTitle: "Receive Ecash",
            systemImageName: "arrow.down.circle"
        )
        AppShortcut(
            intent: OpenReceiveLightningIntent(),
            phrases: [
                "Receive Lightning in \(.applicationName)",
                "Create a Lightning invoice in \(.applicationName)",
                "Open receive Lightning in \(.applicationName)"
            ],
            shortTitle: "Receive Lightning",
            systemImageName: "bolt.circle"
        )
        AppShortcut(
            intent: OpenSendEcashIntent(),
            phrases: [
                "Send ecash in \(.applicationName)",
                "Open send ecash in \(.applicationName)",
                "Send a Cashu token in \(.applicationName)"
            ],
            shortTitle: "Send Ecash",
            systemImageName: "arrow.up.circle"
        )
        AppShortcut(
            intent: OpenPayLightningIntent(),
            phrases: [
                "Pay Lightning in \(.applicationName)",
                "Pay an invoice in \(.applicationName)",
                "Open pay Lightning in \(.applicationName)"
            ],
            shortTitle: "Pay Lightning",
            systemImageName: "bolt.arrow.trianglehead.clockwise"
        )
        AppShortcut(
            intent: OpenQRScannerIntent(),
            phrases: [
                "Scan a QR code in \(.applicationName)",
                "Open the QR scanner in \(.applicationName)",
                "Scan with \(.applicationName)"
            ],
            shortTitle: "Scan QR",
            systemImageName: "viewfinder"
        )
        AppShortcut(
            intent: StartContactlessPaymentIntent(),
            phrases: [
                "Start contactless payment in \(.applicationName)",
                "Pay contactless with \(.applicationName)",
                "Use NFC payment in \(.applicationName)"
            ],
            shortTitle: "Contactless",
            systemImageName: "wave.3.right.circle"
        )
    }
}

enum CreateEcashTokenIntentError: LocalizedError {
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            "Amount must be greater than zero."
        }
    }
}

enum SiriWalletIntentError: LocalizedError {
    case nfcUnavailable

    var errorDescription: String? {
        switch self {
        case .nfcUnavailable:
            "NFC is not available on this device."
        }
    }
}

private extension SiriWalletDestination {
    var displayTitle: String {
        switch self {
        case .wallet:
            return "Wallet"
        case .receiveEcash:
            return "Receive Ecash"
        case .receiveLightning:
            return "Receive Lightning"
        case .sendEcash:
            return "Send Ecash"
        case .payLightning:
            return "Pay Lightning"
        case .scanner:
            return "QR Scanner"
        case .history:
            return "History"
        case .mints:
            return "Mints"
        case .settings:
            return "Settings"
        }
    }
}

private func siriFormattedSats(_ sats: UInt64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    let value = formatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
    return "\(value) sat"
}

private func siriSnapshotRecency(_ date: Date) -> String {
    let elapsed = max(0, Date().timeIntervalSince(date))

    if elapsed < 60 {
        return "Updated just now."
    }

    if elapsed < 3600 {
        let minutes = max(1, Int(elapsed / 60))
        return "Updated \(minutes) minute\(minutes == 1 ? "" : "s") ago."
    }

    let hours = max(1, Int(elapsed / 3600))
    return "Updated \(hours) hour\(hours == 1 ? "" : "s") ago."
}
