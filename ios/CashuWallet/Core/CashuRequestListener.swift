import Foundation
import SwiftUI

protocol CashuRequestInboxClient: AnyObject, Sendable {
    func start() async
    func stop() async
}

extension NostrInboxClient: CashuRequestInboxClient {}

/// Preserves the latest lifecycle intent even when the unstructured task for
/// an earlier scene or setting transition has not started yet.
@MainActor
final class CashuRequestListenerLifecycleScheduler {
    enum Intent: Equatable {
        case start
        case stop
    }

    private var requestGeneration: UInt = 0
    private var currentIntent: Intent?
    private var task: Task<Void, Never>?

    @discardableResult
    func submit(
        _ intent: Intent,
        _ operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        if currentIntent == intent, let task {
            return task
        }

        requestGeneration &+= 1
        let submittedGeneration = requestGeneration
        task?.cancel()
        currentIntent = intent

        let submittedTask = Task { @MainActor [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.requestGeneration == submittedGeneration else { return }
            await operation()
            guard self.requestGeneration == submittedGeneration else { return }
            self.currentIntent = nil
            self.task = nil
        }
        task = submittedTask
        return submittedTask
    }

    func invalidate() {
        requestGeneration &+= 1
        task?.cancel()
        currentIntent = nil
        task = nil
    }
}

/// Owns exactly one inbox client across async start/stop/reset races. The
/// candidate is published before its first suspension point so overlapping
/// starts share one owner, while the generation prevents stale completions
/// from becoming running again after a wallet boundary.
@MainActor
final class CashuRequestListenerClientSlot {
    private var generation: UInt = 0
    private var client: (any CashuRequestInboxClient)?
    private var retiringClients: [ObjectIdentifier: any CashuRequestInboxClient] = [:]
    private var retirementWaiters: [CheckedContinuation<Void, Never>] = []
    private let onRunningChange: (Bool) -> Void

    private(set) var isRunning = false

    init(onRunningChange: @escaping (Bool) -> Void = { _ in }) {
        self.onRunningChange = onRunningChange
    }

    @discardableResult
    func start(
        makeClient: (UInt) -> any CashuRequestInboxClient
    ) async -> Bool {
        guard !Task.isCancelled, client == nil else { return false }
        await waitUntilRetired()
        guard !Task.isCancelled, client == nil else { return false }

        generation &+= 1
        let startGeneration = generation
        let candidate = makeClient(startGeneration)
        client = candidate

        await candidate.start()

        let stillOwnsCandidate: Bool
        if let current = client {
            stillOwnsCandidate = generation == startGeneration
                && ObjectIdentifier(current) == ObjectIdentifier(candidate)
        } else {
            stillOwnsCandidate = false
        }
        guard !Task.isCancelled, stillOwnsCandidate else {
            if stillOwnsCandidate {
                let displaced = invalidate()
                await retireAndWaitForAll(displaced)
            }
            return false
        }

        setRunning(true)
        return true
    }

    /// Event callbacks capture the generation that created their client. A
    /// stop, reset, or replacement invalidates that ownership synchronously,
    /// before the old client's asynchronous shutdown can finish.
    func owns(_ candidateGeneration: UInt) -> Bool {
        generation == candidateGeneration && client != nil
    }

    /// Invalidates callback ownership synchronously and returns the displaced
    /// client so callers can choose whether to await or detach its shutdown.
    @discardableResult
    func invalidate() -> (any CashuRequestInboxClient)? {
        generation &+= 1
        let previous = client
        client = nil
        setRunning(false)
        return previous
    }

    func stop() async {
        let previous = invalidate()
        await retireAndWaitForAll(previous)
    }

    func reset() {
        guard let previous = invalidate() else { return }
        let identifier = beginRetirement(previous)
        Task { [weak self] in
            await previous.stop()
            self?.finishRetirement(identifier)
        }
    }

    private func retire(_ retiringClient: any CashuRequestInboxClient) async {
        let identifier = beginRetirement(retiringClient)
        await retiringClient.stop()
        finishRetirement(identifier)
    }

    func retireAndWaitForAll(
        _ displacedClient: (any CashuRequestInboxClient)?
    ) async {
        if let displacedClient {
            await retire(displacedClient)
        }
        await waitUntilRetired()
    }

    private func beginRetirement(
        _ retiringClient: any CashuRequestInboxClient
    ) -> ObjectIdentifier {
        let identifier = ObjectIdentifier(retiringClient)
        retiringClients[identifier] = retiringClient
        return identifier
    }

