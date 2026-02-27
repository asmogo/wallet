import Foundation

// MARK: - Currency Protocol

/// Protocol defining the interface for different currencies.
/// Implementations include SAT (satoshis), USD, EUR, and potentially other fiat currencies.
///
/// This abstraction allows the wallet to:
/// - Display amounts in different currency denominations
/// - Support mints with different unit types
/// - Convert between currencies when needed
protocol Currency {
    /// ISO-style currency code (e.g., "SAT", "USD", "EUR")
    var code: String { get }
    
    /// Currency symbol for display (e.g., "₿", "$", "€")
    var symbol: String { get }
    
    /// Number of decimal places for this currency
    /// SAT = 0, USD/EUR = 2
    var decimals: Int { get }
    
    /// Human-readable name (e.g., "Satoshis", "US Dollar", "Euro")
    var displayName: String { get }
    
    /// Whether symbol appears before or after the amount
    var symbolPosition: CurrencySymbolPosition { get }
}

/// Position of currency symbol relative to amount
enum CurrencySymbolPosition {
    case before  // $100
    case after   // 100 SAT
}

// MARK: - Built-in Currencies

/// Satoshis - the base unit for Bitcoin/Lightning
struct SatoshiCurrency: Currency {
    let code = "SAT"
    let symbol = "₿"
    let decimals = 0
    let displayName = "Satoshis"
    let symbolPosition = CurrencySymbolPosition.before
}

/// US Dollar
struct USDCurrency: Currency {
    let code = "USD"
    let symbol = "$"
    let decimals = 2
    let displayName = "US Dollar"
    let symbolPosition = CurrencySymbolPosition.before
}

/// Euro
struct EURCurrency: Currency {
    let code = "EUR"
    let symbol = "€"
    let decimals = 2
    let displayName = "Euro"
    let symbolPosition = CurrencySymbolPosition.before
}

// MARK: - Currency Amount

/// A value with an associated currency
struct CurrencyAmount: Equatable {
    /// The raw value in the smallest unit (sats for BTC, cents for fiat)
    let value: UInt64
    
    /// The currency this amount is denominated in
    let currency: any Currency
    
    /// Create amount from smallest unit value
    init(value: UInt64, currency: any Currency) {
        self.value = value
        self.currency = currency
    }
    
    /// Create satoshi amount (convenience)
    static func sats(_ value: UInt64) -> CurrencyAmount {
        CurrencyAmount(value: value, currency: SatoshiCurrency())
    }
    
    /// Create USD amount from cents
    static func usdCents(_ cents: UInt64) -> CurrencyAmount {
        CurrencyAmount(value: cents, currency: USDCurrency())
    }
    
    /// Create EUR amount from cents
    static func eurCents(_ cents: UInt64) -> CurrencyAmount {
        CurrencyAmount(value: cents, currency: EURCurrency())
    }
    
    /// The display value (e.g., 1000 cents = 10.00)
    var displayValue: Double {
        if currency.decimals == 0 {
            return Double(value)
        }
        return Double(value) / pow(10.0, Double(currency.decimals))
    }
    
    /// Formatted string for display
    func formatted(showSymbol: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = currency.decimals
        formatter.maximumFractionDigits = currency.decimals
        formatter.groupingSeparator = ","
        
        let formattedValue = formatter.string(from: NSNumber(value: displayValue)) ?? "\(displayValue)"
        
        guard showSymbol else { return formattedValue }
        
        switch currency.symbolPosition {
        case .before:
            return "\(currency.symbol)\(formattedValue)"
        case .after:
            return "\(formattedValue) \(currency.code)"
        }
    }
    
    // MARK: - Equatable
    
    static func == (lhs: CurrencyAmount, rhs: CurrencyAmount) -> Bool {
        lhs.value == rhs.value && lhs.currency.code == rhs.currency.code
    }
}

// MARK: - Currency Registry

/// Registry for looking up currencies by code
enum CurrencyRegistry {
    /// All supported currencies
    static let supportedCurrencies: [any Currency] = [
        SatoshiCurrency(),
        USDCurrency(),
        EURCurrency()
    ]
    
    /// Get currency by code
    static func currency(forCode code: String) -> (any Currency)? {
        supportedCurrencies.first { $0.code.uppercased() == code.uppercased() }
    }
    
    /// Map from mint unit string to currency
    /// Mints may use "sat", "usd", "eur" as unit identifiers
    static func currency(forMintUnit unit: String) -> (any Currency)? {
        switch unit.lowercased() {
        case "sat", "sats", "satoshi", "satoshis":
            return SatoshiCurrency()
        case "usd", "dollar", "dollars":
            return USDCurrency()
        case "eur", "euro", "euros":
            return EURCurrency()
        default:
            return nil
        }
    }
}
