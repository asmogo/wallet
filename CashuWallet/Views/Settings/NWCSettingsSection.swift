import SwiftUI

struct NWCSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    @Binding var nwcError: String?
    @Binding var copiedNWCConnectionId: UUID?
    @Binding var activeQRPayload: QRPayload?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nostr Wallet Connect (NWC)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)

            Text("Use NWC to control your wallet from compatible applications.")
                .font(.caption)
                .foregroundColor(.cashuMutedText)

            Toggle(isOn: $settings.enableNWC.animation(.easeInOut(duration: 0.2))) {
                Text("Enable NWC")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

            if settings.enableNWC {
                Text("You can only use NWC for payments from your Bitcoin balance on your active mint.")
                    .font(.caption2)
                    .foregroundColor(.cashuMutedText)

                Button(action: createNWCConnection) {
                    HStack(spacing: 8) {
                        Image(systemName: "link.badge.plus")
                        Text(settings.nwcConnections.isEmpty ? "Create connection" : "Ensure connection")
                    }
                    .font(.subheadline)
                    .foregroundColor(settings.accentColor)
                }

                ForEach(settings.nwcConnections) { connection in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Connection")
                                .font(.caption)
                                .foregroundColor(.cashuMutedText)

                            Spacer()

                            Button(action: { copyNWCConnection(connection) }) {
                                Image(systemName: copiedNWCConnectionId == connection.id ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedNWCConnectionId == connection.id ? .green : settings.accentColor)
                            }
                            .accessibilityLabel("Copy connection string")

                            Button(action: { showQRCode(title: "NWC Connection", content: settings.nwcConnectionString(for: connection)) }) {
                                Image(systemName: "qrcode")
                                    .foregroundColor(settings.accentColor)
                            }
                            .accessibilityLabel("Show connection QR")

                            Button(action: { settings.removeNWCConnection(connection) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.cashuError)
                            }
                            .accessibilityLabel("Remove connection")
                        }

                        Text(settings.nwcConnectionString(for: connection))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack {
                            Text("Allowance left (sat)")
                                .font(.caption2)
                                .foregroundColor(.cashuMutedText)
                            Spacer()
                            TextField("0", text: allowanceBinding(for: connection))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: 100)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.cashuCardBackground)
                    )
                }

                if let nwcError {
                    Text(nwcError)
                        .font(.caption2)
                        .foregroundColor(.cashuError)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func createNWCConnection() {
        nwcError = nil
        guard settings.generateNWCConnection() != nil else {
            nwcError = "Unable to create an NWC connection."
            return
        }
    }

    private func copyNWCConnection(_ connection: NWCConnection) {
        UIPasteboard.general.string = settings.nwcConnectionString(for: connection)
        copiedNWCConnectionId = connection.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedNWCConnectionId == connection.id {
                copiedNWCConnectionId = nil
            }
        }
    }

    private func allowanceBinding(for connection: NWCConnection) -> Binding<String> {
        Binding(
            get: { String(connection.allowanceLeft) },
            set: { newValue in
                let digits = newValue.filter { $0.isNumber }
                let amount = Int(digits) ?? 0
                settings.updateNWCAllowance(connectionId: connection.id, allowanceLeft: amount)
            }
        )
    }

    private func showQRCode(title: String, content: String) {
        activeQRPayload = QRPayload(title: title, content: content)
    }
}