    private func finishRetirement(_ identifier: ObjectIdentifier) {
        retiringClients[identifier] = nil
        guard retiringClients.isEmpty else { return }

        let waiters = retirementWaiters
        retirementWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func waitUntilRetired() async {
        guard !retiringClients.isEmpty else { return }
        await withCheckedContinuation { continuation in
            retirementWaiters.append(continuation)
        }
    }

    private func setRunning(_ running: Bool) {
        guard isRunning != running else { return }
        isRunning = running
        onRunningChange(running)
    }
}

/// A non-cancelling drain for wallet work owned by the request listener.
///
/// A wallet boundary first closes this gate, then waits for every lease that
/// was already admitted. This is deliberately different from task
/// cancellation: once CDK starts redeeming a token, cancellation cannot prove
/// whether the mint consumed it, so the complete receive workflow (including
/// transaction attribution and balance/history refreshes) must finish before
/// the wallet database can be moved or removed.
@MainActor
final class CashuRequestListenerWorkGate {
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var acceptsNewWork = true
    private(set) var activeWorkCount = 0

    func begin() -> Bool {
        guard acceptsNewWork else { return false }
        activeWorkCount += 1
        return true
    }

    func end() {
        guard activeWorkCount > 0 else {
            assertionFailure("Cashu request listener work gate underflow")
            return
        }
        activeWorkCount -= 1
        guard activeWorkCount == 0 else { return }

        let waiters = drainWaiters
        drainWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Synchronous so no new held-payment or callback work can enter between
    /// client invalidation and the first suspension of wallet reset.
    func suspend() {
        acceptsNewWork = false
    }

    func waitUntilDrained() async {
        guard activeWorkCount > 0 else { return }
        await withCheckedContinuation { continuation in
            drainWaiters.append(continuation)
        }
    }

    /// A new wallet explicitly reopens the gate only after it is attached.
    func resume() {
        guard activeWorkCount == 0 else { return }
        acceptsNewWork = true
    }
}

/// Mirrors Android's processed-event tracker: terminal gift wraps persist in a
/// bounded history, while an in-flight set prevents the same relay event from
/// entering a second receive workflow before the first one finishes.
@MainActor
final class ProcessedNIP17EventTracker {
    private let load: () -> [String]
    private let save: ([String]) -> Void
    private let maxProcessedIds: Int
    private var processedIds: Set<String> = []
    private var processedOrder: [String] = []
    private var inFlightIds: Set<String> = []

    init(
        load: @escaping () -> [String],
        save: @escaping ([String]) -> Void,
        maxProcessedIds: Int = 1_000
    ) {
        precondition(maxProcessedIds > 0, "maxProcessedIds must be positive")
        self.load = load
        self.save = save
        self.maxProcessedIds = maxProcessedIds
    }

    func reload() {
        var seen: Set<String> = []
        let stored = load().filter { seen.insert($0).inserted }
        processedOrder = Array(stored.suffix(maxProcessedIds))
        processedIds = Set(processedOrder)
        inFlightIds = []
    }

    func clear() {
        processedIds = []
        processedOrder = []
        inFlightIds = []
    }

    func begin(_ eventId: String) -> Bool {
        guard !processedIds.contains(eventId),
              inFlightIds.insert(eventId).inserted else { return false }
        return true
    }

    func finish(_ eventId: String, terminalOutcome: Bool) {
        inFlightIds.remove(eventId)
        guard terminalOutcome, processedIds.insert(eventId).inserted else { return }

        processedOrder.append(eventId)
        if processedOrder.count > maxProcessedIds {
            let removed = processedOrder.removeFirst()
            processedIds.remove(removed)
        }
        save(processedOrder)
    }
}

/// NUT-18 receive-side listener. Foreground-only: opens a NIP-17 relay subscription
/// at app launch, decrypts gift wraps, parses PaymentRequestPayload from the inner
/// rumor, and forwards to the auto-claim path in WalletManager.
///
/// Payments that can't claim silently (auto-claim off, or the mint isn't
/// tracked yet) are persisted as `PendingReceiveToken`s — the same store the
/// "Receive Later" flow uses — so they survive restarts, show up in History as
/// claimable pending rows, and don't depend on the relay lookback window.
@MainActor
final class CashuRequestListener: ObservableObject {
    static let shared = CashuRequestListener()

    @Published private(set) var isRunning: Bool = false

