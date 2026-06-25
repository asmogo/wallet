import Foundation
import Cdk

extension WalletManager {
    // MARK: - Backup

    func getMnemonicWords() -> [String] {
        return mnemonic?.split(separator: " ").map(String.init) ?? []
    }

    func validateMnemonic(_ phrase: String) -> Bool {
        let normalizedPhrase = normalizeMnemonic(phrase)
        let words = normalizedPhrase.split(separator: " ").map(String.init)
        guard words.count == 12 || words.count == 24 else { return false }
        guard words.allSatisfy({ bip39WordList.contains($0) }) else { return false }
        return (try? Cdk.mnemonicToEntropy(mnemonic: normalizedPhrase)) != nil
    }

    /// Validate individual words and return which ones are invalid
    func invalidMnemonicWords(_ phrase: String) -> [Int] {
        let words = normalizeMnemonic(phrase).split(separator: " ").map(String.init)
        return words.enumerated().compactMap { index, word in
            bip39WordList.contains(word) ? nil : index
        }
    }

    func normalizeMnemonic(_ phrase: String) -> String {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
