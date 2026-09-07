import Foundation
import XCTest
import Cdk

/// Real native wallets, separate durable stores, and a scenario-scoped fault proxy.
/// The fixture is required in CI; ordinary unit-only runs can opt out explicitly.
class PaymentFixtureTestCase: XCTestCase {
    var fixture: String!
    var sessionID: String!
    var stores: [(WalletRepository, String, String)] = []
    var reopened: [WalletRepository] = []
    var walletHandles: [Wallet] = []
    var storeByWallet: [ObjectIdentifier: Int] = [:]

    override func setUp() async throws {
        try await super.setUp()
        fixture = ProcessInfo.processInfo.environment["PAYMENT_FIXTURE_URL"]
        try XCTSkipIf(fixture == nil, "Run with PAYMENT_FIXTURE_URL to enable payment fixtures")
        sessionID = try await call("/sessions", method: "POST")["id"] as? String
        XCTAssertNotNil(sessionID)
    }

    override func tearDown() async throws {
        if sessionID != nil { _ = try await call("/sessions/\(sessionID!)", method: "DELETE") }
        // Keep repository handles alive until the synchronous teardown boundary:
        // dropping the last native Tokio runtime from an async context is unsafe.
        try await super.tearDown()
    }

    override func tearDown() {
        let paths = stores.map { $0.1 }
        storeByWallet.removeAll()
        walletHandles.removeAll()
        reopened.removeAll()
        stores.removeAll()
        for path in paths {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }
        super.tearDown()
    }

    func call(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: fixture + path)!)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw NSError(domain: "PaymentFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture request failed: \(path)"])
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    var root: String { "/sessions/\(sessionID!)" }
    func mintURL(_ mint: String) -> String { fixture + root + "/mint/" + mint }

    func makeWallet(_ mint: String, unit: CurrencyUnit = .sat) async throws -> Wallet {
        let seed = try generateMnemonic()
        let path = NSTemporaryDirectory() + "payment-\(UUID().uuidString).sqlite"
        let repo = try WalletRepository(mnemonic: seed, store: .sqlite(path: path))
        stores.append((repo, path, seed))
        let url = MintUrl(url: mintURL(mint))
        try await repo.createWallet(mintUrl: url, unit: unit, targetProofCount: nil)
        let wallet = try await repo.getWallet(mintUrl: url, unit: unit)
        walletHandles.append(wallet)
        storeByWallet[ObjectIdentifier(wallet)] = stores.count - 1
        return wallet
    }

    func reopen(_ wallet: Wallet) async throws -> Wallet {
        let index = try XCTUnwrap(storeByWallet[ObjectIdentifier(wallet)])
        let entry = stores[index]
        let repo = try WalletRepository(mnemonic: entry.2, store: .sqlite(path: entry.1))
        reopened.append(repo)
        let recovered = try await repo.getWallet(mintUrl: wallet.mintUrl(), unit: wallet.unit())
        walletHandles.append(recovered)
        storeByWallet[ObjectIdentifier(recovered)] = index
        return recovered
    }

    func paidQuote(_ wallet: Wallet, amount: UInt64, controlled: String? = nil) async throws -> MintQuote {
        let quote = try await wallet.mintQuote(paymentMethod: .bolt11, amount: Amount(value: amount), description: nil, extra: nil)
        if let controlled {
            _ = try await call(root + "/pay/" + controlled, method: "POST", body: ["invoice": quote.request])
        }
        return try await awaitPaid(wallet, id: quote.id)
    }

    func awaitPaid(_ wallet: Wallet, id: String) async throws -> MintQuote {
        for _ in 0..<80 {
            let quote = try await wallet.checkMintQuote(quoteId: id)
            if quote.state == .paid || quote.state == .issued { return quote }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(domain: "PaymentFixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Quote did not become paid"])
    }

    func fund(_ wallet: Wallet, amount: UInt64 = 100, controlled: String? = nil) async throws {
        let quote = try await paidQuote(wallet, amount: amount, controlled: controlled)
        let proofs = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .none, spendingConditions: nil)
        XCTAssertEqual(proofs.reduce(0) { $0 + $1.amount.value }, amount)
    }

    func invoice(amount: UInt64 = 21, script: [String: Any]? = nil, expired: Bool = false) async throws -> String {
        var body: [String: Any] = ["amount": amount]
        if let script { body["description"] = String(data: try JSONSerialization.data(withJSONObject: script), encoding: .utf8)! }
        if expired { body["expiry"] = 1; body["age"] = 60 }
        return try await call(root + "/invoice", method: "POST", body: body)["invoice"] as! String
    }

    func arm(_ path: String, action: String, method: String = "POST", count: Int = 1) async throws {
        _ = try await call(root + "/faults", method: "POST", body: ["path": path, "method": method, "action": action, "remaining": count])
    }

    func send(_ wallet: Wallet, amount: UInt64, key: String? = nil, includeFee: Bool = false) async throws -> PreparedSend {
        try await wallet.prepareSend(amount: Amount(value: amount), options: SendOptions(
            memo: SendMemo(memo: "Payment test", includeMemo: true),
            conditions: key.map { .p2pk(pubkey: $0, conditions: nil) }, amountSplitTarget: .none,
            sendKind: .onlineExact, includeFee: includeFee, useP2bk: false, maxProofs: nil,
            metadata: [:], p2pkSigningKeys: [], p2pkLockedProofSendMode: .swap))
    }

    func receive(_ wallet: Wallet, token: Token, keys: [String] = []) async throws -> UInt64 {
        try await wallet.receive(token: token, options: ReceiveOptions(amountSplitTarget: .none,
            p2pkSigningKeys: keys.map { SecretKey(hex: $0) }, preimages: [], metadata: [:])).value
    }

    // Match the app's NUT-05 path, including a pending response followed by wait.
    func melt(_ wallet: Wallet, quoteID: String) async throws -> FinalizedMelt {
        switch try await wallet.prepareMelt(quoteId: quoteID).confirmPreferAsync() {
        case .paid(let finalized): return finalized
        case .pending(let pending): return try await pending.wait()
        }
    }

    func balance(_ wallet: Wallet) async throws -> UInt64 { try await wallet.totalBalance().value }

    /// An assertion failure must never be swallowed by a catch-all error test.
    func expectError(_ fragments: [String], _ operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected payment rejection: \(fragments)") }
        catch {
            let message = String(describing: error).lowercased()
            XCTAssertTrue(fragments.contains { message.contains($0.lowercased()) }, "Unexpected rejection: \(error)")
        }
    }
}

