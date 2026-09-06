import SwiftUI

extension EnvironmentValues {
    @Entry var compactPaymentDetails = false
}

/// Fits the QR around the receipt's actual text, keeping related details together.
/// Scrolling remains available when accessibility text needs more than one screen.
struct PaymentDetailContent<Hero: View, Details: View>: View {
    @ViewBuilder let hero: (CGFloat) -> Hero
    @ViewBuilder let details: () -> Details
    @State private var detailsHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let qrSize = max(120, min(280, geometry.size.width - 64,
                                      geometry.size.height - detailsHeight - 64))
            ScrollView {
                VStack(spacing: 16) {
                    hero(qrSize)
                    details()
                        .environment(\.compactPaymentDetails, geometry.size.height < 600)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailsHeight = $0 }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Shared history inspector with an optional visible QR above the amount and facts.
struct ActivityDetailSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24, content: content)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .contentFitMeasured { contentHeight = $0 }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        .compactBottomSheetSurface()
        .contentFitDetent(contentHeight, estimate: 420, navigationBar: true)
        .presentationDragIndicator(.visible)
        .accessibilityAction(.escape) { dismiss() }
    }
}

struct ActivityPaymentCode: View {
    let content: String
    var staticOnly = true
    let onCopy: () -> Void
    let onShare: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            code(size: 240)
            code(size: 180)
            code(size: 120)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("cashu.history.payment-code")
    }

    private func code(size: CGFloat) -> some View {
        QRCodeView(content: content, showControls: false, staticOnly: staticOnly,
                   onCopy: onCopy, onShare: onShare)
            .frame(width: size, height: size)
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc", action: onCopy)
                Button("Share", systemImage: "square.and.arrow.up", action: onShare)
            }
    }
}
