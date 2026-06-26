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
