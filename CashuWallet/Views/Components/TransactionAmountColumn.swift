import SwiftUI

// Shared trailing region for transaction rows on Home and History.
// Renders the amount VStack(sats, optional fiat) — trailing-aligned.
// Amount color is a two-state ledger signal: .primary = settled,
// .secondary = pending. No row badge; pending is conveyed by the muted
// amount alone, and re-check lives on History pull-to-refresh. See
// DESIGN.md — The One Green Rule, The Quiet Pending Rule,
// The Fiat Sub-Amount Rule.
struct TransactionAmountColumn: View {
    let transaction: WalletTransaction

    @ObservedObject var settings: SettingsManager = .shared
    @ObservedObject var priceService: PriceService = .shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(formattedAmount)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .contentTransition(.numericText(value: Double(transaction.amount)))

            if showFiat {
                Text(priceService.formatSatsAsFiat(transaction.amount))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var showFiat: Bool {
        settings.showFiatBalance && priceService.btcPriceUSD > 0
    }

    // Two-state ledger: pending reads muted, everything settled reads
    // .primary. Amounts are never green (see The One Green Rule).
    private var amountColor: Color {
        transaction.status == .pending ? .secondary : .primary
    }

    // The +/− sign is a *settled-ledger* signal: a pending receive hasn't
    // credited the balance and a pending send hasn't debited it, so neither
    // wears a sign until it settles — matching the waiting Cashu Request /
    // Reusable Invoice, which shows a bare amount until paid. The sign and the
    // `.primary` colour arrive together on settlement. See DESIGN.md — The
    // Quiet Pending Rule.
    private var formattedAmount: String {
        let value = settings.formatAmountShort(transaction.amount)
        guard transaction.status != .pending else { return value }
        let prefix = transaction.type == .incoming ? "+" : "−"
        return "\(prefix)\(value)"
    }
}
