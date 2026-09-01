import SwiftUI

// Shared trailing region for Cashu Request rows in History.
// - Received: green +amount + muted converted sub-line.
// - Waiting (fixed amount): muted amount + fiat, no indicator (gray = waiting).
// - Waiting (any amount, no fixed expected total): no trailing element.
// Primary and secondary values use neighboring type sizes and weights so they
// read as one amount block. See DESIGN.md —
// The Amount Column Rule, The One Green Rule, The Fiat Sub-Amount Rule.
struct CashuRequestAmountColumn: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: CashuRequest
    let received: Bool
    let receivedAmount: UInt64

    @ObservedObject var settings: SettingsManager = .shared
    @ObservedObject var priceService: PriceService = .shared

    @ViewBuilder
    var body: some View {
        if received {
            let display = amountDisplay(receivedAmount)
            animatedAmountPair(display: display, amount: receivedAmount, received: true)
        } else if let amount = request.amount, amount > 0 {
            let display = amountDisplay(amount)
            animatedAmountPair(display: display, amount: amount, received: false)
        }
        // "any amount" + waiting: no trailing element.
    }

    private func amountDisplay(_ amount: UInt64) -> AmountDisplayText {
        AmountFormatter.displayMintUnitAmount(
            amount: amount,
            unit: request.unit,
            preferredPrimary: settings.homeBalancePrimary,
            showFiat: settings.showFiatBalance,
            btcPrice: priceService.btcPriceUSD,
            currencyCode: settings.bitcoinPriceCurrency,
            useBitcoinSymbol: settings.useBitcoinSymbol
        )
    }

    private func animatedAmountPair(
        display: AmountDisplayText,
        amount: UInt64,
        received: Bool
    ) -> some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .trailing, spacing: 2) {
                if received {
                    Text("+\(display.primary)")
                        .cashuAmount(.amountRow, value: Double(amount))
                        .foregroundStyle(.green)
                } else {
                    // No value passed: a waiting amount is static, so it takes the
                    // role's tabular figures without the digit transition.
                    Text(display.primary)
                        .cashuText(.amountRow)
                        .foregroundStyle(.secondary)
                }

                if let secondary = display.secondary {
                    Text(secondary)
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

    private var swapAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .snappy
    }
}
