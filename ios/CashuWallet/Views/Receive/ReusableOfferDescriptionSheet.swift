import SwiftUI

/// Description edit sheet for a reusable BOLT12 offer (Android
/// `ReusableDescriptionEditSheet` parity). The text is embedded in the offer
/// payers receive. Seeded verbatim from the current offer's stored memo;
/// never from profile or mint metadata. Empty → removes the description
/// (plain offer).
struct ReusableOfferDescriptionSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Current offer description, if any (`nil` = plain offer).
    let currentDescription: String?
    /// Called with the new description on Done (`nil` = removed). Sheet
    /// dismisses afterwards.
    let onDone: (String?) -> Void

    @State private var description: String

    init(currentDescription: String?, onDone: @escaping (String?) -> Void) {
        self.currentDescription = currentDescription
        self.onDone = onDone
        self._description = State(initialValue: currentDescription ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            TextField(
                "e.g. Coffee tips",
                text: $description,
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            .padding(.top, 16)
            .accessibilityLabel("Description shown to the payer")
            .onChange(of: description) { _, newValue in
                if newValue.count > ReceiveLightningView.maxOfferDescriptionLength {
                    description = String(newValue.prefix(ReceiveLightningView.maxOfferDescriptionLength))
                }
            }

            Spacer(minLength: 0)

            Button(action: confirm) {
                Text("Done")
            }
            .glassButton()
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        ZStack {
            Text("Description")
                .font(.headline)

            HStack {
                SheetCloseButton()
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
    }

    private func confirm() {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        onDone(trimmed.isEmpty ? nil : trimmed)
        dismiss()
    }
}
