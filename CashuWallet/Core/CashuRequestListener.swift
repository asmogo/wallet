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
    private let sinceKey = "cashuRequests.nip17.since.v1"

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
        guard !relays.isEmpty else { return }
        let since = UserDefaults.standard.object(forKey: sinceKey) as? Int64
            ?? Int64(Date().timeIntervalSince1970) - (48 * 60 * 60)  // 48h backfill on first run

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
        AppLogger.wallet.info("CashuRequestListener: started on \(relays.count) relays since=\(since)")
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
        UserDefaults.standard.set(event.createdAt, forKey: sinceKey)

        let rumor: NostrRumor
        do {
            rumor = try NIP17.unwrap(giftWrap: event, recipientPrivateKey: recipientPrivateKey)
        } catch {
            AppLogger.wallet.debug("CashuRequestListener: NIP-17 unwrap failed: \(String(describing: error))")
            return
        }
        guard rumor.kind == 14 else { return }
        await tryClaim(rumorContent: rumor.content)
    }

    private func tryClaim(rumorContent content: String) async {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        // NUT-18 PaymentRequestPayload:
        // { "id": "<request_uuid>", "memo": "...", "mint": "<url>", "unit": "sat", "proofs": [ ... ] }
        let requestId = json["id"] as? String
        guard let mintUrl = json["mint"] as? String,
              let proofs = json["proofs"] as? [[String: Any]] else {
            AppLogger.wallet.debug("CashuRequestListener: malformed PaymentRequestPayload")
            return
        }
        let unit = (json["unit"] as? String) ?? "sat"
        let memo = json["memo"] as? String
        let tokenString = buildV3Token(mint: mintUrl, proofs: proofs, unit: unit, memo: memo)
        guard let tokenString else { return }
        guard let walletManager else {
            AppLogger.wallet.error("CashuRequestListener: walletManager not attached")
            return
        }
        do {
            try await walletManager.receiveCashuRequestPayment(
                tokenString: tokenString,
                requestId: requestId
            )
        } catch {
            AppLogger.wallet.error("CashuRequestListener: redeem failed: \(String(describing: error))")
        }
    }

    /// Build a NUT-00 V3 cashu token string from a mint + proofs payload.
    /// Format: `cashuA` + base64url(no padding)(JSON({token:[{mint, proofs}], unit, memo})).
    private func buildV3Token(mint: String, proofs: [[String: Any]], unit: String?, memo: String?) -> String? {
        var entry: [String: Any] = ["mint": mint, "proofs": proofs]
        _ = entry
        var token: [String: Any] = ["token": [["mint": mint, "proofs": proofs]]]
        if let unit { token["unit"] = unit }
        if let memo { token["memo"] = memo }
        guard let data = try? JSONSerialization.data(withJSONObject: token) else { return nil }
        return "cashuA" + Base64URL.encode(data)
    }
}