    /// The most recently held payment, for the one-shot approval prompt at app
    /// root. Clearing it is UI-only — the payment itself lives in the
    /// pending-receive store and stays claimable from History.
    @Published private(set) var heldForApproval: PendingReceiveToken?

    private lazy var clientSlot = CashuRequestListenerClientSlot { [weak self] running in
        self?.isRunning = running
    }
    private let lifecycleScheduler = CashuRequestListenerLifecycleScheduler()
    private let workGate = CashuRequestListenerWorkGate()
    private weak var walletManager: WalletManager?

    private enum WalletBoundaryState: Equatable {
        case active
        case resetting
        case suspended
    }

    private var walletBoundaryState: WalletBoundaryState = .active
    private var walletBoundaryResetWaiters: [CheckedContinuation<Void, Never>] = []

    // Gift wraps are fetched over a generous fixed lookback window. NIP-59
    // backdates each gift wrap's `created_at` up to ~2 days, so a tight or
    // forward-advancing `since` floor silently drops later payments. We instead
    // re-scan a wide window every start and prevent re-processing by remembering
    // the gift-wrap event ids we've already handled.
    private let lookbackWindow: TimeInterval = 7 * 24 * 60 * 60
    private let processedIdsKey = StorageKeys.cashuRequestsProcessedNIP17Ids
    private lazy var processedEvents = ProcessedNIP17EventTracker(
        load: {
            UserDefaults.standard.stringArray(
                forKey: StorageKeys.cashuRequestsProcessedNIP17Ids
            ) ?? []
        },
        save: {
            UserDefaults.standard.set(
                $0,
                forKey: StorageKeys.cashuRequestsProcessedNIP17Ids
            )
        }
    )

    private init() {}

    func attach(walletManager: WalletManager) {
        self.walletManager = walletManager
        guard walletBoundaryState != .resetting else { return }
        walletBoundaryState = .active
        workGate.resume()
    }

    func requestStart() {
        lifecycleScheduler.submit(.start) { [weak self] in
            await self?.start()
        }
    }

    func requestStop() {
        lifecycleScheduler.submit(.stop) { [weak self] in
            await self?.stop()
        }
    }

    func start() async {
        guard walletBoundaryState == .active, workGate.acceptsNewWork else {
            AppLogger.wallet.notice("CashuRequestListener: wallet boundary in progress — not starting")
            return
        }
        guard SettingsManager.shared.enablePaymentRequests else {
            AppLogger.wallet.notice("CashuRequestListener: payment requests disabled in settings — not starting")
            await clientSlot.stop()
            return
        }
        let nostr = NostrService.shared
        guard nostr.isInitialized,
              !nostr.publicKeyHex.isEmpty,
              let privHex = nostr.getPrivateKeyHex(),
              let privateKey = Data(hex: privHex) else {
            AppLogger.wallet.error("CashuRequestListener: NostrService not initialized")
            return
        }
        let relays = CashuRequestNostrReadiness.normalizedRelays(
            SettingsManager.shared.nostrRelays
        )
        guard !relays.isEmpty else {
            AppLogger.wallet.error("CashuRequestListener: no Nostr relays configured — cannot receive Cashu Request payments")
            return
        }
        let since = Int64(Date().timeIntervalSince1970 - lookbackWindow)

        let pubkeyHex = nostr.publicKeyHex
        let started = await clientSlot.start { generation in
            processedEvents.reload()
            return NostrInboxClient(
                pubkeyHex: pubkeyHex,
                relays: relays,
                since: since
            ) { [weak self] event in
                await self?.handleTracked(
                    event: event,
                    recipientPrivateKey: privateKey,
                    generation: generation
                )
            }
        }
        guard started else { return }
        AppLogger.wallet.notice(
            "CashuRequestListener: started relays=\(relays.count, privacy: .public) pubkey=\(WalletOperationCoordinator.privacySafeIdentifier(pubkeyHex), privacy: .public) since=\(since, privacy: .public)"
        )
    }

    func stop() async {
        await clientSlot.stop()
    }

