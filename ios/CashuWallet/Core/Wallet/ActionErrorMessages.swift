import Foundation

/// Context for settings failures. Unrecognized technical details never become UI copy.
enum ActionErrorMessages {
    enum Context {
        case lightningConnection
        case lightningPayments
        case lightningMint
        case walletConnect
        case mintBackup
        case keyUpdate
        case keyGenerate
        case keyImport
        case keyRemove
        case keyRename

        var fallback: String {
            switch self {
            case .lightningConnection: "Couldn't connect to the Lightning address service. Try again shortly."
            case .lightningPayments: "Couldn't check for Lightning payments. Try again shortly."
            case .lightningMint: "Couldn't change your receiving mint. Try again shortly."
            case .walletConnect: "Couldn't start Wallet Connect. Check your relays and try again."
            case .mintBackup: "Couldn't back up your mint list. Check your relays and try again."
            case .keyUpdate: "Couldn't update your Nostr key. Try again."
            case .keyGenerate: "Couldn't generate a key. Try again."
            case .keyImport: "Couldn't import this key. Check it and try again."
            case .keyRemove: "Couldn't remove this key. Try again."
            case .keyRename: "Couldn't save the key name. Try again."
            }
        }
    }

    static func message(for error: Error, context: Context) -> String {
        let raw = (String(describing: error) + " " + error.localizedDescription).lowercased()
        if context == .keyImport {
            if raw.contains("already") && ["exist", "added", "wallet"].contains(where: raw.contains) {
                return "This key is already in your wallet."
            }
            let invalidKey = raw.contains("invalid") && ["nsec", "private key", "privatekey", "padding"].contains(where: raw.contains)
            let invalidEncoding = ["bech32", "nsec"].contains(where: raw.contains) &&
                ["decode", "decoding", "checksum"].contains(where: raw.contains)
            if invalidKey || invalidEncoding {
                return "That private key doesn't look right. Check that you copied the complete nsec key."
            }
        }
        if [.keyUpdate, .keyGenerate, .keyImport].contains(context),
           ["not initialized", "no wallet seed", "no seed available"].contains(where: raw.contains) {
            return "Your wallet is still starting up. Try again shortly."
        }
        return context.fallback
    }
}
