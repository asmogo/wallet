#if canImport(CoreNFC)
import CoreNFC
#endif

/// Whether tap-to-pay can be offered at all.
///
/// Macs have no NFC radio, and older iPhones report the same "unavailable"
/// answer, so the two cases collapse into one question the UI already knew how
/// to ask. Views call this instead of touching `NFCNDEFReaderSession` directly,
/// which is what keeps the Send sheet free of platform branches.
enum ContactlessPayments {
    static var isAvailable: Bool {
        #if canImport(CoreNFC)
        return NFCNDEFReaderSession.readingAvailable
        #else
        return false
        #endif
    }
}
