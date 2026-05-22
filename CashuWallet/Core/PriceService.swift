import Foundation
import SwiftUI

/// Service for fetching Bitcoin price from Coinbase API
@MainActor
class PriceService: ObservableObject {
    static let shared = PriceService()
    
    // MARK: - Published Properties
    
    /// Current BTC price in selected fiat currency
    @Published var btcPriceUSD: Double = 0.0

    /// Selected fiat currency code (e.g. USD, EUR)
    @Published var currencyCode: String {
        didSet {
            guard currencyCode != oldValue else { return }
            settingsStore.priceCurrencyCode = currencyCode
            if isEnabled {
                startAutoRefresh()
            }
        }
    }
    
    /// Whether price fetching is enabled
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            settingsStore.priceEnabled = isEnabled
            if isEnabled {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
    }
    
    /// Last update timestamp
    @Published var lastUpdated: Date?
    
    /// Whether currently fetching
    @Published var isFetching: Bool = false
    
    /// Error message if fetch failed
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var coinbaseSpotURL: String {
        "https://api.coinbase.com/v2/prices/BTC-\(currencyCode)/spot"
    }
    private let settingsStore = SettingsStore.shared
    private var refreshTimer: Timer?
    private var initialFetchTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 60 // Refresh every 60 seconds
    private lazy var fiatFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()
    
    // MARK: - Initialization
    
    init() {
        self.isEnabled = settingsStore.priceEnabled
        self.currencyCode = settingsStore.priceCurrencyCode

        if let cachedPrice = settingsStore.cachedPrice(currency: currencyCode) {
            self.btcPriceUSD = cachedPrice
        }

        if let cachedDate = settingsStore.cachedPriceDate(currency: currencyCode) {
            self.lastUpdated = cachedDate
        }
        
        // The first network refresh is started by SettingsManager after the
        // initial wallet UI has had a chance to render cached values.
    }
    
    // MARK: - Public Methods
    
    /// Fetch current BTC price from Coinbase
    func fetchPrice() async {
        guard isEnabled else { return }
        
        isFetching = true
        errorMessage = nil
        
        defer { isFetching = false }
        
        do {
            guard let url = URL(string: coinbaseSpotURL) else {
                throw PriceError.invalidURL
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw PriceError.invalidResponse
            }
            
            let priceResponse = try JSONDecoder().decode(CoinbasePriceResponse.self, from: data)
            
            guard let price = Double(priceResponse.data.amount) else {
                throw PriceError.invalidData
            }
            
            btcPriceUSD = price
            let now = Date()
            lastUpdated = now
            
            // Cache the price
            settingsStore.setCachedPrice(price, currency: currencyCode)
            settingsStore.setCachedPriceDate(now, currency: currencyCode)
            
        } catch {
            errorMessage = error.localizedDescription
            print("Price fetch error: \(error)")
        }
    }
    
    /// Convert satoshis to selected fiat currency
    func satsToFiat(_ sats: UInt64) -> Double {
        guard btcPriceUSD > 0 else { return 0 }
        let btc = Double(sats) / 100_000_000.0
        return btc * btcPriceUSD
    }
    
    /// Format satoshis as selected fiat currency string
    func formatSatsAsFiat(_ sats: UInt64) -> String {
        let fiat = satsToFiat(sats)
        fiatFormatter.currencyCode = currencyCode
        return fiatFormatter.string(from: NSNumber(value: fiat)) ?? "\(currencyCode) 0.00"
    }

    /// Backward-compatible wrapper used by existing views
    func satsToUSD(_ sats: UInt64) -> Double {
        satsToFiat(sats)
    }

    /// Backward-compatible wrapper used by existing views
    func formatSatsAsUSD(_ sats: UInt64) -> String {
        formatSatsAsFiat(sats)
    }
    
    /// Start auto-refresh timer
    func startAutoRefresh() {
        stopAutoRefresh()
        
        initialFetchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.fetchPrice()
        }
        
        // Setup timer for periodic refresh
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchPrice()
            }
        }
    }
    
    /// Stop auto-refresh timer
    func stopAutoRefresh() {
        initialFetchTask?.cancel()
        initialFetchTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Deinit
    
    deinit {
        initialFetchTask?.cancel()
        refreshTimer?.invalidate()
    }
}

// MARK: - Error Types

enum PriceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid response from server"
        case .invalidData: return "Could not parse price data"
        }
    }
}

// MARK: - Coinbase API Response

struct CoinbasePriceResponse: Codable {
    let data: CoinbasePriceData
}

struct CoinbasePriceData: Codable {
    let base: String
    let currency: String
    let amount: String
}
