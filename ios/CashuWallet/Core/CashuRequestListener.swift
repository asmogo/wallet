import Foundation
import SwiftUI

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

    private var client: NostrInboxClient?
    private weak var walletManager: WalletManager?

    // Gift wraps are fetched over a generous fixed lookback window. NIP-59
    // backdates each gift wrap's `created_at` up to ~2 days, so a tight or
    // forward-advancing `since` floor silently drops later payments. We instead
    // re-scan a wide window every start and prevent re-processing by remembering
    // the gift-wrap event ids we've already handled.
    private let lookbackWindow: TimeInterval = 7 * 24 * 60 * 60
    private let processedIdsKey = StorageKeys.cashuRequestsProcessedNIP17Ids
    private let maxProcessedIds = 1000
    private var processedIds: Set<String> = []
    private var processedOrder: [String] = []

    private init() {}

    func attach(walletManager: WalletManager) {
        self.walletManager = walletManager
    }

    func start() async {
        guard !isRunning else { return }
        guard SettingsManager.shared.enablePaymentRequests else {
            AppLogger.wallet.notice("CashuRequestListener: payment requests disabled in settings — not starting")
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
        loadProcessedIds()
        let since = Int64(Date().timeIntervalSince1970 - lookbackWindow)

        let pubkeyHex = nostr.publicKeyHex
        let client = NostrInboxClient(
            pubkeyHex: pubkeyHex,
            relays: relays,
            since: since
        ) { [weak self] event in
            await self?.handle(event: event, recipientPrivateKey: privateKey)
        }
        self.client = client
        await client.start()
        isRunning = true
        AppLogger.wallet.notice("CashuRequestListener: started on \(relays.count) relays, pubkey=\(String(pubkeyHex.prefix(8)), privacy: .public), since=\(since)")
    }

    func stop() async {
        guard let client else { return }
        await client.stop()
        self.client = nil
        isRunning = false
    }

    /// Forget processed gift-wrap ids at a wallet boundary. The ids belong to
    /// the previous wallet's Nostr inbox; a new wallet has a new keypair, and a
    /// re-restored seed should re-attempt claims rather than skip them.
    func resetForWalletBoundary() {
        let oldClient = client
        client = nil
        isRunning = false
        processedIds = []
        processedOrder = []
        heldForApproval = nil
        UserDefaults.standard.removeObject(forKey: processedIdsKey)
        Task { await oldClient?.stop() }
    }

    // MARK: - Event handling

    private func handle(event: NostrIncomingEvent, recipientPrivateKey: Data) async {
        guard event.kind == 1059 else { return }
        guard !processedIds.contains(event.id) else { return }
        AppLogger.wallet.notice("CashuRequestListener: gift wrap received id=\(String(event.id.prefix(8)), privacy: .public) createdAt=\(event.createdAt)")

        let rumor: NostrRumor
        do {
            rumor = try NIP17.unwrap(giftWrap: event, recipientPrivateKey: recipientPrivateKey)
        } catch {
            // Not encrypted for us (or an unrelated DM) — it can never succeed,
            // so mark it handled and stop reconsidering it.
            AppLogger.wallet.notice("CashuRequestListener: NIP-17 unwrap failed for \(String(event.id.prefix(8)), privacy: .public): \(String(describing: error), privacy: .public)")
            markProcessed(event.id)
            return
        }
        guard rumor.kind == 14 else {
            markProcessed(event.id)
            return
        }
        switch await tryClaim(rumorContent: rumor.content, eventId: event.id) {
        case .claimed, .unclaimable, .held:
            // .held: the payment is persisted in the pending-receive store —
            // that store owns it now, so the relay event is done.
            markProcessed(event.id)
        case .transientFailure:
            break  // leave unmarked so a later run retries
        }
    }

    private enum ClaimOutcome {
        case claimed            // redeemed successfully
        case unclaimable        // malformed / un-redeemable payload — never retry
        case transientFailure   // redeem failed (mint/network) — retry later
        case held               // persisted for an explicit user decision
    }

    private func tryClaim(rumorContent content: String, eventId: String) async -> ClaimOutcome {
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
            return holdForApproval(
                tokenString: tokenString,
                requestId: requestId,
                mintUrl: mintUrl,
                amount: proofsTotalAmount(proofs),
                unit: PaymentRequestDecoder.unitDescription(PaymentRequestDecoder.currencyUnit(from: unit)),
                memo: memo,
                reason: mintKnown ? "auto-claim off" : "unknown mint"
            )
        }

        return await claimNow(tokenString: tokenString, requestId: requestId)
    }

    private func claimNow(tokenString: String, requestId: String?) async -> ClaimOutcome {
        guard let walletManager else {
            AppLogger.wallet.error("CashuRequestListener: walletManager not attached")
            return .transientFailure
        }
        do {
            // A gift wrap can arrive exactly as the app backgrounds; hold a background-task
            // assertion so this SQLite-writing redeem finishes before suspension.
            let amount = try await withBackgroundWriteAssertion("cashu-request-claim") {
                try await walletManager.receiveCashuRequestPayment(
                    tokenString: tokenString,
                    requestId: requestId
                )
            }
            AppLogger.wallet.notice("CashuRequestListener: claimed \(amount) sat for request \(requestId ?? "—", privacy: .public)")
            return .claimed
        } catch {
            AppLogger.wallet.error("CashuRequestListener: redeem failed (will retry): \(String(describing: error), privacy: .public)")
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
        reason: String
    ) -> ClaimOutcome {
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
        AppLogger.wallet.notice("CashuRequestListener: payment from \(mintUrl, privacy: .public) held for approval (\(reason, privacy: .public))")
        Task { await walletManager.loadTransactions() }
        return .held
    }

    /// User accepted (from the approval prompt): claim the held payment —
    /// this adds its mint to the wallet if needed — then silently claim any
    /// other held payments that no longer need a decision.
    func claimHeldPayment(_ pending: PendingReceiveToken) async throws -> UInt64 {
        guard let walletManager else { throw WalletError.notInitialized }
        let amount = try await withBackgroundWriteAssertion("cashu-request-claim") {
            try await walletManager.claimPendingReceiveToken(pending)
        }
        if heldForApproval?.tokenId == pending.tokenId { heldForApproval = nil }
        AppLogger.wallet.notice("CashuRequestListener: user approved claim of \(amount) sat from \(pending.mintUrl, privacy: .public)")
        await claimEligibleHeldPayments()
        return amount
    }

    /// User declined: drop the held payment permanently.
    func declineHeldPayment(_ pending: PendingReceiveToken) {
        walletManager?.removePendingReceiveToken(tokenId: pending.tokenId)
        if heldForApproval?.tokenId == pending.tokenId { heldForApproval = nil }
        AppLogger.wallet.notice("CashuRequestListener: user declined payment from \(pending.mintUrl, privacy: .public)")
        Task { await walletManager?.loadTransactions() }
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
        guard SettingsManager.shared.receivePaymentRequestsAutomatically else { return }
        guard let walletManager else { return }
        let eligible = walletManager.pendingReceiveTokens.filter {
            $0.cashuRequestId != nil && walletManager.isMintKnown(url: $0.mintUrl)
        }
        for pending in eligible {
            do {
                let amount = try await withBackgroundWriteAssertion("cashu-request-claim") {
                    try await walletManager.claimPendingReceiveToken(pending)
                }
                if heldForApproval?.tokenId == pending.tokenId { heldForApproval = nil }
                AppLogger.wallet.notice("CashuRequestListener: claimed held payment of \(amount) sat from \(pending.mintUrl, privacy: .public)")
            } catch {
                AppLogger.wallet.error("CashuRequestListener: held-payment claim failed (stays claimable in History): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func proofsTotalAmount(_ proofs: [[String: Any]]) -> UInt64 {
        proofs.reduce(UInt64(0)) { total, proof in
            let amount = (proof["amount"] as? NSNumber)?.uint64Value ?? 0
            return total &+ amount
        }
    }

    // MARK: - De-duplication

    private func loadProcessedIds() {
        let stored = UserDefaults.standard.stringArray(forKey: processedIdsKey) ?? []
        processedOrder = stored
        processedIds = Set(stored)
    }

    private func markProcessed(_ id: String) {
        guard processedIds.insert(id).inserted else { return }
        processedOrder.append(id)
        if processedOrder.count > maxProcessedIds {
            let overflow = processedOrder.count - maxProcessedIds
            for removed in processedOrder.prefix(overflow) { processedIds.remove(removed) }
            processedOrder.removeFirst(overflow)
        }
        UserDefaults.standard.set(processedOrder, forKey: processedIdsKey)
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
