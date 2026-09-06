import SwiftUI

/// Edits the payer-facing memo of a reusable BOLT12 offer. A blank draft
/// removes the description; closing the sheet leaves the offer unchanged.
struct ReusableOfferDescriptionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onDone: (String?) -> Void

    @State private var description: String
    @State private var contentHeight: CGFloat = 0
    @FocusState private var descriptionFocused: Bool

    init(currentDescription: String?, onDone: @escaping (String?) -> Void) {
        self.onDone = onDone
        self._description = State(initialValue: currentDescription ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Add a note for anyone paying this invoice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)

                TextField("e.g. Coffee tips", text: $description, axis: .vertical)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .lineLimit(3...5)
                    .textInputAutocapitalization(.sentences)
                    .focused($descriptionFocused)
                    .accessibilityLabel("Description")
                    .accessibilityHint("Shown to the payer. Leave blank to remove.")
                    .accessibilityIdentifier("reusable-description-field")
                    .onChange(of: description) { _, newValue in
                        if newValue.count > ReceiveLightningView.maxOfferDescriptionLength {
                            description = String(newValue.prefix(ReceiveLightningView.maxOfferDescriptionLength))
                        }
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                HStack(alignment: .firstTextBaseline) {
                    Text("Leave blank to remove.")
                    Spacer(minLength: 8)
                    Text("\(description.count) / \(ReceiveLightningView.maxOfferDescriptionLength)")
                        .monospacedDigit()
                        .accessibilityLabel("\(description.count) of \(ReceiveLightningView.maxOfferDescriptionLength) characters")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 24)

                Button("Save", action: confirm)
                    .glassButton()
                    .accessibilityIdentifier("reusable-description-save")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .contentFitMeasured { contentHeight = $0 }
            .navigationTitle("Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }
            }
        }
        .contentFitDetent(contentHeight, estimate: 290)
        .presentationDragIndicator(.visible)
        .compactBottomSheetSurface()
        .task { descriptionFocused = true }
    }

    private func confirm() {
        HapticFeedback.selection()
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        onDone(trimmed.isEmpty ? nil : trimmed)
        dismiss()
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ReusableOfferDescriptionSheet(currentDescription: "Coffee tips") { _ in }
    }
}
