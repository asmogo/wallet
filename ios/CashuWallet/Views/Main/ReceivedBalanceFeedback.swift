import SwiftUI

/// Owns the received amount and its timer together, so leaving the wallet
/// cannot cancel dismissal while retaining a permanently visible "+N".
@MainActor
@Observable
final class ReceivedBalanceFeedback {
    private(set) var amount: UInt64?

    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    private let sleep: @MainActor (Duration) async throws -> Void

    init(sleep: @escaping @MainActor (Duration) async throws -> Void = {
        try await Task.sleep(for: $0)
    }) {
        self.sleep = sleep
    }

    func show(amount: UInt64, animation: Animation?) {
        dismissTask?.cancel()
        withAnimation(animation) {
            self.amount = amount
        }
        dismissTask = Task { @MainActor [weak self, sleep] in
            do {
                try await sleep(.seconds(2.5))
            } catch {
                return
            }
            // A cancelled timer must never dismiss a newer receipt, including
            // another receipt with exactly the same amount.
            guard !Task.isCancelled else { return }
            withAnimation(animation) {
                self?.clear()
            }
        }
    }

    /// Used when the screen disappears or the app enters the background.
    /// Always clear both state and work; SwiftUI can preserve state offscreen.
    func clear() {
        dismissTask?.cancel()
        dismissTask = nil
        amount = nil
    }

    deinit {
        dismissTask?.cancel()
    }
}
