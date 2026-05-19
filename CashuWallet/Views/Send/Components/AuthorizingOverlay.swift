import SwiftUI

/// Family/Rainbow-style "Authorizing…" bottom sheet.
///
/// Presented as a `.sheet` over the input view while a payment is in flight.
/// The pill button morphs through `authorizing → sent` (or `error`) with a
/// capsule progress fill, and dismisses itself ~1.2s after success.
struct AuthorizingOverlay: View {
    enum FlowState: Equatable {
        case authorizing
        case sent
        case error(String)
    }

    let amountSats: UInt64
    let recipient: String
    let recipientCaption: String?
    @Binding var state: FlowState
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismissSheet
    @ObservedObject private var settings = SettingsManager.shared
    @State private var fillProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            CurrencyAmountDisplay(
                sats: amountSats,
                primary: $settings.amountDisplayPrimary,
                primarySize: 44
            )
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text("to")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(recipient)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let caption = recipientCaption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            statePill
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onAppear { startFill() }
        .onChange(of: state) { _, newState in
            handleStateChange(newState)
        }
    }

    @ViewBuilder
    private var statePill: some View {
        switch state {
        case .authorizing:
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(.tint.opacity(0.4))
                        .frame(width: geo.size.width * fillProgress)
                        .animation(.linear(duration: 1.2), value: fillProgress)
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Authorizing…")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 52)
            .transition(.opacity)

        case .sent:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .symbolEffect(.bounce, value: state == .sent)
                Text("Sent")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.green.opacity(0.18), in: Capsule())
            .foregroundStyle(.green)
            .transition(.scale.combined(with: .opacity))

        case .error(let message):
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Failed")
                        .font(.body.weight(.semibold))
                }
                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 26))
            .foregroundStyle(.red)
            .transition(.opacity)
        }
    }

    private func startFill() {
        fillProgress = 0
        // Animate to ~0.9 so it lingers near the end while we wait for the actual result.
        withAnimation(.linear(duration: 1.2)) {
            fillProgress = 0.9
        }
    }

    private func handleStateChange(_ newState: FlowState) {
        switch newState {
        case .sent:
            withAnimation(.snappy) { fillProgress = 1 }
            HapticFeedback.notification(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                onDismiss()
            }
        case .error:
            HapticFeedback.notification(.error)
        case .authorizing:
            startFill()
        }
    }
}
