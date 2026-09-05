import Foundation
import Observation

/// Owns the latest metadata request without tying cached information to reachability.
@MainActor
@Observable
final class MintDetailInfoLoader<Info> {
    enum Connection {
        case notChecked, checking, online, offline
    }

    private(set) var info: Info?
    private(set) var connection: Connection = .notChecked
    private(set) var errorMessage: String?
    private var requestID = UUID()

    var isLoading: Bool { connection == .checking }

    func load(fetch: () async throws -> Info?) async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        requestID = request
        connection = .checking
        errorMessage = nil

        do {
            let fetched = try await fetch()
            try Task.checkCancellation()
            guard requestID == request else { return }
            guard let fetched else {
                connection = .offline
                errorMessage = "The mint did not respond."
                return
            }
            info = fetched
            connection = .online
        } catch {
            // An older request must not overwrite a newer success or loading state.
            guard requestID == request else { return }
            if Task.isCancelled || error is CancellationError
                || (error as? URLError)?.code == .cancelled {
                connection = .notChecked
            } else {
                connection = .offline
                errorMessage = error.userFacingWalletMessage
            }
        }
    }
}
