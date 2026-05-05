import CoreNFC
import Foundation

enum NDEFTextRecord {
    static func extractText(from message: NFCNDEFMessage) -> String? {
        for record in message.records {
            if let text = extractText(from: record) {
                return text
            }
        }
        return nil
    }

    private static func extractText(from record: NFCNDEFPayload) -> String? {
        if record.typeNameFormat == .nfcWellKnown {
            if let type = String(data: record.type, encoding: .utf8), type == "T" {
                let payload = record.payload
                guard payload.count > 0 else { return nil }

                let statusByte = payload[0]
                let languageCodeLength = Int(statusByte & 0x3F)

                guard payload.count > 1 + languageCodeLength else { return nil }

                let textData = payload.dropFirst(1 + languageCodeLength)
                return String(data: Data(textData), encoding: .utf8)
            }

            if let type = String(data: record.type, encoding: .utf8), type == "U" {
                if let uri = record.wellKnownTypeURIPayload()?.absoluteString {
                    return uri
                }
            }
        }

        if record.typeNameFormat == .nfcExternal {
            if let text = String(data: record.payload, encoding: .utf8) {
                return text
            }
        }

        if record.typeNameFormat == .media {
            if let text = String(data: record.payload, encoding: .utf8) {
                return text
            }
        }

        if let text = String(data: record.payload, encoding: .utf8), !text.isEmpty {
            return text
        }

        return nil
    }

    static func makeMessage(with text: String) -> NFCNDEFMessage {
        let languageCode = "en"
        let languageCodeData = languageCode.data(using: .utf8)!
        let textData = text.data(using: .utf8)!
        let statusByte = UInt8(languageCodeData.count & 0x3F)

        var payload = Data()
        payload.append(statusByte)
        payload.append(languageCodeData)
        payload.append(textData)

        let record = NFCNDEFPayload(
            format: .nfcWellKnown,
            type: "T".data(using: .utf8)!,
            identifier: Data(),
            payload: payload
        )

        return NFCNDEFMessage(records: [record])
    }
}
