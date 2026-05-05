import CoreNFC
import Foundation

final class NFCReaderDelegate: NSObject, NFCNDEFReaderSessionDelegate, @unchecked Sendable {
    let onTagDetected: @MainActor @Sendable (NFCNDEFTag, NFCNDEFReaderSession) async -> Void
    let onError: @MainActor @Sendable (String) -> Void
    let onSessionEnd: @MainActor @Sendable () -> Void

    init(
        onTagDetected: @escaping @MainActor @Sendable (NFCNDEFTag, NFCNDEFReaderSession) async -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void,
        onSessionEnd: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onTagDetected = onTagDetected
        self.onError = onError
        self.onSessionEnd = onSessionEnd
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError

        Task { @MainActor in
            if nfcError?.code != .readerSessionInvalidationErrorUserCanceled &&
                nfcError?.code != .readerSessionInvalidationErrorFirstNDEFTagRead {
                self.onError(error.localizedDescription)
            }
            self.onSessionEnd()
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag found")
            return
        }

        Task { @MainActor in
            await self.onTagDetected(tag, session)
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
    }
}
