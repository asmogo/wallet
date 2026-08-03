import Foundation

// MARK: - Models

struct DiscoveredMint: Identifiable, Hashable {
    var id: String { url }
    let url: String
    var name: String?
    var iconUrl: String?
    let pubkey: String?
    var description: String?
    var methods: [PaymentMethodKind] = []

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return URL(string: url)?.host ?? url
    }

    static func == (lhs: DiscoveredMint, rhs: DiscoveredMint) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

struct MintDiscoveryPreview: Equatable, Sendable {
    let name: String?
    let description: String?
    let iconUrl: String?
    let methods: [PaymentMethodKind]
}

protocol MintDiscoveryPreviewFetching: Sendable {
    func fetchPreview(for mintURL: String) async -> MintDiscoveryPreview?
}

/// A bounded NUT-06 request that never creates a CDK wallet or enters the
/// serialized wallet-operation lane.
final class HTTPMintDiscoveryPreviewFetcher: MintDiscoveryPreviewFetching, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 5
            configuration.httpMaximumConnectionsPerHost = 4
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchPreview(for mintURL: String) async -> MintDiscoveryPreview? {
        guard let baseURL = URL(string: mintURL) else { return nil }
        let infoURL = baseURL.appendingPathComponent("v1/info")
        var request = URLRequest(url: infoURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return MintDiscoveryPreviewParser.parse(data)
        } catch {
            return nil
        }
    }
}

enum MintDiscoveryPreviewParser {
    static func parse(_ data: Data) -> MintDiscoveryPreview? {
        guard let document = try? JSONDecoder().decode(MintInfoDocument.self, from: data) else {
            return nil
        }
        let mintSettings = document.nuts?["4"]?.activeMethods ?? []
        let meltSettings = document.nuts?["5"]?.activeMethods ?? []
        let reported = (mintSettings + meltSettings).compactMap { PaymentMethodKind(rawValue: $0.method.lowercased()) }
        let methods = PaymentMethodKind.allCases.filter(reported.contains)
        return MintDiscoveryPreview(
            name: document.name?.nonBlank,
            description: document.description,
            iconUrl: document.iconUrl,
            methods: methods
        )
    }

    private struct MintInfoDocument: Decodable {
        let name: String?
        let description: String?
        let iconUrl: String?
        let nuts: [String: NutSettings]?

        private enum CodingKeys: String, CodingKey {
            case name
            case description
            case iconUrlSnake = "icon_url"
            case iconUrlCamel = "iconUrl"
            case nuts
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            iconUrl = try container.decodeIfPresent(String.self, forKey: .iconUrlSnake)
                ?? container.decodeIfPresent(String.self, forKey: .iconUrlCamel)
            nuts = try container.decodeIfPresent([String: NutSettings].self, forKey: .nuts)
        }
    }

    private struct NutSettings: Decodable {
        let methods: [MethodSettings]?
        let disabled: Bool?

        var activeMethods: [MethodSettings] {
            disabled == true ? [] : (methods ?? [])
        }
    }

    private struct MethodSettings: Decodable {
        let method: String
    }
}

private extension String {
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

func canonicalDiscoveredMintURL(_ rawURL: String) -> String? {
    let normalized = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: normalized),
          components.scheme?.lowercased() == "https",
          let host = components.host,
          !host.isEmpty,
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil else {
        return nil
    }
    components.scheme = "https"
    components.host = host.lowercased()
    while components.path.hasSuffix("/") { components.path.removeLast() }
    return components.string
}

private actor MintDiscoveryPreviewPermits {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ available: Int) {
        self.available = available
    }

    func wait() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Manager

@MainActor
final class MintDiscoveryManager: ObservableObject {
    static let shared = MintDiscoveryManager()

    @Published private(set) var discoveredMints: [DiscoveredMint] = []
    @Published private(set) var isDiscovering = false

    private var webSocketTasks: [URLSessionWebSocketTask] = []
    private var sessions: [URLSession] = []
    private var validationTasks: [String: Task<Void, Never>] = [:]
    private var seenURLs: Set<String> = []
    private var discoveryGeneration = 0
    private var relayDiscoveryActive = false
    private let previewFetcher: MintDiscoveryPreviewFetching
    private let previewPermits = MintDiscoveryPreviewPermits(4)
    private let discoveryWindowNanoseconds: UInt64 = 3 * 1_000_000_000

    init(previewFetcher: MintDiscoveryPreviewFetching = HTTPMintDiscoveryPreviewFetcher()) {
        self.previewFetcher = previewFetcher
    }

    private var configuredRelays: [String] {
        let relays = SettingsManager.shared.nostrRelays.filter { relay in
            let lower = relay.lowercased()
            return lower.hasPrefix("wss://") || lower.hasPrefix("ws://")
        }
        return relays.isEmpty ? SettingsManager.defaultNostrRelays : relays
    }

    func clearDiscoveredMints() {
        discoveryGeneration &+= 1
        relayDiscoveryActive = false
        cancelValidationTasks()
        closeAllConnections()
        seenURLs = []
        discoveredMints = []
        updateDiscoveryState()
    }

