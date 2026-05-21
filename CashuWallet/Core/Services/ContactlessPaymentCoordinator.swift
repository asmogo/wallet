import CoreNFC
import Foundation

/// Orchestrates a contactless NFC payment with no custom SwiftUI chrome.
/// The iOS native NFC scan sheet ("Hold Near Reader") is the entire user
/// surface; status text flows through `session.alertMessage` and errors
/// through `session.invalidate(errorMessage:)`.
///
/// Holds the delegate + session as instance state so they survive past the
/// triggering tap (NFCNDEFReaderSession requires a stable delegate pointer
/// for the duration of the scan).
@MainActor
final class ContactlessPaymentCoordinator {
    private var delegate: NFCReaderDelegate?
    private var session: NFCNDEFReaderSession?

    func start(walletManager: WalletManager, navigationManager: NavigationManager) {
        guard NFCNDEFReaderSession.readingAvailable else { return }

        // Tear down any prior session so a back-to-back trigger doesn't
        // leak readers.
        session?.invalidate()
        delegate = nil
        session = nil

        let delegate = NFCReaderDelegate(
            onTagDetected: { [weak self] tag, session in
                await self?.handleTagDetected(
                    tag: tag,
                    session: session,
                    walletManager: walletManager,
                    navigationManager: navigationManager
                )
            },
            onError: { _ in
                // iOS surfaces the error in its own sheet; no extra UI.
            },
            onSessionEnd: { [weak self] in
                self?.delegate = nil
                self?.session = nil
            }
        )
        self.delegate = delegate

        let session = NFCNDEFReaderSession(delegate: delegate, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = "Hold your iPhone near the payment terminal"
        self.session = session
        session.begin()
    }

    private func handleTagDetected(
        tag: NFCNDEFTag,
        session: NFCNDEFReaderSession,
        walletManager: WalletManager,
        navigationManager: NavigationManager
    ) async {
        let service = NFCPaymentService(walletManager: walletManager)

        do {
            session.alertMessage = "Reading payment request..."

            do {
                try await session.connect(to: tag)
            } catch {
                throw NFCPaymentError.tagConnectionFailed
            }

            let ndefMessage: NFCNDEFMessage
            do {
                ndefMessage = try await tag.readNDEF()
            } catch {
                throw NFCPaymentError.nfcReadFailed(error.localizedDescription)
            }

            guard let rawInput = NDEFTextRecord.extractText(from: ndefMessage) else {
                throw NFCPaymentError.nfcReadFailed("No readable data on tag")
            }

            let input = try service.decode(rawInput)

            switch input {
            case .creq(let request):
                session.alertMessage = "Preparing payment..."
                let token = try await service.prepareToken(for: request)

                session.alertMessage = "Sending payment..."
                do {
                    try await tag.writeNDEF(NDEFTextRecord.makeMessage(with: token))
                } catch {
                    throw NFCPaymentError.nfcWriteFailed(error.localizedDescription)
                }

                session.alertMessage = "Payment sent!"
                session.invalidate()

            case .bolt11(let invoice):
                session.alertMessage = "Lightning request found"
                session.invalidate()
                navigationManager.pendingMeltInvoice = invoice
            }
        } catch let error as NFCPaymentError {
            session.invalidate(errorMessage: error.localizedDescription)
        } catch {
            session.invalidate(errorMessage: error.localizedDescription)
        }
    }
}
