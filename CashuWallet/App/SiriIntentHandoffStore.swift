import Combine
import Foundation

struct SiriCreateTokenRequest: Codable, Identifiable, Equatable, Sendable {
    let id = UUID()
    let amountSats: UInt64
    let mint: String
    let memo: String?

    private enum CodingKeys: String, CodingKey {
        case amountSats
        case mint
        case memo
    }
}

enum SiriWalletAction: String, Codable, Equatable, Sendable {
    case wallet
    case receiveEcash
    case receiveLightning
    case sendEcash
    case payLightning
    case scanQRCode
    case showHistory
    case showMints
    case showSettings
    case contactlessPayment
}

struct SiriWalletActionRequest: Codable, Identifiable, Equatable, Sendable {
    let id = UUID()
    let action: SiriWalletAction
    let createdAt: Date

    init(action: SiriWalletAction, createdAt: Date = Date()) {
        self.action = action
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case createdAt
    }
}

struct SiriWalletSnapshot: Codable, Equatable, Sendable {
    struct Mint: Codable, Equatable, Sendable {
        let name: String
        let url: String
        let balanceSats: UInt64
        let isActive: Bool
    }

    let balanceSats: UInt64
    let pendingBalanceSats: UInt64
    let activeMintName: String?
    let activeMintURL: String?
    let mints: [Mint]
    let updatedAt: Date
}

enum SiriIntentHandoffPersistence {
    private static let createTokenRequestKey = "siri.createTokenRequest"
    private static let walletActionRequestKey = "siri.walletActionRequest"
    private static let walletSnapshotKey = "siri.walletSnapshot"

    static func saveCreateTokenRequest(_ request: SiriCreateTokenRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        UserDefaults.standard.set(data, forKey: createTokenRequestKey)
    }

    static func loadCreateTokenRequest() -> SiriCreateTokenRequest? {
        guard let data = UserDefaults.standard.data(forKey: createTokenRequestKey) else { return nil }
        return try? JSONDecoder().decode(SiriCreateTokenRequest.self, from: data)
    }

    static func clearCreateTokenRequest() {
        UserDefaults.standard.removeObject(forKey: createTokenRequestKey)
    }

    static func saveWalletActionRequest(_ request: SiriWalletActionRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        UserDefaults.standard.set(data, forKey: walletActionRequestKey)
    }

    static func loadWalletActionRequest() -> SiriWalletActionRequest? {
        guard let data = UserDefaults.standard.data(forKey: walletActionRequestKey) else { return nil }
        return try? JSONDecoder().decode(SiriWalletActionRequest.self, from: data)
    }

    static func clearWalletActionRequest() {
        UserDefaults.standard.removeObject(forKey: walletActionRequestKey)
    }

    @MainActor
    static func saveWalletSnapshot(from walletManager: WalletManager) {
        let snapshot = SiriWalletSnapshot(
            balanceSats: walletManager.balance,
            pendingBalanceSats: walletManager.pendingBalance,
            activeMintName: walletManager.activeMint?.name,
            activeMintURL: walletManager.activeMint?.url,
            mints: walletManager.mints.map {
                SiriWalletSnapshot.Mint(
                    name: $0.name,
                    url: $0.url,
                    balanceSats: $0.balance,
                    isActive: $0.url == walletManager.activeMint?.url
                )
            },
            updatedAt: Date()
        )
        saveWalletSnapshot(snapshot)
    }

    static func saveWalletSnapshot(_ snapshot: SiriWalletSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: walletSnapshotKey)
    }

    static func loadWalletSnapshot() -> SiriWalletSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: walletSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(SiriWalletSnapshot.self, from: data)
    }
}

@MainActor
final class SiriIntentHandoffStore: ObservableObject {
    static let shared = SiriIntentHandoffStore()

    @Published var pendingCreateTokenRequest: SiriCreateTokenRequest?
    @Published var pendingWalletActionRequest: SiriWalletActionRequest?

    private init() {}

    func requestCreateToken(amountSats: UInt64, mint: String, memo: String?) {
        let request = SiriCreateTokenRequest(
            amountSats: amountSats,
            mint: mint,
            memo: memo
        )
        SiriIntentHandoffPersistence.saveCreateTokenRequest(request)
        pendingCreateTokenRequest = request
    }

    func requestWalletAction(_ action: SiriWalletAction) {
        let request = SiriWalletActionRequest(action: action)
        SiriIntentHandoffPersistence.saveWalletActionRequest(request)
        pendingWalletActionRequest = request
    }

    func restorePendingCreateTokenRequest() {
        guard pendingCreateTokenRequest == nil,
              let request = SiriIntentHandoffPersistence.loadCreateTokenRequest() else {
            return
        }
        pendingCreateTokenRequest = request
    }

    func restorePendingWalletActionRequest() {
        guard pendingWalletActionRequest == nil,
              let request = SiriIntentHandoffPersistence.loadWalletActionRequest() else {
            return
        }
        pendingWalletActionRequest = request
    }

    func restorePendingRequests() {
        restorePendingCreateTokenRequest()
        restorePendingWalletActionRequest()
    }

    func clearCreateTokenRequest() {
        SiriIntentHandoffPersistence.clearCreateTokenRequest()
        pendingCreateTokenRequest = nil
    }

    func clearWalletActionRequest(_ request: SiriWalletActionRequest? = nil) {
        guard request == nil || request == pendingWalletActionRequest else { return }
        SiriIntentHandoffPersistence.clearWalletActionRequest()
        pendingWalletActionRequest = nil
    }
}
