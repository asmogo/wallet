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


/// Native activity presentation shared by transactions and stored requests.
/// Each body retains its adaptive QR, status cues and pinned actions.
struct ActivityDetailSheet<Content: View>: View {
    let title: String
    var contentHeight: CGFloat = 0
    var fitsContent = false
    var onShare: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.activitySheetSizing) private var activitySheetSizing
    @Environment(\.dismissActivitySheet) private var dismissActivitySheet
    @Environment(\.colorScheme) private var colorScheme
    @State private var navigationInset: CGFloat = 44

    var body: some View {
        Group {
            if let activitySheetSizing {
                navigationContent
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.secondary.opacity(0.5))
                            .frame(width: 36, height: 5)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                .environment(\.bottomSheetSurfaceStyle, .compact)
                .background { CompactSheetBackground().ignoresSafeArea() }
                .containerShape(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("cashu.history.sheet")
                .onChange(of: fittedHeight, initial: true) { _, height in activitySheetSizing(height) }
            } else {
                navigationContent
                    .compactBottomSheetSurface()
                    .contentFitDetent(nativeContentHeight, enabled: fitsContent, estimate: 500, navigationBar: true)
                    .presentationDragIndicator(.visible)
            }
        }
        .accessibilityAction(.escape) {
            if let dismissActivitySheet { dismissActivitySheet() } else { dismiss() }
        }
    }

    private var fittedHeight: CGFloat? {
        fitsContent ? (contentHeight > 0 ? contentHeight : 500) + navigationInset : nil
    }

    private var nativeContentHeight: CGFloat {
        // Account for the actual navigation inset on floating iPad sheets too.
        contentHeight > 0 ? contentHeight + max(0, navigationInset - ContentFitSheetMetrics.navigationBar) : 0
    }

    private var navigationContent: some View {
        NavigationStack {
            content()
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { inset in
                    if inset > 0 { navigationInset = inset }
                }
                .background {
                    if activitySheetSizing != nil {
                        CompactSheetPalette.sheet(for: colorScheme).ignoresSafeArea()
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(title).font(.headline)
                    }
                    if let onShare {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: onShare) {
                                Image(systemName: "square.and.arrow.up")
                                    .toolbarIconTapTarget()
                            }
                            .accessibilityLabel("Share")
                        }
                    }
                }
        }
    }
}
