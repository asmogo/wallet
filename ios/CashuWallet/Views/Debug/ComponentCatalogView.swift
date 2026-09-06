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
        case matrix, variants, activity

        init(rawValue: String?) {
            self = rawValue == "activity" ? .activity : rawValue == "variants" ? .variants : .matrix
        }
    }

    var page: Page = .matrix

    private let insufficient = "Insufficient balance"
    private let insufficientDetail = "You have 21,000 sat in Testnut mint."

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch page {
            case .activity:
                ActivityDetailCatalog()
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
            section("InlineNotice — the inline channel (never boxed)") {
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
                InlineNotice(message: "Backed up to your relays.", severity: .success)
            }

            section("Titled variant") {
                InlineNotice(
                    message: "You haven't used testnut.cashu.space before. Receiving adds it to your wallet.",
                    title: "New mint",
                    severity: .caution
                )
            }
        }
    }

    private var bannerSection: some View {
        section("ErrorBannerView — the floating channel, on .regularMaterial") {
            ErrorBannerView(message: "Couldn't reach the mint.", severity: .error)
            ErrorBannerView(message: "Backup failed.", severity: .error, retry: {})
        }
    }

    // MARK: - Hand-rolled facsimiles

    private var handRolledVariants: some View {
        Group {
            section("H1 — FIXED: SendView now uses the shared component (SendView.swift:294)") {
                // Was a hand-rolled copy with .top/8 spacing that silently
                // dropped the VoiceOver "Caution. " prefix.
                InlineNotice(
                    message: insufficient,
                    severity: .caution,
                    detail: insufficientDetail
                )
            }

            section("H2 — FIXED: semantic red + the severity's own glyph (SendView.swift:3263)") {
                // Was Color.red paired with the unfilled *caution* circle.
                HStack(spacing: 6) {
                    Image(systemName: ErrorSeverity.error.icon)
                        .font(.caption.weight(.semibold))
                    Text("Unrecognized — try a Lightning address, invoice, or Cashu Request")
                        .font(.caption)
                }
                .foregroundStyle(ErrorSeverity.error.foreground)
            }

            section("H4 — FIXED: scanner overlay is the shared banner (ScannerWrapperView.swift:275)") {
                // Was a solid Color.red slab, no icon, radius 10. Then briefly a
                // hand-rolled copy of ErrorBannerView's body; now the component.
                ErrorBannerView(message: "No valid mint URL found in QR code.", severity: .error)
            }

            section("Severity glyphs — Apple's convention, deliberately not Material's") {
                ForEach(["error", "caution", "info", "success"], id: \.self) { name in
                    let sev: ErrorSeverity = name == "error" ? .error
                        : name == "caution" ? .caution
                        : name == "info" ? .info : .success
                    HStack(spacing: 8) {
                        Image(systemName: sev.icon)
                            .foregroundStyle(sev.foreground)
                        Text("\(name) — \(sev.icon)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

/// Deterministic receipts for native UI checks; no wallet initialization or mint is needed.
private struct ActivityDetailCatalog: View {
    @State private var selectedTransaction: WalletTransaction?
    @State private var selectedRequest: CashuRequest?
    private let date = Date(timeIntervalSince1970: 1_788_768_000)

    private var transactions: [WalletTransaction] {
        [
            .init(id: "pending-lightning", amount: 2100, type: .incoming, kind: .lightning,
                  date: date, memo: "Coffee payment", status: .pending,
                  mintUrl: "https://mint.example", invoice: "lnbc1test", isUnpaidInvoice: true),
            .init(id: "paid-lightning", amount: 2100, type: .incoming, kind: .lightning,
                  date: date, memo: "Coffee payment", status: .completed,
                  mintUrl: "https://mint.example", invoice: "lnbc1test"),
            .init(id: "sent-lightning", amount: 2100, type: .outgoing, kind: .lightning,
                  date: date, status: .completed, mintUrl: "https://mint.example",
                  preimage: "0123456789abcdef0123456789abcdef", fee: 2),
            .init(id: "pending-ecash", amount: 2100, type: .outgoing, kind: .ecash,
                  date: date, status: .pending, mintUrl: "https://mint.example", token: "cashu-token"),
            .init(id: "received-ecash", amount: 2100, type: .incoming, kind: .ecash,
                  date: date, status: .completed, mintUrl: "https://mint.example", token: "cashu-token"),
            .init(id: "received-bitcoin", amount: 2100, type: .incoming, kind: .onchain,
                  date: date, status: .completed, mintUrl: "https://mint.example",
                  preimage: "0123456789abcdef0123456789abcdef", invoice: "bc1qfixture"),
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Activity details").font(.title)
            ForEach(transactions) { transaction in
                Button(transaction.displayTitle) { selectedTransaction = transaction }
                    .accessibilityIdentifier(transaction.id)
            }
            Button("Reusable Invoice") {
                selectedRequest = CashuRequest(
                    id: "catalog-offer", encoded: "lno1fixture", mints: ["https://mint.example"],
                    memo: "Coffee tips", createdAt: date,
                    receivedPayments: [.init(transactionId: "fixture-payment", amount: 2100, receivedAt: date)],
                    rail: .bolt12, reusable: true
                )
            }
            .accessibilityIdentifier("reusable-invoice")
        }
        .sheet(item: $selectedTransaction) { TransactionDetailView(transaction: $0) }
        .sheet(item: $selectedRequest) { CashuRequestReceiptView(request: $0) }
    }
}

#Preview("Inline error catalog — matrix") {
    ComponentCatalogView(page: .matrix)
}

#Preview("Inline error catalog — variants") {
    ComponentCatalogView(page: .variants)
}
#endif
