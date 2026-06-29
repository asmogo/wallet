import Foundation

struct RestoreMintResult: Identifiable {
    var id: String { mintUrl }
    let mintUrl: String
    let mintName: String
    /// The mint's own logo, fetched alongside the name during restore. Lets the
    /// completed row show the real mint icon (falling back to a monogram avatar).
    var iconUrl: String? = nil
    let spent: UInt64
    let unspent: UInt64
    let pending: UInt64

    var totalRecovered: UInt64 { unspent + pending }
}

/// Per-mint state on the dedicated restore/results screen (shared by the
/// Onboarding and Settings restore twins). Drives the row UI: spinner while
/// pending/restoring, recovered amount when done, error + Retry on failure.
enum MintRestorePhase {
    case pending
    case restoring
    case recovered(RestoreMintResult)
    case failed(String)            // user-facing message
}

/// Token parsed information
