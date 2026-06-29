import Foundation
import SwiftUI

/// NUT-18 receive-side listener. Foreground-only: opens a NIP-17 relay subscription
/// at app launch, decrypts gift wraps, parses PaymentRequestPayload from the inner
/// rumor, and forwards to the auto-claim path in WalletManager.
@MainActor
final class CashuRequestListener: ObservableObject {
    static let shared = CashuRequestListener()

    @Published private(set) var isRunning: Bool = false

    private var client: NostrInboxClient?
    private weak var walletManager: WalletManager?

    // Gift wraps are fetched over a generous fixed lookback window. NIP-59
    // backdates each gift wrap's `created_at` up to ~2 days, so a tight or
    // forward-advancing `since` floor silently drops later payments. We instead
    // re-scan a wide window every start and prevent re-processing by remembering
    // the gift-wrap event ids we've already handled.
    private let lookbackWindow: TimeInterval = 7 * 24 * 60 * 60
    private let processedIdsKey = "cashuRequests.nip17.processedIds.v1"
    private let maxProcessedIds = 1000
    private var processedIds: Set<String> = []
    private var processedOrder: [String] = []

    private init() {}

    func attach(walletManager: WalletManager) {
        self.walletManager = walletManager
    }

    func start() async {
        guard !isRunning else { return }
        let nostr = NostrService.shared
        guard nostr.isInitialized,
              !nostr.publicKeyHex.isEmpty,
              let privHex = nostr.getPrivateKeyHex(),
              let privateKey = Data(hex: privHex) else {
            AppLogger.wallet.error("CashuRequestListener: NostrService not initialized")
            return
        }
        let relays = SettingsManager.shared.nostrRelays
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
        switch await tryClaim(rumorContent: rumor.content) {
        case .claimed, .unclaimable:
            markProcessed(event.id)
        case .transientFailure:
            break  // leave unmarked so a later run retries
        }
    }

    private enum ClaimOutcome {
        case claimed            // redeemed successfully
        case unclaimable        // malformed / un-redeemable payload — never retry
        case transientFailure   // redeem failed (mint/network) — retry later
    }

    private func tryClaim(rumorContent content: String) async -> ClaimOutcome {
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
