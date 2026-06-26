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
            options.profilesSampleRate = 0.0
        }
        SentrySDK.capture(message: "Sentry initialized — test event") // TODO: remove after confirming
    }

    static func shutdown() {
        SentrySDK.close()
    }

    static func capture(_ error: Error) {
        guard SettingsStore.shared.sentryEnabled else { return }
        SentrySDK.capture(error: error)
    }

    static func breadcrumb(_ message: String, category: String = "wallet") {
        guard SettingsStore.shared.sentryEnabled else { return }
        let crumb = Breadcrumb()
        crumb.message = message
        crumb.category = category
        crumb.level = .info
        SentrySDK.addBreadcrumb(crumb)
    }
}