final class PaymentSafetyIntegrationTests: PaymentFixtureTestCase {
    func testControlledQuoteIsUnpaidUntilExplicitPaymentAndIssuesOnlyOnce() async throws {
        let wallet = try await makeWallet("controlled")
        let quote = try await wallet.mintQuote(paymentMethod: .bolt11, amount: Amount(value: 21), description: nil, extra: nil)
        let unpaid = try await wallet.checkMintQuote(quoteId: quote.id)
        XCTAssertEqual(unpaid.state, .unpaid)
        let before = try await balance(wallet)
        XCTAssertEqual(before, 0)
        await expectError(["not paid", "unpaid", "20001", "Amount undefined"]) {
            _ = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .none, spendingConditions: nil)
        }
        _ = try await wallet.recoverIncompleteSagas()
        _ = try await call(root + "/pay/controlled", method: "POST", body: ["invoice": quote.request])
        _ = try await awaitPaid(wallet, id: quote.id)
        _ = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .none, spendingConditions: nil)
        let issued = try await wallet.checkMintQuote(quoteId: quote.id)
        XCTAssertEqual(issued.state, .issued)
        let sweep = try await wallet.mintUnissuedQuotes()
        XCTAssertEqual(sweep.value, 0)
        let after = try await balance(wallet)
        XCTAssertEqual(after, 21)
    }

    func testBolt11InternalAndExternalPaymentsConserveBalanceAndPersistReceipt() async throws {
        // Nutshell's stock FakeWallet reports every external payment settled
        // before it starts. Use a real internal invoice for this fast native
        // path; the simulator journey also exercises its external payment path.
        for mint in ["controlled", "cdk"] {
            let payer = try await makeWallet(mint)
            let recipient = try await makeWallet(mint)
            try await fund(payer, controlled: mint == "controlled" ? mint : nil)
            let incoming = mint == "controlled"
                ? try await recipient.mintQuote(paymentMethod: .bolt11, amount: Amount(value: 21), description: nil, extra: nil)
                : nil
            let request: String
            if let incoming { request = incoming.request } else { request = try await invoice() }
            let quote = try await payer.meltQuote(method: .bolt11, request: request, options: nil, extra: nil)
            if mint == "controlled" {
                // Nutshell 0.20.1 sends PENDING before its background task
                // persists it. Pace the first status read past that fixture race.
                try await arm("/v1/melt/quote/bolt11/", action: "delay", method: "GET")
            }
            let result = try await melt(payer, quoteID: quote.id)
            XCTAssertEqual(result.state, .paid)
            XCTAssertEqual(result.amount.value, 21)
            let after = try await balance(payer)
            XCTAssertEqual(after, 100 - 21 - result.feePaid.value)
            let receipts = try await payer.listTransactions(direction: .outgoing).filter { $0.quoteId == quote.id }
            XCTAssertEqual(receipts.count, 1)
            XCTAssertEqual(receipts.first?.amount.value, 21)
            XCTAssertEqual(receipts.first?.fee.value, result.feePaid.value)
            if let incoming {
                _ = try await awaitPaid(recipient, id: incoming.id)
                let received = try await recipient.mint(quoteId: incoming.id, amountSplitTarget: .none, spendingConditions: nil)
                XCTAssertEqual(received.reduce(0) { $0 + $1.amount.value }, 21)
            }
        }
    }

    func testLostMeltResponseRecoversWithoutSecondDebit() async throws {
        let payer = try await makeWallet("cdk")
        try await fund(payer)
        let quote = try await payer.meltQuote(method: .bolt11, request: invoice(), options: nil, extra: nil)
        try await arm("/v1/melt/bolt11", action: "lose_response")
        let prepared = try await payer.prepareMelt(quoteId: quote.id)
        // CDK can reconcile internally or surface the transport failure. Both
        // must converge through the same durable saga without a second send.
        do { _ = try await prepared.confirm() } catch { }
        _ = try await payer.recoverIncompleteSagas()
        let status = try await payer.checkMeltQuoteStatus(quoteId: quote.id)
        XCTAssertEqual(status.state, .paid)
        let after = try await balance(payer)
        XCTAssertLessThan(after, 100)
        let recovered = try await reopen(payer)
        _ = try await recovered.recoverIncompleteSagas()
        let reopenedBalance = try await balance(recovered)
        XCTAssertEqual(reopenedBalance, after)
        let receipts = try await recovered.listTransactions(direction: .outgoing).filter { $0.quoteId == quote.id }
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(after + 21 + (receipts.first?.fee.value ?? 0), 100)
        let records = try await call(root)["requests"] as! [[String: Any]]
        XCTAssertTrue(records.contains { $0["fault"] as? String == "lose_response" && $0["forwarded"] as? Bool == true })
    }

    func testLostMintResponseRecoversPaidQuoteExactlyOnce() async throws {
        let wallet = try await makeWallet("controlled")
        let quote = try await paidQuote(wallet, amount: 42, controlled: "controlled")
        try await arm("/v1/mint/bolt11", action: "lose_response")
        do { _ = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .none, spendingConditions: nil) } catch { }
        let recovered = try await reopen(wallet)
        _ = try await recovered.recoverIncompleteSagas()
        _ = try await recovered.mintUnissuedQuotes()
        let after = try await balance(recovered)
        XCTAssertEqual(after, 42)
        let second = try await recovered.mintUnissuedQuotes()
        XCTAssertEqual(second.value, 0)
        let receipts = try await recovered.listTransactions(direction: .incoming).filter { $0.quoteId == quote.id }
        XCTAssertEqual(receipts.count, 1)
        let records = try await call(root)["requests"] as! [[String: Any]]
        XCTAssertTrue(records.contains { $0["fault"] as? String == "lose_response" && $0["forwarded"] as? Bool == true })
    }

    func testInsufficientFundsAndOfflineQuoteDoNotDebit() async throws {
        let wallet = try await makeWallet("controlled")
        try await fund(wallet, controlled: "controlled")
        let quote = try await wallet.meltQuote(method: .bolt11, request: invoice(amount: 101), options: nil, extra: nil)
        await expectError(["insufficient", "not enough"]) { _ = try await wallet.prepareMelt(quoteId: quote.id) }
        try await arm("/v1/melt/quote/bolt11", action: "reject")
        await expectError(["503", "unavailable", "http"]) {
            _ = try await wallet.meltQuote(method: .bolt11, request: self.invoice(), options: nil, extra: nil)
        }
        let after = try await balance(wallet)
        XCTAssertEqual(after, 100)
        let recipient = try await makeWallet("controlled")
        let token = try await send(wallet, amount: 100).confirm(memo: nil)
        let received = try await receive(recipient, token: token)
        XCTAssertEqual(received, 100)
    }

    func testBackendFailureReturnsSpendableFunds() async throws {
        let payer = try await makeWallet("cdk")
        try await fund(payer)
        let request = try await invoice(script: ["pay_invoice_state": "UNPAID", "check_payment_state": "UNPAID", "pay_err": true, "check_err": false])
        let quote = try await payer.meltQuote(method: .bolt11, request: request, options: nil, extra: nil)
        do { _ = try await payer.prepareMelt(quoteId: quote.id).confirm() } catch { }
        _ = try await payer.recoverIncompleteSagas()
        let amount = try await balance(payer)
        XCTAssertEqual(amount, 100)
        let recipient = try await makeWallet("cdk")
        let token = try await send(payer, amount: 100).confirm(memo: nil)
        let received = try await receive(recipient, token: token)
        XCTAssertEqual(received, 100)
    }

    func testPaidBolt11RecoversAfterDatabaseReopenExactlyOnce() async throws {
        let wallet = try await makeWallet("controlled")
        let quote = try await paidQuote(wallet, amount: 42, controlled: "controlled")
        let recovered = try await reopen(wallet)
        let first = try await recovered.mintUnissuedQuotes()
        let second = try await recovered.mintUnissuedQuotes()
        XCTAssertEqual(first.value, 42)
        XCTAssertEqual(second.value, 0)
        let history = try await recovered.listTransactions(direction: .incoming).filter { $0.quoteId == quote.id }
        XCTAssertEqual(history.count, 1)
    }

    func testEcashClaimAfterReopenCannotBeRevokedOrReceivedTwice() async throws {
        let sender = try await makeWallet("controlled")
        let receiver = try await makeWallet("controlled")
        try await fund(sender, controlled: "controlled")
        let prepared = try await send(sender, amount: 21)
        let id = prepared.operationId()
        let token = try await prepared.confirm(memo: "Saved token")
        let reopenedSender = try await reopen(sender)
        let pending = try await reopenedSender.getPendingSends()
        XCTAssertTrue(pending.contains(id))
        let credited = try await receive(receiver, token: token)
        XCTAssertEqual(credited, 21)
        let claimed = try await reopenedSender.checkSendStatus(operationId: id)
        XCTAssertTrue(claimed)
        await expectError(["spent", "claimed", "not found", "completed", "unknown"]) {
            _ = try await reopenedSender.revokeSend(operationId: id)
        }
        await expectError(["spent", "already", "11001"]) { _ = try await self.receive(receiver, token: token) }
        let senderBalance = try await balance(reopenedSender)
        let receiverBalance = try await balance(receiver)
        XCTAssertEqual(senderBalance, 79)
        XCTAssertEqual(receiverBalance, 21)
    }

    func testRevokeUnclaimedTokenRestoresSpendability() async throws {
        let sender = try await makeWallet("controlled")
        let receiver = try await makeWallet("controlled")
        try await fund(sender, controlled: "controlled")
        let prepared = try await send(sender, amount: 21)
        let token = try await prepared.confirm(memo: nil)
        let amount = try await sender.revokeSend(operationId: prepared.operationId())
        XCTAssertEqual(amount.value, 21)
        await expectError(["spent", "already", "11001"]) { _ = try await self.receive(receiver, token: token) }
        let newToken = try await send(sender, amount: 100).confirm(memo: nil)
        let received = try await receive(receiver, token: newToken)
        XCTAssertEqual(received, 100)
    }

    func testFeeChargingMintMaxSendAndReceiveConserveValue() async throws {
        let sender = try await makeWallet("fees")
        let receiver = try await makeWallet("fees")
        try await fund(sender, controlled: "fees")
        let prepared = try await send(sender, amount: 100)
        XCTAssertEqual(prepared.fee().value, 0, "Send max transfers existing proofs without a swap")
        let token = try await prepared.confirm(memo: nil)
        let proofCount = prepared.proofs().count
        let received = try await receive(receiver, token: token)
        XCTAssertGreaterThan(proofCount, 0)
        XCTAssertEqual(received, 100 - UInt64(proofCount), "1000 ppk charges one unit per input proof")
        let senderBalance = try await balance(sender)
        let receiverBalance = try await balance(receiver)
        XCTAssertEqual(senderBalance, 0)
        XCTAssertEqual(receiverBalance, received)
    }

    func testP2PKWrongKeyThenCorrectKeyOnBothMints() async throws {
        let key = nostrGenerateSecretKey()
        let publicKey = try "02" + nostrGetPubkey(nostrSecretKey: key)
        for mint in ["nutshell", "cdk"] {
            let sender = try await makeWallet(mint)
            let receiver = try await makeWallet(mint)
            try await fund(sender)
            let token = try await send(sender, amount: 21, key: publicKey).confirm(memo: nil)
            await expectError(["key", "signature", "witness", "sign", "p2pk"]) {
                _ = try await self.receive(receiver, token: token, keys: [nostrGenerateSecretKey()])
            }
            let before = try await balance(receiver)
            XCTAssertEqual(before, 0)
            let received = try await receive(receiver, token: token, keys: [key])
            XCTAssertEqual(received, 21)
        }
    }

    func testConcurrentReceiversCannotDoubleCredit() async throws {
        let sender = try await makeWallet("controlled")
        let a = try await makeWallet("controlled")
        let b = try await makeWallet("controlled")
        try await fund(sender, controlled: "controlled")
        let token = try await send(sender, amount: 21).confirm(memo: nil)
        async let first = attemptReceive(a, token: token)
        async let second = attemptReceive(b, token: token)
        let results = await [first, second]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let total = try await balance(a) + balance(b)
        XCTAssertEqual(total, 21)
    }

    private func attemptReceive(_ wallet: Wallet, token: Token) async -> Bool {
        do { _ = try await receive(wallet, token: token); return true } catch { return false }
    }
}