    /// Quiesce listener-owned wallet mutations before forgetting the previous
    /// wallet's inbox state. The gate remains suspended until `attach` installs
    /// the next wallet, preventing foreground/start tasks from reopening intake
    /// while lifecycle code moves or removes the database.
    func resetForWalletBoundary() async {
        lifecycleScheduler.invalidate()
        switch walletBoundaryState {
        case .resetting:
            // Waiting only for active wallet work is insufficient: the reset
            // owner may still be stopping the client or clearing listener state.
            await withCheckedContinuation { continuation in
                walletBoundaryResetWaiters.append(continuation)
            }
            return
        case .suspended:
            return
        case .active:
            break
        }

        walletBoundaryState = .resetting

        // Invalidate callback ownership before the first await. A callback that
        // has not entered the gate is now rejected; one already inside is
        // allowed to finish its full, potentially ambiguous receive workflow.
        let previousClient = clientSlot.invalidate()
        workGate.suspend()

        await clientSlot.retireAndWaitForAll(previousClient)
        await workGate.waitUntilDrained()

        processedEvents.clear()
        heldForApproval = nil
        UserDefaults.standard.removeObject(forKey: processedIdsKey)
        walletBoundaryState = .suspended

        let resetWaiters = walletBoundaryResetWaiters
        walletBoundaryResetWaiters.removeAll()
        for waiter in resetWaiters {
            waiter.resume()
        }
    }

    // MARK: - Event handling

    private func handleTracked(
        event: NostrIncomingEvent,
        recipientPrivateKey: Data,
        generation: UInt
    ) async {
        guard clientSlot.owns(generation), workGate.begin() else { return }
        defer { workGate.end() }
        await handle(
            event: event,
            recipientPrivateKey: recipientPrivateKey,
            generation: generation
        )
    }

    private func handle(
        event: NostrIncomingEvent,
        recipientPrivateKey: Data,
        generation: UInt
    ) async {
        guard clientSlot.owns(generation) else { return }
        guard event.kind == 1059 else { return }
        guard processedEvents.begin(event.id) else { return }
        var terminalOutcome = false
        defer {
            processedEvents.finish(
                event.id,
                terminalOutcome: terminalOutcome && clientSlot.owns(generation)
            )
        }
        AppLogger.wallet.notice(
            "CashuRequestListener: gift wrap received event=\(WalletOperationCoordinator.privacySafeIdentifier(event.id), privacy: .public) created_at=\(event.createdAt, privacy: .public)"
        )

        let rumor: NostrRumor
        do {
            rumor = try NIP17.unwrap(giftWrap: event, recipientPrivateKey: recipientPrivateKey)
        } catch {
            // Not encrypted for us (or an unrelated DM) — it can never succeed,
            // so mark it handled and stop reconsidering it.
            AppLogger.wallet.notice(
                "CashuRequestListener: NIP-17 unwrap failed event=\(WalletOperationCoordinator.privacySafeIdentifier(event.id), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            terminalOutcome = true
            return
        }
        guard rumor.kind == 14 else {
            terminalOutcome = true
            return
        }
        switch await tryClaim(
            rumorContent: rumor.content,
            eventId: event.id,
            generation: generation
        ) {
        case .claimed, .unclaimable, .held:
            // .held: the payment is persisted in the pending-receive store —
            // that store owns it now, so the relay event is done.
            terminalOutcome = true
        case .transientFailure, .stale:
            break  // leave unmarked so a later run retries
        }
    }

    private enum ClaimOutcome {
        case claimed            // redeemed successfully
        case unclaimable        // malformed / un-redeemable payload — never retry
        case transientFailure   // redeem failed (mint/network) — retry later
        case held               // persisted for an explicit user decision
        case stale              // callback belongs to a stopped/replaced wallet
    }

    private func tryClaim(
        rumorContent content: String,
        eventId: String,
        generation: UInt
    ) async -> ClaimOutcome {
        guard clientSlot.owns(generation) else { return .stale }
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unclaimable
        }
        // NUT-18 PaymentRequestPayload:
        // { "id": "<request_uuid>", "memo": "...", "mint": "<url>", "unit": "sat", "proofs": [ ... ] }
        let requestId = json["id"] as? String
        guard let mintUrl = json["mint"] as? String,
              let proofs = json["proofs"] as? [[String: Any]] else {
            AppLogger.wallet.notice("CashuRequestListener: malformed PaymentRequestPayload")
            return .unclaimable
        }
        let unit = (json["unit"] as? String) ?? "sat"
        let memo = json["memo"] as? String
        guard let tokenString = buildV3Token(mint: mintUrl, proofs: proofs, unit: unit, memo: memo) else {
            AppLogger.wallet.notice("CashuRequestListener: could not build token from payload")
            return .unclaimable
        }
        guard let walletManager else {
            AppLogger.wallet.error("CashuRequestListener: walletManager not attached")
            return .transientFailure
        }

        // Silent claiming needs both: auto-claim enabled, and a mint the user
        // already trusts (claiming creates a CDK wallet for the mint and adds
        // it to the tracked list — never do that without consent). Everything
        // else is persisted for an explicit decision on the receive screen.
        let mintKnown = walletManager.isMintKnown(url: mintUrl)
        let autoClaim = SettingsManager.shared.receivePaymentRequestsAutomatically
        guard autoClaim && mintKnown else {
            return await holdForApproval(
                tokenString: tokenString,
                requestId: requestId,
                mintUrl: mintUrl,
                amount: proofsTotalAmount(proofs),
                unit: PaymentRequestDecoder.unitDescription(PaymentRequestDecoder.currencyUnit(from: unit)),
                memo: memo,
                reason: mintKnown ? "auto-claim off" : "unknown mint",
                generation: generation
            )
        }

        return await claimNow(
            tokenString: tokenString,
            requestId: requestId,
            generation: generation
        )
    }

