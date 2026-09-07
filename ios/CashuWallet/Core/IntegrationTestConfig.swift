import Foundation

/// Configuration for integration testing mode
/// Detected via environment variables set in CI
struct IntegrationTestConfig {
    /// Whether we're running in integration test mode
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CI_INTEGRATION_TEST"] == "1"
    }
    
    /// Nutshell mint URL (typically http://localhost:3338)
    static var nutshellMintURL: String? {
        ProcessInfo.processInfo.environment["NUTSHELL_MINT_URL"]
    }
    
    /// CDK mint URL (typically http://localhost:3339)
    static var cdkMintURL: String? {
        ProcessInfo.processInfo.environment["CDK_MINT_URL"]
    }
    
    /// All configured test mint URLs
    static var testMintURLs: [String] {
        var urls: [String] = []
        if let nutshell = nutshellMintURL {
            urls.append(nutshell)
        }
        if let cdk = cdkMintURL {
            urls.append(cdk)
        }
        return urls
    }
    
    /// Whether to reset wallet state for fresh test runs
    static var shouldResetWallet: Bool {
        ProcessInfo.processInfo.environment["RESET_WALLET"] == "1"
    }

    /// UI tests need a quiescent process. Production-only monitoring, relay
    /// listeners, foreground reconciliation, and animations make XCTest wait
    /// for unrelated work and introduce external-network flakiness.
    static var shouldUseDeterministicUIRuntime: Bool {
        isEnabled
    }

    /// Explicit live-payment tests retain real recovery and local relay listeners.
    /// This is independent of visual determinism and telemetry suppression.
    static var shouldRunPaymentServices: Bool {
        #if DEBUG
        return !isEnabled || ProcessInfo.processInfo.environment["UITEST_LIVE_PAYMENTS"] == "1"
        #else
        return !isEnabled
        #endif
    }

    static var localPaymentTestRelay: String? {
        #if DEBUG
        guard isEnabled, shouldRunPaymentServices,
              let value = ProcessInfo.processInfo.environment["UITEST_PAYMENT_RELAY"],
              let url = URL(string: value), url.scheme == "ws",
              ["localhost", "127.0.0.1"].contains(url.host ?? "") else { return nil }
        return value
        #else
        return nil
        #endif
    }

    static var shouldDisableAnimations: Bool {
        ProcessInfo.processInfo.environment["UITEST_DISABLE_ANIMATIONS"] == "1"
    }

    /// Whether UI tests should skip onboarding and start from a deterministic
    /// empty wallet. This keeps feature tests fast while the onboarding tests
    /// still exercise the real setup flow.
    static var shouldSeedWallet: Bool {
        ProcessInfo.processInfo.environment["UITEST_SEED_WALLET"] == "1"
    }

    /// Whether the seeded UI-test wallet should include a placeholder active
    /// mint. This avoids live network setup for tests that only need receive UI.
    static var shouldSeedMint: Bool {
        ProcessInfo.processInfo.environment["UITEST_SEED_MINT"] == "1"
    }

    /// Deterministic test-only mnemonic. Never use this wallet for real funds.
    static var seedMnemonic: String {
        ProcessInfo.processInfo.environment["UITEST_SEED_MNEMONIC"]
            ?? "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    }

    static var seedMintURL: String? {
        ProcessInfo.processInfo.environment["UITEST_SEED_MINT_URL"] ?? nutshellMintURL
    }

    /// Replaces the app root with the debug component catalog. Used to capture
    /// every inline-error variant for cross-platform comparison; the catalog
    /// itself is `#if DEBUG`, so this never resolves in Release.
    ///
    /// The value names the page — `matrix` (the shared contract) or `variants`
    /// (the hand-rolled facsimiles) — matching the two Android catalog previews
    /// so the platforms pair up one screenshot at a time. Anything else falls
    /// back to `matrix`.
    static var componentCatalogPage: String? {
        ProcessInfo.processInfo.environment["SHOW_COMPONENT_CATALOG"]
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static var shouldShowComponentCatalog: Bool {
        componentCatalogPage != nil
    }
}

extension IntegrationTestConfig {
    /// Helper to check if a specific mint is configured
    static func hasMint(_ name: String) -> Bool {
        switch name.lowercased() {
        case "nutshell":
            return nutshellMintURL != nil
        case "cdk":
            return cdkMintURL != nil
        default:
            return false
        }
    }
}
