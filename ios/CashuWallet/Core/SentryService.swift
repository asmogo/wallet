import Foundation
import Sentry

enum SentryService {
    // Replace with your DSN from sentry.io → Settings → Projects → apple-ios → Client Keys (DSN)
    private static let dsn =
        "https://aff293071a9e53305e76990761d4b38f@o4511625394061312.ingest.de.sentry.io/4511625402712144"

    static func initialize() {
        guard SettingsStore.shared.sentryEnabled else { return }
        SentrySDK.start { options in
            options.dsn = Self.dsn
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.enableAutoSessionTracking = true
            options.tracesSampleRate = 0.1
        }
    }

    static func shutdown() {
        SentrySDK.close()
    }

    static func capture(_ error: Error) {
        guard SettingsStore.shared.sentryEnabled else { return }
        SentrySDK.capture(error: CrashReportSanitizer.error(error))
    }

    static func breadcrumb(_ message: String, category: String = "wallet") {
        guard SettingsStore.shared.sentryEnabled else { return }
        let crumb = Breadcrumb()
        crumb.message = CrashReportSanitizer.message(message)
        crumb.category = category
        crumb.level = .info
        SentrySDK.addBreadcrumb(crumb)
    }
}

/// Removes known wallet secrets and payment payloads at the explicit crash-report boundary.
///
/// Keep this independent of Sentry so the redaction contract can be unit tested without
/// starting the SDK. Unknown error metadata is intentionally discarded: `NSError.userInfo`
/// may contain the same request data that caused the failure.
enum CrashReportSanitizer {
    private struct Replacement {
        let expression: NSRegularExpression
        let template: String

        init(_ pattern: String, template: String, caseInsensitive: Bool = true) {
            expression = try! NSRegularExpression(
                pattern: pattern,
                options: caseInsensitive ? [.caseInsensitive] : []
            )
            self.template = template
        }
    }

    private static let replacements = [
        Replacement(#"\bnostr\+walletconnect://[^\s,;)\"']+"#, template: "<redacted-nwc-uri>"),
        Replacement(#"\bnsec1[023456789acdefghjklmnpqrstuvwxyz]+\b"#, template: "<redacted-nsec>"),
        Replacement(#"\bcashu[ab][a-z0-9_\-=]{16,}\b"#, template: "<redacted-cashu-token>"),
        Replacement(#"\bcreq(?:a|b1)[a-z0-9_\-=]{8,}\b"#, template: "<redacted-cashu-request>"),
        Replacement(#"\b(?:lnbc|lntb|lnbcrt|lno|lni|lnr|lnurl)[a-z0-9]{16,}\b"#, template: "<redacted-lightning-payload>"),
        Replacement(#"\bbitcoin:(?://)?[^\s,;)\"']+"#, template: "<redacted-bitcoin-uri>"),
        Replacement(#"\b(?:bc1|tb1|bcrt1)[a-z0-9]{20,}\b"#, template: "<redacted-bitcoin-address>"),
        Replacement(#"\b[13mn2][a-km-zA-HJ-NP-Z1-9]{25,34}\b"#, template: "<redacted-bitcoin-address>", caseInsensitive: false),
        Replacement(#"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#, template: "<redacted-email>"),
        Replacement(#"https?://[^\s,;)\"']+"#, template: "<redacted-url>"),
        Replacement(#"(?<![A-Za-z0-9])/(?:Users|private|data|var|tmp|storage|sdcard)/[^\s,;)\"']+"#, template: "<redacted-path>", caseInsensitive: false),
        Replacement(
            #"\b(mnemonic|seed phrase|private key|secret)\s*[:=]\s*([^\s,;]+(?:\s+[^\s,;]+){0,23})"#,
            template: "$1=<redacted>"
        ),
    ]

    static func message(_ message: String) -> String {
        replacements.reduce(message) { result, replacement in
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            return replacement.expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement.template
            )
        }
    }

    static func error(_ error: Error) -> NSError {
        let original = error as NSError
        let typeName = String(reflecting: type(of: error))
        return NSError(
            domain: "CashuWallet.SanitizedError",
            code: original.code,
            userInfo: [NSLocalizedDescriptionKey: "\(typeName): \(message(original.localizedDescription))"]
        )
    }
}
