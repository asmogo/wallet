import CoreNFC
import SwiftUI

struct ContactlessPayView: View {
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var navigationManager: NavigationManager
    @Environment(\.dismiss) private var dismiss

    @State private var nfcDelegate: NFCReaderDelegate?
    @State private var nfcSession: NFCNDEFReaderSession?
    @State private var isProcessing = false
    @State private var paymentComplete = false
    @State private var errorMessage: String?
    @State private var lastPaymentAmount: UInt64?

    private var isNFCAvailable: Bool {
        NFCNDEFReaderSession.readingAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.gen2.crop.circle")
                            .fontWeight(.light)
                            .foregroundStyle(.primary.opacity(0.5))
                            .accessibilityHidden(true)
                        ContactlessWaveSymbol()
                    }
                    .font(.system(size: 60))

                    if !isNFCAvailable {
                        Text("NFC not available on this device")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        errorView(errorMessage)
                    }

                    if paymentComplete, let lastPaymentAmount {
                        VStack(spacing: 8) {
                            Label("Payment sent!", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("\(lastPaymentAmount) sat")
                                .font(.title2.bold().monospacedDigit())
                        }
                        .padding()
                    }
                }
                .accessibilityElement(children: .combine)

                Spacer()

                actionButton
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .principal) {
                    Text("Contactless")
                        .font(.headline)
                }
            }
            .onAppear {
                startContactlessPayment()
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if paymentComplete {
            Button(action: reset) {
                Label("Pay Again", systemImage: "arrow.counterclockwise")
            }
            .glassButton()
        } else {
            Button(action: startContactlessPayment) {
                if isProcessing {
                    ProgressView()
                } else {
                    Label("Pay with NFC", systemImage: "wave.3.right.circle.fill")
                }
            }
            .glassButton()
            .disabled(isProcessing || !isNFCAvailable)
        }
    }

    private func startContactlessPayment() {
        guard isNFCAvailable else {
            errorMessage = NFCPaymentError.nfcUnavailable.localizedDescription
            return
        }

        reset()
        isProcessing = true

        nfcDelegate = NFCReaderDelegate(
            onTagDetected: { tag, session in
                await self.handleTagDetected(tag: tag, session: session)
            },
            onError: { error in
                self.errorMessage = error
                self.isProcessing = false
            },
            onSessionEnd: {
                self.isProcessing = false
                self.nfcSession = nil
            }
        )

        guard let nfcDelegate else { return }
        nfcSession = NFCNDEFReaderSession(delegate: nfcDelegate, queue: nil, invalidateAfterFirstRead: false)
        nfcSession?.alertMessage = "Hold your iPhone near the payment terminal"
        nfcSession?.begin()
    }

    private func handleTagDetected(tag: NFCNDEFTag, session: NFCNDEFReaderSession) async {
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
                let amount = request.amount()?.value
                let token = try await service.prepareToken(for: request)

                session.alertMessage = "Sending payment..."
                do {
                    try await tag.writeNDEF(NDEFTextRecord.makeMessage(with: token))
                } catch {
                    throw NFCPaymentError.nfcWriteFailed(error.localizedDescription)
                }

                lastPaymentAmount = amount
                paymentComplete = true
                session.alertMessage = "Payment sent!"
                session.invalidate()

                try? await Task.sleep(for: .seconds(1.5))
                dismiss()

            case .bolt11(let invoice):
                session.alertMessage = "Lightning invoice found"
                session.invalidate()
                navigationManager.pendingMeltInvoice = invoice
                dismiss()
            }
        } catch let error as NFCPaymentError {
            errorMessage = error.localizedDescription
            session.invalidate(errorMessage: error.localizedDescription)
        } catch {
            errorMessage = error.localizedDescription
            session.invalidate(errorMessage: error.localizedDescription)
        }
    }

    private func reset() {
        errorMessage = nil
        paymentComplete = false
        lastPaymentAmount = nil
        isProcessing = false
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}

private struct ContactlessWaveSymbol: View {
    @State private var isOn = false

    var body: some View {
        Image(systemName: "wave.3.right")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.primary.opacity(0.5), .primary.opacity(0.6))
            .symbolEffect(.variableColor.iterative.nonReversing, options: .repeating, value: isOn)
            .accessibilityHidden(true)
            .onAppear { isOn.toggle() }
    }
}

#Preview {
    ContactlessPayView()
        .environmentObject(WalletManager())
        .environmentObject(NavigationManager())
}
