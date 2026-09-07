import Cdk
import XCTest
@testable import CashuWallet

@MainActor
final class StoredWalletAccountTests: XCTestCase {
    private enum Failure: Error { case storage }

    func testFailedAccountPreservesWholeCurrencyTotalAndRetryReplacesIt() async throws {
        let a = StoredWalletAccount(mintURL: "https://a.example", unit: .usd)
        let b = StoredWalletAccount(mintURL: "https://b.example", unit: .usd)
        let sat = StoredWalletAccount(mintURL: a.mintURL, unit: .sat)
        let first = try await StoredBalanceProjection.load(accounts: [a, b, sat], previousTotals: ["usd": 500, "sat": 1]) {
            if $0 == b { throw Failure.storage }
            return $0 == sat ? 30 : 200
        }
        XCTAssertEqual(first.totals, ["usd": 500, "sat": 30])
        let retry = try await StoredBalanceProjection.load(accounts: [a, b, a], previousTotals: first.totals) { _ in 200 }
        XCTAssertEqual(retry.totals, ["usd": 400])
    }

    func testDiscontinuedZeroBalanceCurrencyAndHistorySurviveOfflineRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("wallet.sqlite").path
        let mnemonic = try generateMnemonic()
        let mint = MintUrl(url: "https://offline.example")
        let id = String(repeating: "a", count: 64)
        do {
            let db = try LifecycleSafeWalletDatabase(filePath: path)
            // No USD advertisement remains, but the historical account does.
            try await db.addMint(mintUrl: mint, mintInfo: nil)
            try await db.addTransaction(transaction: Cdk.Transaction(
                id: TransactionId(hex: id), mintUrl: mint, direction: .incoming,
                amount: Amount(value: 250), fee: Amount(value: 0), unit: .usd,
                ys: [], timestamp: 1, memo: nil, metadata: [:], quoteId: nil,
                paymentRequest: nil, paymentProof: nil, paymentMethod: nil, sagaId: nil, status: .completed
            ))
        }
        let db = try LifecycleSafeWalletDatabase(filePath: path)
        let repo = try WalletRepository(mnemonic: mnemonic, store: customWalletStore(db: db))
        let wallets = await repo.getWallets()
        XCTAssertFalse(wallets.contains { $0.unit() == .usd })
        let accounts = try await StoredWalletAccount.discover(database: db, repository: repo)
        let usd = StoredWalletAccount(mintURL: mint.url, unit: .usd)
        XCTAssertTrue(accounts.contains(usd))
        let projection = try await StoredBalanceProjection.load(accounts: accounts, previousTotals: [:]) {
            try await db.getBalance(mintUrl: MintUrl(url: $0.mintURL), unit: $0.unit, state: [.unspent])
        }
        XCTAssertEqual(projection.totals["usd"], 0)
        let reader = FailingAccountHistoryDatabase(database: db)
        let service = TransactionService(walletRepository: { repo }, walletDatabase: { reader }, getTrackedMintUrls: { [mint.url] })
        await service.loadTransactions(includeRemoteObservations: false)
        XCTAssertEqual(service.transactions.map(\.unit), ["usd"])
        reader.failAccountReads = true
        await service.loadTransactions(includeRemoteObservations: false)
        XCTAssertEqual(service.transactions.map(\.unit), ["usd"])
        reader.failAccountReads = false
        await service.loadTransactions(includeRemoteObservations: false)
        XCTAssertEqual(service.transactions.count, 1)
    }
}

private final class FailingAccountHistoryDatabase: WalletSqliteDatabase, @unchecked Sendable {
    private var retainedDatabase: WalletSqliteDatabase?
    var failAccountReads = false
    required init(unsafeFromHandle handle: UInt64) { super.init(unsafeFromHandle: handle) }
    convenience init(database: WalletSqliteDatabase) {
        self.init(unsafeFromHandle: database.uniffiCloneHandle())
        retainedDatabase = database
    }
    override func listTransactions(mintUrl: MintUrl?, direction: TransactionDirection?, unit: CurrencyUnit?) async throws -> [Cdk.Transaction] {
        if failAccountReads && unit != nil { throw NSError(domain: "TestStorage", code: 1) }
        return try await super.listTransactions(mintUrl: mintUrl, direction: direction, unit: unit)
    }
}
