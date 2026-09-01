#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Why this file exists
//
// The wallet is one codebase shipping to iPhone and to the Mac menu bar. The
// alternative to this file was rewriting ~35 view files to call platform-neutral
// wrappers; instead the handful of UIKit names those files already use are
// reproduced here, mapped onto their AppKit equivalents. The views compile
// unchanged and the port stays reviewable.
//
// The rule for anything added here: it must be a faithful mapping or an honest
// no-op. A shim that silently changes behaviour is worse than a compile error,
// because the compile error is the thing that would have told us to look.

// MARK: - Images

typealias UIImage = NSImage

extension NSImage {
    /// UIKit's parameterless `cgImage` initialiser. AppKit requires an explicit
    /// size, so take the bitmap's own pixel dimensions — the callers here are
    /// decoding downloaded mint icons and generated QR codes, where the pixel
    /// grid *is* the intended size.
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

extension Image {
    /// Lets `Image(uiImage:)` call sites stand.
    init(uiImage: NSImage) {
        self.init(nsImage: uiImage)
    }
}

// MARK: - Colors

typealias UIColor = NSColor

extension NSColor {
    /// UIKit spells the window/base background `systemBackground`.
    static var systemBackground: NSColor { .windowBackgroundColor }

    /// UIKit spells the hairline divider `separator`.
    static var separator: NSColor { .separatorColor }

    /// UIKit omits the `Color` suffix from its semantic label colors.
    static var quaternaryLabel: NSColor { .quaternaryLabelColor }
}

extension Color {
    /// Lets `Color(uiColor:)` call sites stand.
    init(uiColor: NSColor) {
        self.init(nsColor: uiColor)
    }
}

// MARK: - Fonts and Dynamic Type
//
// macOS has no Dynamic Type. Every size resolves to the system default, so the
// shared typography maths in CashuTypography.swift stays honest: it computes
// against a fixed scale rather than a scale that silently lies.

typealias UIFont = NSFont

enum UIContentSizeCategory {
    case extraSmall, small, medium, large, extraLarge, extraExtraLarge
    case extraExtraExtraLarge
    case accessibilityMedium, accessibilityLarge, accessibilityExtraLarge
    case accessibilityExtraExtraLarge, accessibilityExtraExtraExtraLarge
}

struct UITraitCollection {
    let preferredContentSizeCategory: UIContentSizeCategory

    init(preferredContentSizeCategory: UIContentSizeCategory) {
        self.preferredContentSizeCategory = preferredContentSizeCategory
    }
}

extension NSFont {
    /// UIKit exposes the full line box on the font; AppKit leaves it to the
    /// layout manager. Ascender + |descender| + leading is that same box.
    var lineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }

    /// The trait argument is inert here — see the Dynamic Type note above.
    static func preferredFont(
        forTextStyle style: NSFont.TextStyle,
        compatibleWith _: UITraitCollection?
    ) -> NSFont {
        preferredFont(forTextStyle: style)
    }
}

/// Stands in for `UIFontMetrics`. With no Dynamic Type to scale against, the
/// scaled value is the base value.
struct UIFontMetrics {
    init(forTextStyle _: NSFont.TextStyle) {}

    func scaledValue(for value: CGFloat, compatibleWith _: UITraitCollection?) -> CGFloat {
        value
    }
}

// MARK: - Pasteboard

/// `NSPasteboard` is change-count based rather than a live string property, so
/// this wrapper restores UIKit's read/write shape. Writing clears first, which
/// is mandatory on AppKit — without it the new string is appended to the
/// existing pasteboard contents rather than replacing them.
enum UIPasteboard {
    struct Proxy {
        var string: String? {
            get { NSPasteboard.general.string(forType: .string) }
            nonmutating set {
                NSPasteboard.general.clearContents()
                guard let newValue else { return }
                NSPasteboard.general.setString(newValue, forType: .string)
            }
        }

        var hasStrings: Bool {
            NSPasteboard.general.string(forType: .string)?.isEmpty == false
        }
    }

    static let general = Proxy()
}

// MARK: - Haptics
//
// Macs without a Force Touch trackpad have nowhere to play these, and the
// wallet's haptics are all confirmation flourishes on top of a visible state
// change. No-ops rather than NSHapticFeedbackManager: routing a "token sent"
// bump to a trackpad the user may not be touching is noise, not feedback.

enum UIImpactFeedbackGenerator {
    enum FeedbackStyle { case light, medium, heavy, rigid, soft }
}

enum UINotificationFeedbackGenerator {
    enum FeedbackType { case success, warning, error }
}

// MARK: - Animation gate

/// The integration-test hook that disables animations app-wide. SwiftUI's own
/// `transaction.disablesAnimations` still carries the load on macOS; this only
/// exists so the call site in the app entry point compiles.
enum UIView {
    static func setAnimationsEnabled(_ enabled: Bool) {
        NSAnimationContext.current.duration = enabled ? 0.25 : 0
    }
}

// MARK: - Screen

enum UIScreen {
    struct Descriptor {
        /// Backing scale of the screen the app is actually on, falling back to
        /// the main screen and then to 2x. Used to render QR codes at native
        /// resolution, so guessing low would visibly soften them.
        var scale: CGFloat {
            NSApp?.keyWindow?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
        }
    }

    static let main = Descriptor()
}
#endif
