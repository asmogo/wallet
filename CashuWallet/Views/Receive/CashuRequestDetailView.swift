import SwiftUI
import UIKit

struct CashuRequestDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var store = CashuRequestStore.shared
    @ObservedObject private var settings = SettingsManager.shared

    let onClose: () -> Void

    @State private var requestId: String
    @State private var showCopied = false
    @State private var paymentJustReceived = false
    @State private var showMintPicker = false
    @State private var showAmountPicker = false

    init(request: CashuRequest, onClose: @escaping () -> Void) {
        self._requestId = State(initialValue: request.id)
        self.onClose = onClose
    }

    private var request: CashuRequest? {
        store.request(withId: requestId)
    }

    private var paymentCount: Int {
        request?.receivedPaymentIds.count ?? 0
    }

    var body: some View {
        Group {
            if let request {
                content(request: request)
            } else {
                Text("Request not found")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Cashu Request")
                    .font(.headline)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let request {
                    ShareLink(item: request.encoded) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share request")
                }
            }
        }
        .sheet(isPresented: $showMintPicker) {
            CashuRequestMintPickerSheet(
                currentMintUrl: request?.mints.first,
                onSelect: { mintUrl in
                    let mints: [String] = mintUrl.map { [$0] } ?? []
                    regenerate(mints: mints)
                }
            )
            .environmentObject(walletManager)
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAmountPicker) {
            CashuRequestAmountPickerSheet(
                currentAmount: request?.amount,
                onSelect: { amount in
                    regenerate(amount: amount)
                }
            )
            .presentationDetents([.medium])
        }
        .onReceive(NotificationCenter.default.publisher(for: .cashuTokenReceived)) { note in
            guard let source = note.userInfo?["source"] as? String,
                  source == "cashu-request" else { return }
            paymentJustReceived = true
            HapticFeedback.notification(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                paymentJustReceived = false
            }
        }
    }

    @ViewBuilder
    private func content(request: CashuRequest) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    QRCodeView(content: request.encoded, showControls: false, staticOnly: true)
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 8)
                        .contextMenu {
                            Button(action: { copy(request.encoded) }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            ShareLink(item: request.encoded) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }

                    if let amount = request.amount, amount > 0 {
                        CurrencyAmountDisplay(
                            sats: amount,
                            primary: $settings.amountDisplayPrimary,
                            primarySize: 32
                        )
                    }

                    statusBadge

                    VStack(spacing: 0) {
                        editableRow(
                            icon: "bitcoinsign.bank.building",
                            label: "Mint",
                            value: mintDisplayValue(for: request),
                            action: { showMintPicker = true }
                        )
                        canvasDivider
                        editableRow(
                            icon: "number",
                            label: "Amount",
                            value: amountDisplayValue(for: request),
                            action: { showAmountPicker = true }
                        )
                        canvasDivider
                        detailRow(icon: "creditcard", label: "Unit", value: request.unit.uppercased())
                        canvasDivider
                        detailRow(
                            icon: "calendar",
                            label: "Created",
                            value: request.createdAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal)
            }

            VStack(spacing: 10) {
                Button(action: { copy(request.encoded) }) {
                    Text(showCopied ? "Copied" : "Copy")
                }
                .glassButton()

                Button(action: { regenerate() }) {
                    Text("New Request")
                }
                .glassButton()
                .accessibilityHint("Generates a fresh Cashu Request and rotates the QR")
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private var statusBadge: some View {
        Group {
            if paymentJustReceived {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolEffect(.bounce, value: paymentJustReceived)
                    Text("Payment received!")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
            } else if paymentCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(paymentCount == 1 ? "1 payment received" : "\(paymentCount) payments received")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Waiting for payment…")
                }
                .font(.subheadline)
                .foregroundStyle(.orange)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: paymentJustReceived)
        .animation(.easeInOut(duration: 0.2), value: paymentCount)
    }

    // MARK: - Detail rows

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }

    private func editableRow(icon: String, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "pencil")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            .font(.subheadline)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edits the \(label.lowercased())")
    }

    private var canvasDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 8)
    }

    // MARK: - Value formatters

    private func mintDisplayValue(for request: CashuRequest) -> String {
        guard let mintUrl = request.mints.first else { return "Any mint" }
        if let mint = walletManager.mints.first(where: { $0.url == mintUrl }) {
            return mint.name
        }
        return URL(string: mintUrl)?.host ?? mintUrl
    }

    private func amountDisplayValue(for request: CashuRequest) -> String {
        guard let amount = request.amount, amount > 0 else { return "Any" }
        return "\(amount) \(request.unit)"
    }

    // MARK: - Actions

    private func copy(_ s: String) {
        UIPasteboard.general.string = s
        HapticFeedback.selection()
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showCopied = false
        }
    }

    /// Rotates the displayed request with optional overrides. Defaults preserve the current request's params.
    private func regenerate(amount: UInt64?? = nil, mints: [String]? = nil) {
        HapticFeedback.selection()
        let nostr = NostrService.shared
        guard nostr.isInitialized, !nostr.publicKeyHex.isEmpty,
              let existing = request else { return }
        let nextAmount: UInt64?
        switch amount {
        case .none: nextAmount = existing.amount
        case .some(let inner): nextAmount = inner
        }
        let nextMints = mints ?? existing.mints
        let id = CashuRequest.newId()
        do {
            let encoded = try PaymentRequestBuilder.build(
                id: id,
                amount: nextAmount,
                unit: existing.unit,
                mints: nextMints,
                description: existing.memo,
                nostrPubkeyHex: nostr.publicKeyHex,
                relays: SettingsManager.shared.nostrRelays
            )
            let newRequest = store.createNew(
                amount: nextAmount,
                unit: existing.unit,
                mints: nextMints,
                memo: existing.memo,
                encoded: encoded
            )
            requestId = newRequest.id
        } catch {
            AppLogger.wallet.error("Could not regenerate request: \(String(describing: error))")
        }
    }
}
