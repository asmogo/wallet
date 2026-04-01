import SwiftUI

struct P2PKSettingsSection: View {
    @ObservedObject var settings = SettingsManager.shared

    @Binding var expandedP2PKKeys: Bool
    @Binding var activeQRPayload: QRPayload?
    @Binding var copiedP2PKPublicKey: String?
    @Binding var p2pkImportText: String
    @Binding var showImportP2PK: Bool
    @Binding var p2pkError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("P2PK")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Generate a key pair to receive P2PK-locked ecash. Use only small amounts while this remains experimental.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: generateP2PKKey) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Generate key")
                    }
                    .font(.subheadline)
.foregroundStyle(Color.accentColor)
                }

                Button(action: {
                    p2pkError = nil
                    showImportP2PK = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import nsec")
                    }
                    .font(.subheadline)
.foregroundStyle(Color.accentColor)
                }
            }

            Toggle(isOn: $settings.showP2PKButtonInDrawer.animation(.easeInOut(duration: 0.2))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick access to lock")
                        .font(.subheadline)
                    Text("Show your P2PK locking key in the Receive ecash menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))

            if !settings.p2pkKeys.isEmpty {
                DisclosureGroup(
                    isExpanded: $expandedP2PKKeys.animation(.easeInOut(duration: 0.2)),
                    content: {
                        VStack(spacing: 8) {
                            ForEach(settings.p2pkKeys) { key in
                                GroupBox {
                                    HStack(spacing: 10) {
                                        Button(action: { copyP2PKPublicKey(key.publicKey) }) {
                                            Image(systemName: copiedP2PKPublicKey == key.publicKey ? "checkmark" : "doc.on.doc")
                                                .foregroundColor(copiedP2PKPublicKey == key.publicKey ? .green : Color.accentColor)
                                        }

                                        Text(key.publicKey)
                                            .font(.system(.caption2, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        if key.used {
                                            Text("used")
                                                .font(.caption2)
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.accentColor)
                                                )
                                        }

                                        Spacer()

                                        Button(action: { showQRCode(title: "P2PK Public Key", content: key.publicKey) }) {
                                            Image(systemName: "qrcode")
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    },
                    label: {
                        Text("Browse \(settings.p2pkKeys.count) keys")
                            .font(.caption)
        .foregroundStyle(Color.accentColor)
                    }
                )
                .padding(10)
            }

            if let p2pkError {
                Text(p2pkError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func generateP2PKKey() {
        p2pkError = nil
        guard settings.generateP2PKKey() else {
            p2pkError = "Failed to generate P2PK key."
            return
        }
    }

    private func importP2PKNsec() {
        p2pkError = nil
        do {
            try settings.importP2PKNsec(p2pkImportText)
            p2pkImportText = ""
            showImportP2PK = false
        } catch {
            p2pkError = error.localizedDescription
        }
    }

    private func copyP2PKPublicKey(_ publicKey: String) {
        UIPasteboard.general.string = publicKey
        copiedP2PKPublicKey = publicKey
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedP2PKPublicKey == publicKey {
                copiedP2PKPublicKey = nil
            }
        }
    }

    private func showQRCode(title: String, content: String) {
        activeQRPayload = QRPayload(title: title, content: content)
    }
}