/// The expanded matrix is selected explicitly by the full/nightly CI tier.
final class PaymentExtendedIntegrationTests: PaymentFixtureTestCase {
    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAYMENT_TEST_TIER"] == "full", "Full payment tier")
        try await super.setUp()
    }

    func testCashuRequestFixedAndAmountlessHttpDelivery() async throws {
        try await assertRequestDelivery(mint: "controlled")
    }

    // Opt-in reproduction: CDK 0.18 delivers 19 instead of 21 at 1000 ppk.
    // Keep the intended assertion; do not make underpayment a passing contract.
    func testCashuRequestReceiverFeeRegression() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAYMENT_KNOWN_REGRESSIONS"] == "1",
                          "Known CDK 0.18 receiver-fee regression; see CI/payment-tests/README.md")
        try await assertRequestDelivery(mint: "fees")
    }

    private func assertRequestDelivery(mint: String) async throws {
        for amount: UInt64? in [21, nil] {
            let payer = try await makeWallet(mint)
            let receiver = try await makeWallet(mint)
            try await fund(payer, controlled: mint)
            var config: [String: Any] = ["target": fixture + root + "/receive", "mints": [mintURL(mint)]]
            if let amount { config["amount"] = amount }
            let encoded = try await call(root + "/request", method: "POST", body: config)["request"] as! String
            let request = try PaymentRequest.fromString(encoded: encoded)
            let prepared = try await payer.preparePayRequest(paymentRequest: request, customAmount: amount == nil ? Amount(value: 21) : nil)
            try await prepared.confirm()
            let delivered = try await call(root + "/received-token")
            XCTAssertEqual(delivered["id"] as? String, sessionID)
            let token = try Token.decode(encodedToken: delivered["token"] as! String)
            let credited = try await receive(receiver, token: token)
            XCTAssertEqual(credited, 21, "A payment request includes the receiver's redemption fee")
            let left = try await balance(payer)
            XCTAssertLessThanOrEqual(left, 79)
        }
    }

    func testCashuRequestDeliveryFailureLeavesReclaimableToken() async throws {
        let payer = try await makeWallet("controlled")
        try await fund(payer, controlled: "controlled")
        let encoded = try await call(root + "/request", method: "POST", body: ["target": fixture + root + "/unavailable", "amount": 21])["request"] as! String
        let request = try PaymentRequest.fromString(encoded: encoded)
        let prepared = try await payer.preparePayRequest(paymentRequest: request, customAmount: nil)
        do {
            try await prepared.confirm()
            XCTFail("Delivery must fail")
        } catch FfiError.PaymentRequestDeliveryFailed(let operationId, _) {
            let recovered = try await payer.revokeSend(operationId: operationId)
            XCTAssertEqual(recovered.value, 21)
        }
        let after = try await balance(payer)
        XCTAssertEqual(after, 100)
    }

    func testPreparedSendCancellationAndCompetingSpendPreserveFunds() async throws {
        let sender = try await makeWallet("controlled")
        try await fund(sender, controlled: "controlled")
        let prepared = try await send(sender, amount: 80)
        await expectError(["insufficient", "not enough"]) { _ = try await self.send(sender, amount: 80) }
        try await prepared.cancel()
        let balance = try await balance(sender)
        XCTAssertEqual(balance, 100)
        let recipient = try await makeWallet("controlled")
        let token = try await send(sender, amount: 100).confirm(memo: nil)
        let received = try await receive(recipient, token: token)
        XCTAssertEqual(received, 100)
    }

    func testMultipleMintUnitsDoNotCrossCredit() async throws {
        let sat = try await makeWallet("cdk")
        let usd = try await makeWallet("cdk", unit: .usd)
        try await fund(sat, amount: 21)
        try await fund(usd, amount: 125)
        let recipient = try await makeWallet("cdk", unit: .usd)
        let token = try await send(usd, amount: 25).confirm(memo: nil)
        let received = try await receive(recipient, token: token)
        XCTAssertEqual(received, 25)
        let sats = try await balance(sat)
        let dollars = try await balance(usd)
        XCTAssertEqual(sats, 21)
        XCTAssertEqual(dollars, 100)
    }

    func testNwcPaymentLimitReplayAndBalance() async throws {
        let payer = try await makeWallet("cdk")
        try await fund(payer)
        let relay = fixture.replacingOccurrences(of: "http://", with: "ws://") + root + "/relay"
        let service = try NwcService.create(wallet: payer, relays: [relay], serviceSecretKey: nostrGenerateSecretKey(), maxPaymentMsat: 21_000)
        try await service.start()
        do {
            let uri = service.connectionUri()
            let initial = try await call(root + "/nwc", method: "POST", body: ["uri": uri, "method": "get_balance"])
            XCTAssertEqual((initial["result"] as? [String: Any])?["balance"] as? Int, 100_000)
            let rejected = try await call(root + "/nwc", method: "POST", body: ["uri": uri, "method": "pay_invoice", "params": ["invoice": invoice(amount: 22)]])
            XCTAssertEqual((rejected["error"] as? [String: Any])?["code"] as? String, "QUOTA_EXCEEDED")
            let untouched = try await balance(payer)
            XCTAssertEqual(untouched, 100)
            let paid = try await call(root + "/nwc", method: "POST", body: ["uri": uri, "method": "pay_invoice", "params": ["invoice": invoice()], "duplicate": true])
            XCTAssertNotNil(paid["result"])
            XCTAssertNil(paid["timeout"])
            let receipts = try await payer.listTransactions(direction: .outgoing)
            XCTAssertEqual(receipts.count, 1)
            let after = try await balance(payer)
            XCTAssertEqual(after + 21 + receipts[0].fee.value, 100)
            let remote = try await call(root + "/nwc", method: "POST", body: ["uri": uri, "method": "get_balance"])
            XCTAssertEqual((remote["result"] as? [String: Any])?["balance"] as? UInt64, after * 1000)
            let finalReceipts = try await payer.listTransactions(direction: .outgoing)
            XCTAssertEqual(finalReceipts.count, 1)
            try await service.stop()
        } catch {
            try? await service.stop()
            throw error
        }
    }
}
