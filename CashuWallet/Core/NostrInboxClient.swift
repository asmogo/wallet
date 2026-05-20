import Foundation

/// Long-lived NIP-17 inbox subscription across multiple relays.
/// Sends a REQ with `{"kinds":[1059], "#p":[pubkey], "since": <ts>}` and re-subscribes on reconnect.
actor NostrInboxClient {
    private let pubkeyHex: String
    private let relays: [String]
    private let onEvent: @Sendable (NostrIncomingEvent) async -> Void
    private let subId = "cashu-inbox-" + UUID().uuidString.split(separator: "-").first.map(String.init)!.lowercased()

    private var sessions: [URLSession] = []
    private var tasks: [URLSessionWebSocketTask] = []
    private var running = false
    private var sinceTimestamp: Int64

    init(
        pubkeyHex: String,
        relays: [String],
        since: Int64,
        onEvent: @escaping @Sendable (NostrIncomingEvent) async -> Void
    ) {
        self.pubkeyHex = pubkeyHex
        self.relays = relays
        self.sinceTimestamp = since
        self.onEvent = onEvent
    }

    func start() async {
        guard !running else { return }
        running = true
        for relay in relays {
            Task { await connectLoop(relay: relay) }
        }
    }

    func stop() async {
        running = false
        for task in tasks {
            task.cancel(with: .normalClosure, reason: nil)
        }
        tasks.removeAll()
        for session in sessions {
            session.invalidateAndCancel()
        }
        sessions.removeAll()
    }

    func updateSince(_ ts: Int64) {
        if ts > sinceTimestamp { sinceTimestamp = ts }
    }

    // MARK: - Connect / reconnect

    private func connectLoop(relay: String) async {
        var attempt = 0
        while running {
            await connect(relay: relay)
            guard running else { break }
            attempt += 1
            let delaySeconds = min(30, Int(pow(2.0, Double(min(attempt, 5)))))
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
        }
    }

    private func connect(relay: String) async {
        guard let url = URL(string: relay) else { return }
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 0
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        sessions.append(session)
        tasks.append(task)
        task.resume()

        // Send REQ
        let filter: [String: Any] = [
            "kinds": [1059],
            "#p": [pubkeyHex],
            "since": sinceTimestamp
        ]
        let reqArray: [Any] = ["REQ", subId, filter]
        guard let reqData = try? JSONSerialization.data(withJSONObject: reqArray),
              let reqString = String(data: reqData, encoding: .utf8) else {
            removeConnection(task: task, session: session)
            return
        }
        do {
            try await task.send(.string(reqString))
            await readLoop(task: task)
        } catch {
            // fall through to reconnect
        }
        removeConnection(task: task, session: session)
    }

    private func readLoop(task: URLSessionWebSocketTask) async {
        while task.state == .running {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                return
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let kind = array.first as? String else {
            return
        }
        switch kind {
        case "EVENT":
            guard array.count >= 3,
                  let event = array[2] as? [String: Any],
                  let parsed = parseEvent(event) else { return }
            updateSince(parsed.createdAt)
            await onEvent(parsed)
        case "EOSE", "OK", "NOTICE", "CLOSED":
            return
        default:
            return
        }
    }

    private func parseEvent(_ obj: [String: Any]) -> NostrIncomingEvent? {
        guard let id = obj["id"] as? String,
              let pubkey = obj["pubkey"] as? String,
              let kind = obj["kind"] as? Int,
              let tags = obj["tags"] as? [[String]],
              let content = obj["content"] as? String,
              let sig = obj["sig"] as? String else {
            return nil
        }
        let createdAt: Int64 = {
            if let n = obj["created_at"] as? NSNumber { return n.int64Value }
            if let i = obj["created_at"] as? Int { return Int64(i) }
            return 0
        }()
        return NostrIncomingEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )
    }

    private func removeConnection(task: URLSessionWebSocketTask, session: URLSession) {
        tasks.removeAll { ObjectIdentifier($0) == ObjectIdentifier(task) }
        sessions.removeAll { ObjectIdentifier($0) == ObjectIdentifier(session) }
    }
}
