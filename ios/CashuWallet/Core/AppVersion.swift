import Foundation

/// Sources the displayed app version from bundle metadata (CFBundleShortVersionString,
/// CFBundleVersion) instead of a hard-coded literal — the iOS counterpart of Android
/// rendering BuildConfig.VERSION_NAME in Settings.
enum AppVersion {
    /// Version string for the Settings footer, e.g. "1.0". Nil when the bundle carries
    /// no marketing version, so callers can omit the version rather than show a stale one.
    static func displayString(bundle: Bundle = .main) -> String? {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return displayString(version: version)
    }

    static func displayString(version: String?) -> String? {
        guard let version, !version.isEmpty else { return nil }
        return version
    }
}
