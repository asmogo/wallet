import SwiftUI

// MARK: - Severity

/// The one severity vocabulary shared by every error surface in the app, and
/// shared by name with Android's `NoticeSeverity`.
///
/// - `error`   — the action failed or is blocked. Something broke.
/// - `caution` — non-blocking "proceed carefully / this won't work here".
///               (Orange also means *pending* elsewhere; the glyph keeps the
///               two distinct.)
/// - `info`    — a neutral precondition, not a failure yet.
/// - `success` — confirmation.
///
/// The *names* match Android. The *glyphs* deliberately do not: Material uses a
/// filled circle for field errors and reserves the triangle for warnings, while
/// Apple leans on the triangle for errors. Each platform follows its own
/// convention — see docs/product/inline-error-fixes.md §2.
enum ErrorSeverity {
    case error, caution, info, success

    var icon: String {
        switch self {
        case .error:   return "exclamationmark.triangle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    /// Text + icon tint. System semantic colours only, so they adapt to dark
    /// mode and Increase Contrast without a custom palette.
    var foreground: Color {
        switch self {
        case .error:   return Color(.systemRed)
        case .caution: return Color(.systemOrange)
        case .info:    return .secondary
        case .success: return Color(.systemGreen)
        }
    }

    /// Prefix spoken by VoiceOver so the tier is announced, not just the message.
    var announcementPrefix: String {
        switch self {
        case .error:   return "Error. "
        case .caution: return "Caution. "
        case .info:    return ""
        case .success: return ""
        }
    }
}

// MARK: - Inline notice (the inline channel)

/// The inline error channel: validation under a control, and preconditions that
/// block the primary action.
///
/// **Never draws a container.** Apple renders validation as plain coloured
/// caption text directly under the control it belongs to — Settings and App
/// Store account creation both do exactly this. A tinted box here would read as
/// someone else's design system.
///
/// The other channels, per docs/product/inline-error-fixes.md §1b:
/// - already happened, nothing to fix → `.errorBanner(_:)`
/// - blocks the whole screen → `ContentUnavailableView`
struct InlineNotice: View {
    let message: String
    /// Optional bold leading line (e.g. "New mint"). When present the `message`
    /// drops to a secondary explanatory body.
    var title: String? = nil
    var severity: ErrorSeverity = .error
    /// Optional second line, always secondary — for amounts / supporting detail.
    var detail: String? = nil
    /// Hide the leading glyph, for footers that read as plain text.
    var showsIcon: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if showsIcon {
                Image(systemName: severity.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(severity.foreground)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(message)
                    .font(title == nil ? .caption : .caption2)
                    .foregroundStyle(title == nil ? severity.foreground : Color.secondary)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .onAppear {
            // Owned here so no call site can forget it. This is exactly what the
            // hand-rolled copy in SendView used to drop.
            guard severity != .info else { return }
            AccessibilityNotification.Announcement(accessibilityText).post()
        }
    }

    private var accessibilityText: String {
        var parts = [severity.announcementPrefix + (title.map { "\($0). " } ?? "") + message]
        if let detail { parts.append(detail) }
        return parts.joined(separator: " ")
    }
}

// MARK: - Banner presentation (the transient channel)

extension View {
    /// Pins a floating error banner to the bottom safe area while `message` is
    /// non-nil. For failures that already happened and have nothing to fix in
    /// place — a backup that failed, a delete that didn't take.
    ///
    /// Do NOT use on screens whose bottom safe area is owned by a primary CTA
    /// (Send/Pay); those use `InlineNotice`.
    func errorBanner(
        _ message: Binding<String?>,
        severity: ErrorSeverity = .error,
        retry: (() -> Void)? = nil
    ) -> some View {
        modifier(ErrorBannerModifier(message: message, severity: severity, retry: retry))
    }
}

/// The floating banner. Not a general-purpose inline component — reach it only
/// through `.errorBanner(_:)`.
///
/// This is the one error surface that genuinely floats over content, so it is
/// the one that takes a material rather than a flat tint, matching the material
/// vocabulary in DESIGN.md. Colour stays on the icon.
struct ErrorBannerView: View {
    let message: String
    var severity: ErrorSeverity = .error
    var retry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: severity.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(severity.foreground)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let retry {
                Button("Retry", action: retry)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(severity.foreground)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(severity.announcementPrefix + message)
        .onAppear {
            guard severity != .info else { return }
            AccessibilityNotification.Announcement(message).post()
        }
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
                        onDismiss: { withAnimation(.snappy) { self.message = nil } }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    // Enter slides up from the bottom edge; exit is a quiet fade
                    // only — the user's focus has already moved on.
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            )
                    )
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: message)
    }
}
