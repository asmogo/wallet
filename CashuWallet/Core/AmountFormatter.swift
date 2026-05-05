import Foundation

enum AmountFormatter {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    static func sats(_ sats: UInt64, useBitcoinSymbol: Bool, includeUnit: Bool = true) -> String {
        let formatted = decimalFormatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
        if useBitcoinSymbol {
            return "₿\(formatted)"
        }
        return includeUnit ? "\(formatted) sat" : formatted
    }
}
