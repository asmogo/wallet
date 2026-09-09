import Foundation
import SwiftUI

/// Service for fetching Bitcoin price from Coinbase API
@MainActor
class PriceService: ObservableObject {
    static let shared: PriceService = {
        #if DEBUG
        if IntegrationTestConfig.shouldUseDeterministicUIRuntime {
            return PriceService(
                priceFetcher: { $0 == "EUR" ? 80_000 : 100_000 },
                enableAutoRefresh: false
            )
        }
        #endif
        return PriceService()
    }()
    
    // MARK: - Published Properties
    
    /// Current BTC price in selected fiat currency
    @Published var btcPriceUSD: Double = 0.0

    /// Selected fiat currency code (e.g. USD, EUR)
    @Published var currencyCode: String {
        didSet {
            guard currencyCode != oldValue else { return }
            settingsStore.priceCurrencyCode = currencyCode
            invalidatePendingRequests()
            loadCachedPrice()
            if enableAutoRefresh && isEnabled {
                startAutoRefresh()
            }
        }
    }
    
    /// Whether price fetching is enabled
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            settingsStore.priceEnabled = isEnabled
            invalidatePendingRequests()
            if enableAutoRefresh && isEnabled {
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
    
    private let settingsStore: SettingsStore
    private let priceFetcher: (String) async throws -> Double
    private let now: () -> Date
    private let enableAutoRefresh: Bool
    private var refreshTimer: Timer?
    private var initialFetchTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 60 // Refresh every 60 seconds
    private var requestGeneration = 0

    // MARK: - Initialization
    
    init(
        settingsStore: SettingsStore = .shared,
        priceFetcher: @escaping (String) async throws -> Double = fetchCoinbasePrice,
        now: @escaping () -> Date = Date.init,
        enableAutoRefresh: Bool = true
    ) {
        self.settingsStore = settingsStore
        self.priceFetcher = priceFetcher
        self.now = now
        self.enableAutoRefresh = enableAutoRefresh
        self.isEnabled = settingsStore.priceEnabled
        self.currencyCode = settingsStore.priceCurrencyCode
        loadCachedPrice()
        
        // The first network refresh is started by SettingsManager after the
        // initial wallet UI has had a chance to render cached values.
    }
    
    // MARK: - Public Methods
    
    /// Fetch current BTC price from Coinbase
    func fetchPrice() async {
        guard isEnabled else { return }

        requestGeneration += 1
        let request = PriceRequest(
            generation: requestGeneration,
            currencyCode: currencyCode
        )
        isFetching = true
        errorMessage = nil

        do {
            let price = try await priceFetcher(request.currencyCode)
            guard isCurrent(request) else { return }

            btcPriceUSD = price
            let updatedAt = now()
            lastUpdated = updatedAt
            isFetching = false

            // Cache the price
            settingsStore.setCachedPrice(price, currency: request.currencyCode)
            settingsStore.setCachedPriceDate(updatedAt, currency: request.currencyCode)
        } catch {
            guard isCurrent(request) else { return }
            isFetching = false
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                return
            }
            errorMessage = error.localizedDescription
            print("Price fetch error: \(error)")
        }
    }

    private func invalidatePendingRequests() {
        requestGeneration += 1
        isFetching = false
        errorMessage = nil
    }

    private func isCurrent(_ request: PriceRequest) -> Bool {
        request.generation == requestGeneration &&
            isEnabled &&
            currencyCode == request.currencyCode
    }

    private func loadCachedPrice() {
        btcPriceUSD = settingsStore.cachedPrice(currency: currencyCode) ?? 0
        lastUpdated = settingsStore.cachedPriceDate(currency: currencyCode)
    }
    
    /// Convert satoshis to selected fiat currency
    func satsToFiat(_ sats: UInt64) -> Double {
        guard btcPriceUSD > 0 else { return 0 }
        let btc = Double(sats) / 100_000_000.0
        return btc * btcPriceUSD
    }

    /// Convert a fiat amount (major units, e.g. dollars) to satoshis at the
    /// current price, rounded to the nearest sat. Returns 0 when no price is
    /// loaded, so fiat entry never fabricates an amount.
    func fiatToSats(_ fiat: Double) -> UInt64 {
        guard btcPriceUSD > 0, fiat > 0 else { return 0 }
        let sats = (fiat / btcPriceUSD * 100_000_000.0).rounded()
        guard sats.isFinite, sats >= 0, sats < Double(UInt64.max) else { return 0 }
        return UInt64(sats)
    }
    
    /// Format satoshis as selected fiat currency string. Nil when no price is
    /// loaded or the amount converts to under one cent (sub-cent fiat is never
    /// displayed).
    func formatSatsAsFiat(_ sats: UInt64) -> String? {
        AmountFormatter.fiat(sats: sats, btcPrice: btcPriceUSD, currencyCode: currencyCode)
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

private struct PriceRequest {
    let generation: Int
    let currencyCode: String
}

private func fetchCoinbasePrice(currency: String) async throws -> Double {
    guard let url = URL(string: "https://api.coinbase.com/v2/prices/BTC-\(currency)/spot") else {
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

    return price
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
