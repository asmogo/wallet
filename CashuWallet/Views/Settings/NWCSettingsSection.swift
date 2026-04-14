import SwiftUI

struct NWCSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    @Binding var nwcError: String?
    @Binding var copiedNWCConnectionId: UUID?
    @Binding var activeQRPayload: QRPayload?

    var body: some View {
        Group {
            Text("Use NWC to control your wallet from compatible applications.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: $settings.enableNWC.animation(.easeInOut(duration: 0.2))) {
                Text("Enable NWC")
            }

            if settings.enableNWC {
                Text("You can only use NWC for payments from your Bitcoin balance on your active mint.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(action: createNWCConnection) {
                    HStack(spacing: 8) {
                        Image(systemName: "link.badge.plus")
                        Text(settings.nwcConnections.isEmpty ? "Create connection" : "Ensure connection")
                    }
                }

                ForEach(settings.nwcConnections) { connection in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Connection")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button(action: { copyNWCConnection(connection) }) {
                                Image(systemName: copiedNWCConnectionId == connection.id ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(copiedNWCConnectionId == connection.id ? .green : Color.accentColor)
                            }
                            .accessibilityLabel("Copy connection string")

                            Button(action: { showQRCode(title: "NWC Connection", content: settings.nwcConnectionString(for: connection)) }) {
                                Image(systemName: "qrcode")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .accessibilityLabel("Show connection QR")

                            Button(action: { settings.removeNWCConnection(connection) }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .accessibilityLabel("Remove connection")
                        }

                        Text(settings.nwcConnectionString(for: connection))
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        LabeledContent("Allowance left (sat)") {
                            TextField("0", text: allowanceBinding(for: connection))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: 100)
                        }
                        .font(.caption2)
                    }
                }

                if let nwcError {
                    Text(nwcError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
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
