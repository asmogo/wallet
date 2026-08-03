import SwiftUI

/// Inline-error parity catalog. Debug-only, reachable exclusively via
/// `SHOW_COMPONENT_CATALOG=1`, and compiled out of Release entirely.
///
/// Mirrors the Android `InlineErrorCatalogTest` previews one section at a time
/// so the two platforms can be read side by side. Two things are being shown:
///
/// 1. The shared contract — `InlineNotice` in every severity, tinted and
///    untinted, plus `ErrorBannerView`, which is the *second* inline error
///    surface iOS ships and which Android has no counterpart for.
/// 2. Facsimiles of the hand-rolled inline errors that bypass both. The
///    originals are `private` members of their screens and cannot be called
///    from here, so each is REPRODUCED from its source and labelled with it.
///    They evidence the styling divergence; they are not the live views.
///
/// See docs/product/inline-error-audit.md.
#if DEBUG
struct ComponentCatalogView: View {
    /// Which page to render. Split in two so each fits one screenshot without
    /// scrolling, and so each pairs with its Android counterpart.
    enum Page {
        case matrix, variants

        init(rawValue: String?) {
            self = rawValue == "variants" ? .variants : .matrix
        }
    }

    var page: Page = .matrix

    private let insufficient = "Insufficient balance"
    private let insufficientDetail = "You have 21,000 sat in Testnut mint."

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch page {
            case .matrix:
                noticeMatrix
                bannerSection
            case .variants:
                handRolledVariants
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared contract

    private var noticeMatrix: some View {
        Group {
            section("InlineNotice — untinted (iOS default)") {
                InlineNotice(message: "Couldn't reach the mint.", severity: .error)
                InlineNotice(
                    message: insufficient,
                    severity: .caution,
                    detail: insufficientDetail
                )
                InlineNotice(
                    message: "This request asks for a mint you have not added yet.",
                    severity: .info
                )
                // iOS has no .success case; Android's NoticeSeverity does.
            }

            section("InlineNotice — tinted (Android default)") {
                InlineNotice(message: "Couldn't reach the mint.", severity: .error, tinted: true)
                InlineNotice(
                    message: insufficient,
                    severity: .caution,
                    detail: insufficientDetail,
                    tinted: true
                )
                InlineNotice(
                    message: "This request asks for a mint you have not added yet.",
                    severity: .info,
                    tinted: true
                )
            }

            section("InlineNotice — titled (no Android equivalent)") {
                InlineNotice(
                    message: "You haven't used testnut.cashu.space before. Receiving adds it to your wallet.",
                    title: "New mint",
                    severity: .caution,
                    tinted: true
                )
            }
        }
    }

    private var bannerSection: some View {
        section("ErrorBannerView — the second iOS surface (Android has none)") {
            ErrorBannerView(message: "Couldn't reach the mint.", severity: .error)
            ErrorBannerView(message: insufficient, severity: .caution)
            ErrorBannerView(message: "Backup failed.", severity: .error, retry: {})
        }
    }

    // MARK: - Hand-rolled facsimiles

    private var handRolledVariants: some View {
        Group {
            section("H1 — sendInputNotice, a clone of InlineNotice (SendView.swift:294)") {
                // .top/8 instead of .firstTextBaseline/6, and no VoiceOver
                // "Caution. " prefix, which the real InlineNotice supplies.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: ErrorSeverity.caution.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ErrorSeverity.caution.foreground)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insufficient)
                            .font(.caption)
                            .foregroundStyle(ErrorSeverity.caution.foreground)
                        Text(insufficientDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ErrorSeverity.caution.tint,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

            section("H2 — bare red caption row (SendView.swift:3289)") {
                // Color.red, not Color(.systemRed); and the *caution* glyph,
                // unfilled, paired with error red.
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption.weight(.semibold))
                    Text("Unrecognized — try a Lightning address, invoice, or Cashu Request")
                        .font(.caption)
                }
                .foregroundStyle(Color.red)
            }

            section("H4 — solid-red scanner block (ScannerWrapperView.swift:275)") {
                // No icon, no severity tint, default body font, radius 10 not 12.
                Text("No valid mint URL found in QR code.")
                    .foregroundStyle(.primary)
                    .padding()
                    .background(Color.red)
                    .clipShape(.rect(cornerRadius: 10))
            }

            section("H6 — no severity signal at all (AmountEntryView.swift:157)") {
                // Same string as the canonical notice, rendered as plain
                // secondary text. Dead code — no production call site.
                Text(insufficient)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            section("Reference — the shared component the above should have used") {
                InlineNotice(
                    message: insufficient,
                    severity: .caution,
                    detail: insufficientDetail,
                    tinted: true
                )
            }
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func section<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Inline error catalog — matrix") {
    ComponentCatalogView(page: .matrix)
}

#Preview("Inline error catalog — variants") {
    ComponentCatalogView(page: .variants)
}
#endif
