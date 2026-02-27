import Foundation

// MARK: - Models

struct DiscoveredMint: Identifiable, Hashable {
    let id = UUID()
    let url: String
    let name: String?
    let pubkey: String?
    let description: String?
    
    // Conformance to Hashable
    static func == (lhs: DiscoveredMint, rhs: DiscoveredMint) -> Bool {
        lhs.url == rhs.url
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - Manager

@MainActor
class MintDiscoveryManager: ObservableObject {
    static let shared = MintDiscoveryManager()
    
    @Published var discoveredMints: [DiscoveredMint] = []
    @Published var isDiscovering = false
    
    private var webSocketTasks: [URLSessionWebSocketTask] = []
    private var sessions: [URLSession] = []
    private let discoveryWindowNanoseconds: UInt64 = 3 * 1_000_000_000
    private var configuredRelays: [String] {
        let relays = SettingsManager.shared.nostrRelays.filter { relay in
            let lower = relay.lowercased()
            return lower.hasPrefix("wss://") || lower.hasPrefix("ws://")
        }
        return relays.isEmpty ? SettingsManager.defaultNostrRelays : relays
    }
    
    func discoverMints() async {
        guard !isDiscovering else { return }
        guard SettingsManager.shared.useWebsockets else { return }
        isDiscovering = true
        discoveredMints = []
        closeAllConnections()
        
        defer {
            closeAllConnections()
            isDiscovering = false
        }
        
        await withTaskGroup(of: Void.self) { group in
            for relay in configuredRelays {
                group.addTask { [weak self] in
                    await self?.connectAndQuery(relay: relay)
                }
            }
            try? await Task.sleep(nanoseconds: discoveryWindowNanoseconds)
            closeAllConnections()
        }
    }
    
    private func connectAndQuery(relay: String) async {
        guard let url = URL(string: relay) else { return }
        
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        
        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: url)
        sessions.append(session)
        webSocketTasks.append(task)
        
        let subId = UUID().uuidString
        let filter = """
        ["REQ", "\(subId)", { "kinds": [38172], "limit": 50 }]
        """
        
        let message = URLSessionWebSocketTask.Message.string(filter)
        
        task.resume()
        
        do {
            try await task.send(message)
            await receiveMessages(task: task)
        } catch {
            print("Nostr Error keys \(relay): \(error)")
        }
        
        removeConnection(task: task, session: session)
    }
    
    private func receiveMessages(task: URLSessionWebSocketTask) async {
        // We'll listen for a few messages then close or timeout
        // In a real app we might keep this open.
        // For now, we loop until error or manually cancelled.
        do {
            while task.state == .running {
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
            }
        } catch {
            // Task handled or closed
        }
    }
    
    private func handleMessage(_ jsonString: String) async {
        // Parse JSON array: ["EVENT", "sub_id", { ... }]
        guard let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 3,
              array[0] as? String == "EVENT",
              let event = array[2] as? [String: Any] else {
            return
        }
        
        parseMintEvent(event)
    }
    
    private func parseMintEvent(_ event: [String: Any]) {
        // Check for Kind 38172 (implied by filter, but good to verify)
        // Extract tags
        guard let tags = event["tags"] as? [[String]] else { return }
        
        // Find "u" tag
        var mintUrl: String?
        for tag in tags {
            if tag.first == "u" && tag.count > 1 {
                mintUrl = tag[1]
            }
        }
        
        guard let url = mintUrl, url.hasPrefix("http") else { return }
        
        // Avoid duplicates
        if discoveredMints.contains(where: { $0.url == url }) {
            return
        }
        
        // Parse content
        var name: String? = nil
        var description: String? = nil
        
        if let contentStr = event["content"] as? String,
           let contentData = contentStr.data(using: .utf8),
           let contentJson = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] {
            name = contentJson["name"] as? String
            description = contentJson["description"] as? String
        }
        
        let discovered = DiscoveredMint(
            url: url,
            name: name ?? "Unknown Mint",
            pubkey: event["pubkey"] as? String,
            description: description
        )
        
        // Add to main list
        discoveredMints.append(discovered)
    }
    
    private func closeAllConnections() {
        for task in webSocketTasks {
            task.cancel(with: .normalClosure, reason: nil)
        }
        webSocketTasks.removeAll()
        
        for session in sessions {
            session.invalidateAndCancel()
        }
        sessions.removeAll()
    }
    
    private func removeConnection(task: URLSessionWebSocketTask, session: URLSession) {
        webSocketTasks.removeAll { ObjectIdentifier($0) == ObjectIdentifier(task) }
        sessions.removeAll { ObjectIdentifier($0) == ObjectIdentifier(session) }
    }
}
