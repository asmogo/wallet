import CoreNFC
import Foundation

@MainActor
protocol NFCReceiveTransport: AnyObject {
    func receive(request: String, accept: (NFCNdefPayload) throws -> NFCReceivePayment) async throws -> NFCReceivePayment?
    func stop()
}

/// Uses the same foreground CardSession / presentment-assertion approach as
/// Macadamia's NFCRequestEmulation. No APDU or bearer-token data is logged.
@MainActor
final class NFCReceiveCardSession: NFCReceiveTransport {
    private var session: CardSession?

    static var isAvailable: Bool {
        get async {
            #if targetEnvironment(simulator)
            return false
            #else
            guard Bundle.main.object(forInfoDictionaryKey: "CashuHCEEnabled") as? String == "YES" else { return false }
            guard CardSession.isSupported else { return false }
            return await CardSession.isEligible
            #endif
        }
    }

    func stop() {
        session?.invalidate()
        session = nil
    }

    func receive(
        request: String,
        accept: (NFCNdefPayload) throws -> NFCReceivePayment
    ) async throws -> NFCReceivePayment? {
        guard await Self.isAvailable else {
            throw NFCReceiveError.message("Contactless receive isn't available on this iPhone or in your region.")
        }
        try Task.checkCancellation()
        var tag = try NFCType4Tag(request: request)
        // Optional suppression of the default contactless app. A cooldown or
        // unavailable assertion must not prevent a foreground card session.
        let assertion = try? await NFCPresentmentIntentAssertion.acquire()
        defer { withExtendedLifetime(assertion) {} }
        try Task.checkCancellation()
        let card = try await CardSession()
        defer { card.invalidate(); session = nil }
        try Task.checkCancellation()
        session = card
        var accepted: NFCReceivePayment?
        do {
            for try await event in card.eventStream {
                try Task.checkCancellation()
                switch event {
                case .sessionStarted:
                    card.alertMessage = "Hold this iPhone near the payer's device."
                    try await card.startEmulation()
                case .readerDetected:
                    if await !card.isEmulationInProgress {
                        try Task.checkCancellation()
                        try await card.startEmulation()
                    }
                case .readerDeselected:
                    tag.reset()
                case .received(let apdu):
                    let result = tag.process(apdu.payload)
                    if let payload = result.payload {
                        do {
                            accepted = try accept(payload)
                        } catch {
                            // Don't acknowledge a token that we couldn't retain.
                            try? await apdu.respond(response: Data([0x6A, 0x80]))
                            throw error
                        }
                    }
                    try await apdu.respond(response: result.response)
                    if accepted != nil {
                        card.alertMessage = "Payment data received."
                        await card.stopEmulation(status: .success)
                        return accepted
                    }
                case .sessionInvalidated(let reason):
                    switch reason {
                    case .userInvalidated, .maxSessionDurationReached, .emulationStopped, .invalidated:
                        return accepted
                    default: throw reason
                    }
                @unknown default: break
                }
            }
        } catch {
            // Once persisted, finish receiving even if the last response or
            // native-sheet dismissal failed. Never lose an already accepted token.
            if let accepted { return accepted }
            throw error
        }
        return accepted
    }
}
