import SwiftUI

/// The shared compact confirmation, also used by Generate new key.
struct ActionConfirmationSheet: View {
    let title: String
    let message: String
    let actionLabel: String
    var destructive = false
    let action: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var contentHeight: CGFloat = 0
    @State private var submitted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) {
                        confirmButton
                        cancelButton
                    }
                } else {
                    HStack(spacing: 12) {
                        cancelButton
                        confirmButton
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .contentFitMeasured { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .contentFitDetent(contentHeight, estimate: 280, navigationBar: false)
        .presentationDragIndicator(.visible)
        .flatBottomSheetSurface()
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel) { dismiss() }
            .flatSheetSecondaryButton()
    }

    private var confirmButton: some View {
        Button(actionLabel, role: destructive ? .destructive : nil) {
            guard !submitted else { return }
            submitted = true
            dismiss()
            action()
        }
        .glassButton(destructive: destructive)
        .disabled(submitted)
    }
}
