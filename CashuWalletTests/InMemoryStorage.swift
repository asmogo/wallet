import Foundation
@testable import CashuWallet

/// Volatile in-memory StorageProtocol implementation for unit tests.
final class InMemoryStorage: StorageProtocol {
    private var data: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func set<T: Codable>(_ value: T, forKey key: String) throws {
        data[key] = try encoder.encode(value)
    }

    func get<T: Codable>(forKey key: String) throws -> T? {
        guard let raw = data[key] else { return nil }
        return try decoder.decode(T.self, from: raw)
    }

    func remove(forKey key: String) throws {
        data.removeValue(forKey: key)
    }

    func exists(forKey key: String) -> Bool {
        data[key] != nil
    }

    func keys(withPrefix prefix: String) -> [String] {
        data.keys.filter { $0.hasPrefix(prefix) }
    }
}
