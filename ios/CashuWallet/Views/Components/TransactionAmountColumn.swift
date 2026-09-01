import SwiftUI

// Shared trailing region for transaction rows on Home and History.
// Renders the configured primary amount plus its optional conversion —
// trailing-aligned.
// Amount styling is the ledger signal: received = green with a plus, sent =
// primary with no sign, pending/expired = muted with no sign. No row badge;
// re-check lives on History pull-to-refresh. See DESIGN.md — The Received
// Amount Rule, The Quiet Pending Rule,
// The Fiat Sub-Amount Rule.
struct TransactionAmountColumn: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let transaction: WalletTransaction

    @ObservedObject var settings: SettingsManager = .shared
    @ObservedObject var priceService: PriceService = .shared

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .trailing, spacing: 2) {
                // The Row rung of the amount ladder. It carries the tabular figures,
                // the line limit, the digit transition and the deliberate absence of
                // autoscale — see `CashuTextRole.amountRow`, which documents why
                // those last two cannot both be on.
                Text(formattedAmount)
                    .cashuAmount(.amountRow, value: Double(transaction.amount))
                    .foregroundStyle(amountColor)

                if let secondaryAmount {
                    Text(secondaryAmount)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .id(settings.homeBalancePrimary)
            .transition(.opacity)
        }
        .animation(swapAnimation, value: settings.homeBalancePrimary)
    }

    // Received value is the only green element in the row. Sent value stays
    // primary; unsettled (pending or expired) stays muted.
    private var amountColor: Color {
        if transaction.isUnsettled { return .secondary }
        return transaction.type == .incoming ? .green : .primary
    }

    // Only a settled receipt gets a sign. Sent, pending, and expired rows stay
    // unsigned; direction remains explicit in the title and arrow.
    private var formattedAmount: String {
        let value = amountDisplay.primary
        guard !transaction.isUnsettled, transaction.type == .incoming else { return value }
        return "+\(value)"
    }

    private var secondaryAmount: String? {
        amountDisplay.secondary
    }

    private var amountDisplay: AmountDisplayText {
        AmountFormatter.displayMintUnitAmount(
            amount: transaction.amount,
            unit: transaction.unit,
            preferredPrimary: settings.homeBalancePrimary,
            showFiat: settings.showFiatBalance,
            btcPrice: priceService.btcPriceUSD,
            currencyCode: settings.bitcoinPriceCurrency,
            useBitcoinSymbol: settings.useBitcoinSymbol
        )
    }

    private var swapAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .snappy
    }
}
