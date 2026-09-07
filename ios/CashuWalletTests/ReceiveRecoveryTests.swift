import Cdk
import XCTest
@testable import CashuWallet

@MainActor
final class ReceiveRecoveryTests: XCTestCase {
    private let mintURL = "http://localhost:3340"

    func testOnlyReceiveSagasSupplyRecoveryCandidates() {
        XCTAssertEqual(ReceiveRecoveryCandidate.fromSaga(#"{"kind":"receive","mint_url":"https://mint.example","unit":"usd"}"#)?.unit, .usd)
        XCTAssertNil(ReceiveRecoveryCandidate.fromSaga(#"{"kind":"send","mint_url":"https://mint.example","unit":"sat"}"#))
        XCTAssertNil(ReceiveRecoveryCandidate.fromSaga("invalid"))
    }

    func testOfflinePlaceholderKeepsEveryRecoveredCurrency() {
        let store = WalletStore(storage: InMemoryStorage())
        let service = MintService(walletRepository: { nil }, walletStore: store)
        service.trackReceivedMintLocally(url: "https://mint.example", unit: .sat)
        service.trackReceivedMintLocally(url: "https://mint.example", unit: .usd)
        service.trackReceivedMintLocally(url: "https://mint.example", unit: .usd)
        XCTAssertEqual(store.loadMints().count, 1)
        XCTAssertEqual(Set(store.loadMints().first?.units ?? []), ["sat", "usd"])
    }

    func testCompletedReceiptBeforeTrackingSurvivesOfflineRelaunch() async throws {
        try await exerciseReceipt(interrupt: false)
    }

    func testAcceptedSwapWithLostResponseRecoversAfterRelaunchExactlyOnce() async throws {
        try await exerciseReceipt(interrupt: true)
    }

    private func exerciseReceipt(interrupt: Bool) async throws {
        try await control("reset")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let seed = try generateMnemonic()
        let path = directory.appendingPathComponent("receiver.sqlite").path
        let senderDB = try LifecycleSafeWalletDatabase(filePath: directory.appendingPathComponent("sender.sqlite").path)
        let sender = try WalletRepository(mnemonic: generateMnemonic(), store: customWalletStore(db: senderDB))
        let mint = MintUrl(url: mintURL)
        try await sender.createWallet(mintUrl: mint, unit: .sat, targetProofCount: nil)
        let wallet = try await sender.getWallet(mintUrl: mint, unit: .sat)
        let quote = try await wallet.mintQuote(paymentMethod: .bolt11, amount: Amount(value: 16), description: nil, extra: nil)
        for _ in 0..<40 {
            if try await wallet.checkMintQuote(quoteId: quote.id).state == .paid { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        _ = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .none, spendingConditions: nil)
        let token = try await TokenService(walletRepository: { sender }, getActiveMint: { nil })
            .sendTokens(amount: 16, mintUrl: mintURL).token
        do {
            let db = try LifecycleSafeWalletDatabase(filePath: path)
            let repo = try WalletRepository(mnemonic: seed, store: customWalletStore(db: db))
            try await repo.createWallet(mintUrl: mint, unit: .sat, targetProofCount: nil)
            let previewCandidates = try await ReceiveRecoveryCandidate.discover(database: db)
            XCTAssertTrue(previewCandidates.isEmpty, "A preview or unapproved token must not track a mint")
            if interrupt { try await control("interrupt-next-swap") }
            do {
                _ = try await TokenService(walletRepository: { repo }, getActiveMint: { nil }).receiveTokens(tokenString: token)
                XCTAssertFalse(interrupt, "Proxy should interrupt the accepted swap")
            } catch {
                if !interrupt { throw error }
            }
        }
        try await control("offline")
        let db = try LifecycleSafeWalletDatabase(filePath: path)
        let repo = try WalletRepository(mnemonic: seed, store: customWalletStore(db: db))
        let candidates = try await ReceiveRecoveryCandidate.discover(database: db)
        XCTAssertEqual(candidates, [ReceiveRecoveryCandidate(mintURL: mintURL, unit: .sat)])
        let store = WalletStore(storage: InMemoryStorage())
        let mints = MintService(walletRepository: { nil }, walletStore: store)
        for candidate in candidates {
            mints.trackReceivedMintLocally(url: candidate.mintURL, unit: candidate.unit)
            mints.trackReceivedMintLocally(url: candidate.mintURL, unit: candidate.unit)
        }
        XCTAssertEqual(store.loadMints().count, 1, "Tracking needs no repository or metadata request")
        if !interrupt {
            let offlineBalance = try await db.getBalance(mintUrl: mint, unit: .sat, state: [.unspent])
            XCTAssertEqual(offlineBalance, 16)
        }
        try await control("reset")
        let recovered = try await repo.getWallet(mintUrl: mint, unit: .sat)
        _ = try await recovered.recoverIncompleteSagas()
        _ = try await recovered.recoverIncompleteSagas()
        let balance = try await recovered.totalBalance().value
        XCTAssertEqual(balance, 16)
        let history = try await recovered.listTransactions(direction: .incoming)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.status, .completed)
    }

    private func control(_ action: String) async throws {
        var request = URLRequest(url: URL(string: "\(mintURL)/__receipt_test/\(action)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
