#if DEBUG
import Foundation
import Cdk

/// UI transport double. It never opens relay connections or moves funds.
/// The lock protects the synchronous state required by CDK's Sendable protocol.
final class UITestNWCService: NwcServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private let uri: String

    init(clientSecret: String?) {
        let secret = clientSecret ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        uri = "nostr+walletconnect://" + String(repeating: "01", count: 32)
            + "?relay=wss%3A%2F%2Frelay.test&secret=" + secret
    }

    func clientPubkey() -> String { String(repeating: "02", count: 32) }
    func servicePubkey() -> String { String(repeating: "01", count: 32) }
    func connectionUri() -> String { uri }
    func isRunning() -> Bool { lock.withLock { running } }
    func start() async throws { lock.withLock { running = true } }
    func stop() async throws { lock.withLock { running = false } }
}
#endif
