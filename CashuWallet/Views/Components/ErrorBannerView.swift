import SwiftUI

// MARK: - Severity

/// The one severity vocabulary shared by every error surface in the app.
///
/// - `error`   — the action is blocked or just failed. Saturated red.
/// - `caution` — non-blocking "proceed carefully / this won't work here". Orange.
///               (Orange also means *pending* elsewhere; the warning-triangle vs
///               pending clock-badge iconography keeps the two distinct.)
/// - `info`    — validation-in-progress that isn't a failure yet. Quiet secondary,
///               never a saturated hue.
enum ErrorSeverity {
    case error, caution, info

    var icon: String {
        switch self {
        case .error:   return "exclamationmark.triangle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    /// Text + icon tint. Maps to DESIGN.md state tokens.
    var foreground: Color {
        switch self {
        case .error:   return Color(.systemRed)   // state-error  #FF3B30
        case .caution: return .orange             // state-pending #FF9500
        case .info:    return .secondary          // no saturated hue
        }
    }

    /// Surface fill behind a tinted notice/banner. Maps to the *-tint tokens.
    var tint: Color {
        switch self {
        case .error:   return Color(.systemRed).opacity(0.18)  // error-tint   #FF3B302E
        case .caution: return Color.orange.opacity(0.10)       // pending-tint #FF95001A
        case .info:    return Color(.secondarySystemBackground)
        }
    }

    /// Prefix spoken by VoiceOver so the tier is announced, not just the message.
    var announcementPrefix: String {
        switch self {
        case .error:   return "Error. "
        case .caution: return "Caution. "
        case .info:    return ""
        }
    }
}

// MARK: - Shared banner (async / system failures, screen-level)

/// Standardized error/info banner for async or system *failures* not tied to a
/// single control (mint unreachable, payment failed, backup failed). Prefer the
/// `.errorBanner(_:)` modifier to pin it to the bottom safe area; place it inline
/// only where the layout already reserves a slot for it.
struct ErrorBannerView: View {
    let message: String
    var severity: ErrorSeverity = .error
    var retry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: severity.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(severity.foreground)
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote)
                .foregroundStyle(severity.foreground)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let retry {
                Button("Retry", action: retry)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(severity.foreground)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(severity.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(severity.announcementPrefix + message)
        .onAppear {
            guard severity != .info else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }
}

// MARK: - Inline notice (preconditions / validation, tied to a control)

/// A calm, control-tied notice for preconditions and validation feedback — the
/// thing that sits directly under a field or amount and tells the user why they
/// can't proceed yet, plus what to do about it.
///
/// Defaults to a bare caption (no box) so most sites stay quiet; opt into
/// `tinted` only where the message deserves a surface (e.g. an insufficient-
/// balance notice carrying amounts and an action).
struct InlineNotice: View {
    let message: String
    var severity: ErrorSeverity = .error
    /// Optional second line, always secondary — for amounts / supporting detail.
    var detail: String? = nil
    /// Hide the leading glyph (e.g. the seed word-counter, which reads as plain text).
    var showsIcon: Bool = true
    /// Wrap in a 12pt tint surface. Off by default to preserve the existing calm look.
    var tinted: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if showsIcon {
                Image(systemName: severity.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(severity.foreground)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(severity.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(tinted ? 10 : 0)
        .background(
            tinted ? AnyShapeStyle(severity.tint) : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [severity.announcementPrefix + message]
        if let detail { parts.append(detail) }
        return parts.joined(separator: " ")
    }
}

// MARK: - Banner presentation modifier

extension View {
    /// Pins the shared error banner to the bottom safe area while `message` is
    /// non-nil. Reuses an existing `@State var errorMessage: String?` — no new
    /// observable object. Use for screen-level/async failures; do NOT use on
    /// screens whose bottom safe area is owned by a primary CTA (Send/Pay) —
    /// those use `InlineNotice` instead.
    func errorBanner(
        _ message: Binding<String?>,
        severity: ErrorSeverity = .error,
        retry: (() -> Void)? = nil
    ) -> some View {
        modifier(ErrorBannerModifier(message: message, severity: severity, retry: retry))
    }
}

private struct ErrorBannerModifier: ViewModifier {
    @Binding var message: String?
    var severity: ErrorSeverity
    var retry: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let message {
                    ErrorBannerView(
                        message: message,
                        severity: severity,
                        retry: retry,
                        onDismiss: { withAnimation { self.message = nil } }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: message)
    }
}
