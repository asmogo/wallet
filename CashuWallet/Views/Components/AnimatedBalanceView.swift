import SwiftUI

// MARK: - Animated Balance View
/// Displays balance with animated number transitions, matching cashu.me's AnimatedNumber component

struct AnimatedBalanceView: View {
    let value: UInt64
    var textStyle: Font = .largeTitle.bold()
    var hideBalance: Bool = false

    @ObservedObject var settings = SettingsManager.shared
    @State private var displayValue: UInt64 = 0
    @State private var animationProgress: Double = 0

    var body: some View {
        Group {
            if hideBalance {
                Text("••••••")
                    .font(textStyle)
                    .accessibilityLabel("Balance hidden")
            } else {
                Text(formattedValue)
                    .font(textStyle)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: displayValue)
                    .accessibilityLabel("Balance: \(formattedValue)")
                    .accessibilityValue(formattedValue)
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                displayValue = newValue
            }
        }
        .onAppear {
            displayValue = value
        }
    }
    
    private var formattedValue: String {
        settings.formatAmountBalance(displayValue)
    }
}

// MARK: - Animated Amount Display
/// Full amount display with unit, used for main balance view

struct AnimatedAmountDisplay: View {
    let value: UInt64
    var showUnit: Bool = true
    var hideBalance: Bool = false

    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 4) {
            AnimatedBalanceView(
                value: value,
                hideBalance: hideBalance
            )
            
            if showUnit && !hideBalance {
                Text(settings.unitSuffix)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Balance Card View
/// Complete balance card matching cashu.me's BalanceView component

struct BalanceCardView: View {
    let balance: UInt64
    let mintName: String?
    let pendingBalance: UInt64
    var onUnitToggle: (() -> Void)?
    var onHideToggle: (() -> Void)?
    
    @ObservedObject var settings = SettingsManager.shared
    @State private var isHidden: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Unit toggle badge at top
            // UnitToggleBadge(onTap: onUnitToggle) // Removed because UnitToggleBadge is undefined
            Button(action: { onUnitToggle?() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text(settings.unitLabel)
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
            .glassButton()
            .accessibilityLabel("Unit: \(settings.unitLabel)")
            .accessibilityHint("Toggles the display unit")
            .padding(.top, 20)
            
            // Main balance display
            VStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHidden.toggle()
                        onHideToggle?()
                    }
                } label: {
                    AnimatedBalanceView(
                        value: balance,
                        hideBalance: isHidden
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isHidden ? "Show balance" : "Hide balance")
                .accessibilityHint("Toggles balance visibility")
                
                // Unit suffix
                if !settings.useBitcoinSymbol {
                    Text("sat")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                
                // Fiat conversion placeholder
                if !isHidden {
                    Text("$0.00") // Placeholder - would need price feed
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 24)
            
            // Mint name
            if let mintName = mintName {
                HStack {
                    Text("Mint:")
                        .foregroundStyle(.secondary)
                    Text(mintName)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            
            // Pending balance indicator
            if pendingBalance > 0 {
                PendingBalanceBadge(amount: pendingBalance)
            }
        }
    }
}

// MARK: - Pending Balance Badge
/// Shows pending balance with clock icon

struct PendingBalanceBadge: View {
    let amount: UInt64
    var onTap: (() -> Void)?
    
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        Button(action: { onTap?() }) {
            Label("Pending: \(settings.formatAmountShort(amount)) \(settings.unitSuffix)", systemImage: "clock")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pending balance: \(settings.formatAmountShort(amount)) \(settings.unitSuffix)")
    }
}

// MARK: - Transaction Amount View
/// Displays transaction amounts with proper +/- formatting

struct TransactionAmountView: View {
    let amount: Int64
    let isIncoming: Bool

    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        Text(formattedAmount)
            .font(.callout.weight(.medium))
            .foregroundStyle(amountColor)
    }
    
    private var formattedAmount: String {
        let sign = isIncoming ? "+" : "-"
        return "\(sign)\(settings.formatAmountShort(UInt64(abs(amount))))"
    }
    
    private var amountColor: Color {
        isIncoming ? .green : .primary
    }
}

// MARK: - Preview

#Preview("Balance Card") {
    BalanceCardView(
        balance: 21000,
        mintName: "mint.minibits.cash",
        pendingBalance: 1000
    )
}

#Preview("Animated Balance") {
    AnimatedBalanceView(value: 123456)
}