    private func claimNow(
        tokenString: String,
        requestId: String?,
        generation: UInt
    ) async -> ClaimOutcome {
        guard clientSlot.owns(generation) else { return .stale }
        guard let walletManager else {
            AppLogger.wallet.error("CashuRequestListener: walletManager not attached")
            return .transientFailure
        }
        do {
            // A gift wrap can arrive exactly as the app backgrounds; hold a background-task
            // assertion so this SQLite-writing redeem finishes before suspension.
            _ = try await withBackgroundWriteAssertion("cashu-request-claim") {
                try await walletManager.receiveCashuRequestPayment(
                    tokenString: tokenString,
                    requestId: requestId
                )
            }
            guard clientSlot.owns(generation) else { return .stale }
            let requestHash = requestId.map(WalletOperationCoordinator.privacySafeIdentifier) ?? "none"
            AppLogger.wallet.notice(
                "CashuRequestListener: claimed payment request=\(requestHash, privacy: .public)"
            )
            return .claimed
        } catch {
            guard clientSlot.owns(generation) else { return .stale }
            AppLogger.wallet.error(
                "CashuRequestListener: redeem failed (will retry) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            return .transientFailure
        }
    }

    // MARK: - Held payments (persisted approval queue)

    /// Cap on payments held in the pending-receive store by this listener, so
    /// a spammer pushing payloads from throwaway mints can't grow UserDefaults
    /// without bound. Overflow events stay unprocessed and are re-offered on a
    /// later scan once the backlog drains. Only listener-held entries count —
    /// manually parked "Receive Later" tokens are the user's own business.
    private static let maxHeldPayments = 50

    /// Persist a payment that needs an explicit user decision and surface the
    /// one-shot approval prompt. Returns `.transientFailure` (leaving the
    /// relay event unprocessed) when the payment can't be persisted, so it is
    /// retried later rather than lost.
    private func holdForApproval(
        tokenString: String,
        requestId: String?,
        mintUrl: String,
        amount: UInt64,
        unit: String,
        memo: String?,
        reason: String,
        generation: UInt
    ) async -> ClaimOutcome {
        guard clientSlot.owns(generation) else { return .stale }
        guard let walletManager else { return .transientFailure }

        let existing = walletManager.pendingReceiveTokens
        // Same proofs delivered under a second event id (relay echo, resend):
        // already held, nothing to add.
        if existing.contains(where: { $0.token == tokenString }) {
            return .held
        }
        guard existing.filter({ $0.cashuRequestId != nil }).count < Self.maxHeldPayments else {
            AppLogger.wallet.notice("CashuRequestListener: held-payment backlog full — deferring")
            return .transientFailure
        }

        // A non-nil cashuRequestId marks the entry as listener-held (vs a
        // manually parked "Receive Later" token); an empty string means the
        // payload carried no request id.
        let pending = PendingReceiveToken(
            tokenId: UUID().uuidString,
            token: tokenString,
            amount: amount,
            unit: unit,
            date: Date(),
            mintUrl: mintUrl,
            cashuRequestId: requestId ?? "",
            memo: memo
        )
        walletManager.savePendingReceiveToken(pending)
        heldForApproval = pending
        AppLogger.wallet.notice(
            "CashuRequestListener: payment held for approval resource=\(WalletOperationCoordinator.privacySafeIdentifier(mintUrl), privacy: .public) reason=\(reason, privacy: .public)"
        )
        await walletManager.loadTransactions()
        return clientSlot.owns(generation) ? .held : .stale
    }

    /// User accepted (from the approval prompt): claim the held payment —
    /// this adds its mint to the wallet if needed — then silently claim any
    /// other held payments that no longer need a decision.
    func claimHeldPayment(_ pending: PendingReceiveToken) async throws -> UInt64 {
        guard workGate.begin() else { throw WalletError.notInitialized }
        defer { workGate.end() }
        guard let walletManager else { throw WalletError.notInitialized }
        let amount = try await withBackgroundWriteAssertion("cashu-request-claim") {
            try await walletManager.claimPendingReceiveToken(pending)
        }
        if heldForApproval?.tokenId == pending.tokenId { heldForApproval = nil }
        AppLogger.wallet.notice(
            "CashuRequestListener: user approved claim resource=\(WalletOperationCoordinator.privacySafeIdentifier(pending.mintUrl), privacy: .public)"
        )
        if workGate.acceptsNewWork {
            await claimEligibleHeldPaymentsAssumingTrackedWork()
        }
        return amount
    }

    /// User declined: drop the held payment permanently.
    func declineHeldPayment(_ pending: PendingReceiveToken) {
        guard workGate.acceptsNewWork else { return }
        walletManager?.removePendingReceiveToken(tokenId: pending.tokenId)
        if heldForApproval?.tokenId == pending.tokenId { heldForApproval = nil }
        AppLogger.wallet.notice(
            "CashuRequestListener: user declined payment resource=\(WalletOperationCoordinator.privacySafeIdentifier(pending.mintUrl), privacy: .public)"
        )
        Task { [weak self] in
            await self?.refreshTransactionsAfterHeldPaymentChange()
        }
    }

    /// "Not now": hide the prompt. The payment stays in the pending-receive
    /// store and remains claimable from its History row.
    func dismissHeldPayment() {
        heldForApproval = nil
    }

    /// Claim held payments that no longer need a decision: auto-claim is on
    /// and the mint is known (the user just approved a payment from that mint,
    /// added the mint manually, or re-enabled auto-claim). No-op in manual
    /// mode — there every payment gets its own confirmation. Only touches
    /// listener-held entries, never manually parked "Receive Later" tokens.
    func claimEligibleHeldPayments() async {
        guard workGate.begin() else { return }
        defer { workGate.end() }
        await claimEligibleHeldPaymentsAssumingTrackedWork()
    }

    private func claimEligibleHeldPaymentsAssumingTrackedWork() async {
        guard SettingsManager.shared.receivePaymentRequestsAutomatically else { return }
        guard let walletManager else { return }
        let eligible = walletManager.pendingReceiveTokens.filter {
            $0.cashuRequestId != nil && walletManager.isMintKnown(url: $0.mintUrl)
        }
        for pending in eligible {
            // Finish an already-started receive, but never begin another after
            // a wallet boundary has requested the drain.
            guard workGate.acceptsNewWork else { return }
            do {
                _ = try await withBackgroundWriteAssertion("cashu-request-claim") {
                    try await walletManager.claimPendingReceiveToken(pending)
                }
                if heldForApproval?.tokenId == pending.tokenId { heldForApproval = nil }
                AppLogger.wallet.notice(
                    "CashuRequestListener: claimed held payment resource=\(WalletOperationCoordinator.privacySafeIdentifier(pending.mintUrl), privacy: .public)"
                )
            } catch {
                AppLogger.wallet.error(
                    "CashuRequestListener: held-payment claim failed (stays claimable in History) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }
    }

    private func refreshTransactionsAfterHeldPaymentChange() async {
        guard workGate.begin() else { return }
        defer { workGate.end() }
        await walletManager?.loadTransactions()
    }

    private func proofsTotalAmount(_ proofs: [[String: Any]]) -> UInt64 {
        proofs.reduce(UInt64(0)) { total, proof in
            let amount = (proof["amount"] as? NSNumber)?.uint64Value ?? 0
            return total &+ amount
        }
    }

    /// Build a NUT-00 V3 cashu token string from a mint + proofs payload.
    /// Format: `cashuA` + base64url(no padding)(JSON({token:[{mint, proofs}], unit, memo})).
    private func buildV3Token(mint: String, proofs: [[String: Any]], unit: String?, memo: String?) -> String? {
        var token: [String: Any] = ["token": [["mint": mint, "proofs": proofs]]]
        if let unit { token["unit"] = unit }
        if let memo { token["memo"] = memo }
        guard let data = try? JSONSerialization.data(withJSONObject: token) else { return nil }
        return "cashuA" + Base64URL.encode(data)
    }
}
