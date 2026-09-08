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

    func testDefaultPortAccountsKeepTheirStorageKeysAndBothBalances() async throws {
        try await withHistoryService { db, repo, service, _ in
            let urls = ["https://offline.example:443", "https://offline.example"]
            let keys = ["02", "03"].map { $0 + "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798" }
            for (index, url) in urls.enumerated() {
                let mint = MintUrl(url: url)
                try await db.addMint(mintUrl: mint, mintInfo: nil)
                try await db.updateProofs(added: [ProofInfo(
                    proof: Proof(amount: Amount(value: UInt64(8 << index)), secret: "stored-account-\(index)",
                        c: keys[index], keysetId: "001234567890abcd", witness: nil, dleq: nil, p2pkE: nil),
                    y: PublicKey(hex: keys[index]), mintUrl: mint, state: .unspent,
                    spendingCondition: nil, unit: .usd, derivationIndex: nil,
                    usedByOperation: nil, createdByOperation: nil
                )], removedYs: [])
                try await db.addTransaction(transaction: Cdk.Transaction(
                    id: TransactionId(hex: String(repeating: index == 0 ? "a" : "b", count: 64)),
                    mintUrl: mint, direction: .incoming, amount: Amount(value: 8), fee: Amount(value: 0),
                    unit: .usd, ys: [], timestamp: 1, memo: nil, metadata: [:], quoteId: nil,
                    paymentRequest: nil, paymentProof: nil, paymentMethod: nil, sagaId: nil, status: .completed
                ))
            }
            let accounts = try await StoredWalletAccount.discover(database: db, repository: repo)
                .filter { $0.unit == .usd && $0.matches(mintURL: urls[1]) }
            XCTAssertEqual(Set(accounts.map(\.mintURL)), Set(urls))
            let projection = try await StoredBalanceProjection.load(accounts: accounts, previousTotals: [:]) {
                try await db.getBalance(mintUrl: MintUrl(url: $0.mintURL), unit: $0.unit, state: [.unspent])
            }
            XCTAssertEqual(projection.totals["usd"], 24)
            XCTAssertEqual(projection.balance(mintURL: urls[1], unit: .usd), 24)
            let partial = try await StoredBalanceProjection.load(accounts: accounts, previousTotals: ["usd": 24]) {
                if $0.mintURL == urls[0] { throw Failure.storage }
                return 16
            }
            XCTAssertEqual(partial.totals["usd"], 24)
            XCTAssertNil(partial.balance(mintURL: urls[1], unit: .usd))
            await service.loadTransactions(includeRemoteObservations: false)
            XCTAssertEqual(Set(service.transactions.compactMap(\.mintUrl)), Set(urls))
            db.failAccountReads = true
            await service.loadTransactions(includeRemoteObservations: false)
            XCTAssertEqual(service.transactions.count, 2)
        }
    }

    func testAccountAndDiscoveryFailuresDoNotSuppressFreshQuotes() async throws {
        try await withHistoryService { db, _, service, _ in
            try await db.addMintQuote(quote: MintQuote(
                id: "invoice", amount: Amount(value: 8), unit: .sat, request: "invoice-request",
                state: .unpaid, expiry: 1, mintUrl: MintUrl(url: "https://offline.example"),
                amountIssued: Amount(value: 0), amountPaid: Amount(value: 0), updatedAt: 1,
                estimatedBlocks: nil, paymentMethod: .bolt11, secretKey: nil, usedByOperation: nil, version: 0
            ))
            let staleInvoice = WalletTransaction(
                id: "invoice", amount: 8, type: .incoming, kind: .lightning, date: Date(), memo: nil,
                status: .pending, mintUrl: "https://offline.example", quoteId: "invoice"
            )
            let completed = WalletTransaction(
                id: "cdk-transaction", amount: 8, type: .incoming, kind: .lightning, date: Date(), memo: nil,
                status: .completed, mintUrl: "https://offline.example", quoteId: "settled-quote"
            )
            for discoveryFails in [false, true] {
                db.failAccountReads = true
                db.failDiscoveryReads = discoveryFails
                db.failQuoteReads = false
                service.transactions = [staleInvoice, completed]
                await service.loadTransactions(includeRemoteObservations: false)
                XCTAssertEqual(service.transactions.first { $0.id == "invoice" }?.status, .expired)
                XCTAssertEqual(service.transactions.count, 2)
                XCTAssertEqual(service.transactions.first { $0.id == completed.id }?.status, .completed)

                db.failQuoteReads = true
                service.transactions = [staleInvoice, completed]
                await service.loadTransactions(includeRemoteObservations: false)
                XCTAssertEqual(service.transactions.first { $0.id == "invoice" }?.status, .pending)
                XCTAssertEqual(service.transactions.count, 2)
            }
        }
    }

    func testDiscoveryFailureStillRebuildsLocallyParkedTokensAfterRelaunch() async throws {
        try await withHistoryService { db, repo, service, store in
            db.failDiscoveryReads = true
            let pending = PendingReceiveToken(tokenId: "parked", token: "cashuAparked", amount: 8,
                date: Date(), mintUrl: "https://offline.example")
            service.savePendingReceiveToken(pending)
            await service.loadTransactions(includeRemoteObservations: false)
            XCTAssertEqual(service.transactions.map(\.id), [pending.tokenId])
            XCTAssertTrue(service.transactions.first?.isPendingReceiveToken == true)

            let relaunched = TransactionService(walletRepository: { repo }, walletDatabase: { db },
                getTrackedMintUrls: { ["https://offline.example"] }, walletStore: store)
            await relaunched.loadTransactions(includeRemoteObservations: false)
            XCTAssertEqual(relaunched.transactions.map(\.id), [pending.tokenId])
            relaunched.removePendingReceiveToken(tokenId: pending.tokenId)
            await relaunched.loadTransactions(includeRemoteObservations: false)
            XCTAssertTrue(relaunched.transactions.isEmpty)
        }
    }

    private func withHistoryService(
        _ body: (FailingAccountHistoryDatabase, WalletRepository, TransactionService, CashuWallet.WalletStore) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LifecycleSafeWalletDatabase(filePath: directory.appendingPathComponent("wallet.sqlite").path)
        let reader = FailingAccountHistoryDatabase(database: database)
        let repo = try WalletRepository(mnemonic: generateMnemonic(), store: customWalletStore(db: database))
        let store = WalletStore(storage: InMemoryStorage())
        let service = TransactionService(walletRepository: { repo }, walletDatabase: { reader },
            getTrackedMintUrls: { ["https://offline.example"] }, walletStore: store)
        try await body(reader, repo, service, store)
    }
}

