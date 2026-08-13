#if canImport(UIKit)
import UIKit
#endif

/// Centralized haptic feedback utility following Apple HIG
///
/// On macOS every call is a no-op. The signatures are kept so shared views need
/// no platform branches, and the shim types they reference live in
/// MacUIKitCompat.swift — see there for why routing these to a trackpad would
/// be the wrong call rather than merely an unimplemented one.
enum HapticFeedback {
    /// Light impact — for UI selections, toggles
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
        #endif
    }

    /// Notification feedback — for success, error, warning outcomes
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
        #endif
    }

    /// Selection changed — for picker/selection changes
    static func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }
}