    func discoverMints() async {
        guard !isDiscovering else { return }
        guard SettingsManager.shared.useWebsockets else { return }

        discoveryGeneration &+= 1
        let generation = discoveryGeneration
        cancelValidationTasks()
        closeAllConnections()
        seenURLs = []
        discoveredMints = []
        relayDiscoveryActive = true
        updateDiscoveryState()

        await withTaskGroup(of: Void.self) { group in
            for relay in configuredRelays {
                group.addTask { [weak self] in
                    await self?.connectAndQuery(relay: relay, generation: generation)
                }
            }
            try? await Task.sleep(nanoseconds: discoveryWindowNanoseconds)
            closeAllConnections()
        }

        guard discoveryGeneration == generation else { return }
        relayDiscoveryActive = false
        closeAllConnections()
        updateDiscoveryState()
    }

    private func connectAndQuery(relay: String, generation: Int) async {
        guard let url = URL(string: relay), discoveryGeneration == generation else { return }

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10

        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: url)
        sessions.append(session)
        webSocketTasks.append(task)

        let subscriptionID = UUID().uuidString
        let filter = """
        ["REQ", "\(subscriptionID)", { "kinds": [38172], "limit": 50 }]
        """

        task.resume()
        do {
            try await task.send(.string(filter))
            await receiveMessages(task: task, generation: generation)
        } catch {
            // Relay failures are expected; other configured relays continue.
        }
        removeConnection(task: task, session: session)
    }

    private func receiveMessages(task: URLSessionWebSocketTask, generation: Int) async {
        do {
            while task.state == .running, discoveryGeneration == generation {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleMessage(text, generation: generation)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text, generation: generation)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            // The discovery window closes active relay receives normally.
        }
    }

    private func handleMessage(_ jsonString: String, generation: Int) {
        guard discoveryGeneration == generation,
              let data = jsonString.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 3,
              array[0] as? String == "EVENT",
              let event = array[2] as? [String: Any],
              event["kind"] as? Int == 38172,
              let tags = event["tags"] as? [[String]],
              let announcedURL = tags.first(where: { $0.first == "u" && $0.count > 1 })?[1],
              let mintURL = canonicalDiscoveredMintURL(announcedURL),
              seenURLs.insert(mintURL).inserted else {
            return
        }

        var name: String?
        var iconUrl: String?
        var description: String?
        if let contentString = event["content"] as? String,
           let contentData = contentString.data(using: .utf8),
           let content = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] {
            name = (content["name"] as? String)?.nonBlank
            iconUrl = (content["icon_url"] as? String) ?? (content["iconUrl"] as? String)
            description = content["description"] as? String
        }

        let candidate = DiscoveredMint(
            url: mintURL,
            name: name,
            iconUrl: iconUrl,
            pubkey: event["pubkey"] as? String,
            description: description
        )
        validate(candidate, generation: generation)
    }

    private func validate(_ candidate: DiscoveredMint, generation: Int) {
        let url = candidate.url
        validationTasks[url] = Task { [weak self, previewFetcher, previewPermits] in
            await previewPermits.wait()
            guard !Task.isCancelled else {
                await previewPermits.signal()
                self?.finishValidation(candidate, preview: nil, generation: generation)
                return
            }

            let preview = await previewFetcher.fetchPreview(for: url)
            await previewPermits.signal()
            self?.finishValidation(candidate, preview: preview, generation: generation)
        }
        updateDiscoveryState()
    }

    private func finishValidation(
        _ candidate: DiscoveredMint,
        preview: MintDiscoveryPreview?,
        generation: Int
    ) {
        guard discoveryGeneration == generation else { return }
        validationTasks[candidate.url] = nil
        if let preview {
            var validated = candidate
            validated.name = preview.name ?? validated.name
            validated.iconUrl = preview.iconUrl ?? validated.iconUrl
            validated.description = preview.description ?? validated.description
            validated.methods = preview.methods
            if !discoveredMints.contains(where: { $0.url == validated.url }) {
                discoveredMints.append(validated)
            }
        }
        updateDiscoveryState()
    }

    private func cancelValidationTasks() {
        validationTasks.values.forEach { $0.cancel() }
        validationTasks = [:]
    }

    private func updateDiscoveryState() {
        isDiscovering = relayDiscoveryActive || !validationTasks.isEmpty
    }

    private func closeAllConnections() {
        webSocketTasks.forEach { $0.cancel(with: .normalClosure, reason: nil) }
        webSocketTasks.removeAll()
        sessions.forEach { $0.invalidateAndCancel() }
        sessions.removeAll()
    }

    private func removeConnection(task: URLSessionWebSocketTask, session: URLSession) {
        webSocketTasks.removeAll { ObjectIdentifier($0) == ObjectIdentifier(task) }
        sessions.removeAll { ObjectIdentifier($0) == ObjectIdentifier(session) }
    }
}
