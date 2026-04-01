import os

/// Structured logging using os.Logger for diagnostics and debugging
enum AppLogger {
    static let wallet = Logger(subsystem: "com.cashu.wallet", category: "wallet")
    static let network = Logger(subsystem: "com.cashu.wallet", category: "network")
    static let security = Logger(subsystem: "com.cashu.wallet", category: "security")
    static let ui = Logger(subsystem: "com.cashu.wallet", category: "ui")
}