private final class FailingAccountHistoryDatabase: WalletSqliteDatabase, @unchecked Sendable {
    private var retainedDatabase: WalletSqliteDatabase?
    var failAccountReads = false
    var failDiscoveryReads = false
    var failQuoteReads = false
    required init(unsafeFromHandle handle: UInt64) { super.init(unsafeFromHandle: handle) }
    convenience init(database: WalletSqliteDatabase) {
        self.init(unsafeFromHandle: database.uniffiCloneHandle())
        retainedDatabase = database
    }
    override func listTransactions(mintUrl: MintUrl?, direction: TransactionDirection?, unit: CurrencyUnit?) async throws -> [Cdk.Transaction] {
        if failAccountReads && unit != nil { throw NSError(domain: "TestStorage", code: 1) }
        return try await super.listTransactions(mintUrl: mintUrl, direction: direction, unit: unit)
    }
    override func getMintQuotes() async throws -> [MintQuote] {
        if failDiscoveryReads { throw NSError(domain: "TestStorage", code: 2) }
        return try await super.getMintQuotes()
    }
    override func getUnissuedMintQuotes() async throws -> [MintQuote] {
        if failQuoteReads { throw NSError(domain: "TestStorage", code: 3) }
        return try await super.getUnissuedMintQuotes()
    }
}
