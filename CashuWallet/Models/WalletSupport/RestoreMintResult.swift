import Foundation

struct RestoreMintResult: Identifiable {
    var id: String { mintUrl }
    let mintUrl: String
    let mintName: String
    let spent: UInt64
    let unspent: UInt64
    let pending: UInt64

    var totalRecovered: UInt64 { unspent + pending }
}

/// Token parsed information
