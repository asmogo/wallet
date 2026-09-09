import Foundation
import Observation

@MainActor
@Observable
final class NFCReceiveCoordinator {
    enum Phase: Equatable { case idle, presenting, redeeming }
    private(set) var phase: Phase = .idle
    private(set) var message: String?
    private(set) var reviewPayment: PendingReceiveToken?
    private(set) var receivedAmount: UInt64?
    private var session: (any NFCReceiveTransport)?
    private var exchangeTask: Task<Void, Never>?
    private var generation = UUID()
    private let makeSession: @MainActor () -> any NFCReceiveTransport

    init(makeSession: @escaping @MainActor () -> any NFCReceiveTransport = { NFCReceiveCardSession() }) {
        self.makeSession = makeSession
    }

    var isBusy: Bool { phase != .idle }

    func start(request: CashuRequest, walletManager: WalletManager) {
        guard walletManager.isRuntimeReady else { return }
        start(
            request: request,
            stage: { try walletManager.stageNFCReceive($0, request: request) },
            claim: { try await walletManager.claimPendingReceiveToken($0) },
            refresh: { await walletManager.loadTransactions() }
        )
    }

    func start(
        request: CashuRequest,
        stage: @escaping (NFCNdefPayload) throws -> NFCReceivePayment,
        claim: @escaping (PendingReceiveToken) async throws -> UInt64,
        refresh: @escaping () async -> Void
    ) {
        guard !isBusy, NFCReceivePayment.canPresent(request) else { return }
        stop()
        message = nil
        reviewPayment = nil
        receivedAmount = nil
        phase = .presenting
        let current = generation
        let card = makeSession()
        session = card
        exchangeTask = Task {
            do {
                let payment = try await card.receive(request: PaymentRequestBuilder.buildNFC(request: request)) {
                    guard generation == current else { throw CancellationError() }
                    try Task.checkCancellation()
                    return try stage($0)
                }
                if let payment {
                    // A new task deliberately survives view disappearance and RF
                    // cancellation after receipt. Wallet operations protect their
                    // own background execution and serialize CDK access.
                    if generation == current { phase = .redeeming }
                    Task { await finish(payment, claim: claim, refresh: refresh, generation: current) }
                } else if generation == current {
                    phase = .idle
                }
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                phase = .idle
                message = (error as? NFCReceiveError)?.errorDescription
                    ?? "Couldn't receive by tap. Keep the phones together and try again."
            }
            if generation == current {
                exchangeTask = nil
                session = nil
            }
        }
    }

    /// Stop advertising on background, dismissal, or request edits. An accepted
    /// payment is already persisted; its wallet operation is never cancelled.
    func stop() {
        // Keep ownership while the independent wallet operation finishes.
        if phase == .redeeming { return }
        generation = UUID()
        exchangeTask?.cancel()
        exchangeTask = nil
        session?.stop()
        session = nil
        if phase == .presenting { phase = .idle }
    }

    func dismissReview() { reviewPayment = nil }

    private func finish(
        _ payment: NFCReceivePayment,
        claim: (PendingReceiveToken) async throws -> UInt64,
        refresh: () async -> Void,
        generation current: UUID
    ) async {
        if payment.needsReview {
            await refresh()
            if generation == current {
                message = payment.validationMessage.map { "\($0) The token is saved in History for review." }
                // Keep validation failures visible on the request; never cover
                // the mismatch explanation with an ordinary claim screen.
                if payment.validationMessage == nil { reviewPayment = payment.pending }
                phase = .idle
            }
            return
        }
        do {
            let amount = try await claim(payment.pending)
            if generation == current { receivedAmount = amount; phase = .idle }
        } catch {
            await refresh()
            if generation == current {
                message = "Couldn't claim the payment. The token is saved in History; review it to try again."
                reviewPayment = payment.pending
                phase = .idle
            }
        }
    }
}
