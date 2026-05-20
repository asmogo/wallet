import Foundation
import SwiftUI

@MainActor
class CashuRequestStore: ObservableObject {
    static let shared = CashuRequestStore()

    @Published private(set) var requests: [CashuRequest] = []
    @Published var currentRequestId: String?

    private let storageKey = "cashuRequests.v1"
    private let currentIdKey = "cashuRequests.currentId.v1"

    var currentRequest: CashuRequest? {
        guard let id = currentRequestId else { return nil }
        return requests.first(where: { $0.id == id })
    }

    private init() {
        load()
    }

    func createNew(
        amount: UInt64? = nil,
        unit: String = "sat",
        mints: [String] = [],
        memo: String? = nil,
        encoded: String
    ) -> CashuRequest {
        let request = CashuRequest(
            encoded: encoded,
            amount: amount,
            unit: unit,
            mints: mints,
            memo: memo
        )
        requests.insert(request, at: 0)
        currentRequestId = request.id
        persist()
        return request
    }

    func attachPayment(requestId: String, historyId: String) {
        guard let index = requests.firstIndex(where: { $0.id == requestId }) else { return }
        guard !requests[index].receivedPaymentIds.contains(historyId) else { return }
        requests[index].receivedPaymentIds.append(historyId)
        persist()
    }

    func request(withId id: String) -> CashuRequest? {
        requests.first(where: { $0.id == id })
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(requests)
            UserDefaults.standard.set(data, forKey: storageKey)
            UserDefaults.standard.set(currentRequestId, forKey: currentIdKey)
        } catch {
            AppLogger.wallet.error("CashuRequestStore persist failed: \(String(describing: error))")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CashuRequest].self, from: data) {
            requests = decoded
        }
        currentRequestId = UserDefaults.standard.string(forKey: currentIdKey)
    }
}
