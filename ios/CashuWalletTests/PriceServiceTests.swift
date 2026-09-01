import XCTest
@testable import CashuWallet

@MainActor
final class PriceServiceTests: XCTestCase {
    func testStaleUSDResponseCannotOverwriteNewerEURPrice() async throws {
        let settings = makeSettings(currency: "USD")
        let fetcher = ControlledPriceFetcher()
        let updatedAt = Date(timeIntervalSince1970: 1_234)
        let service = PriceService(
            settingsStore: settings,
            priceFetcher: fetcher.fetch,
            now: { updatedAt },
            enableAutoRefresh: false
        )

        let usdRequest = Task { await service.fetchPrice() }
        let firstCurrency = await fetcher.nextStarted()
        XCTAssertEqual(firstCurrency, "USD")

        service.currencyCode = "EUR"
        let eurRequest = Task { await service.fetchPrice() }
        let secondCurrency = await fetcher.nextStarted()
        XCTAssertEqual(secondCurrency, "EUR")

        fetcher.complete(currency: "EUR", price: 90_000)
        await eurRequest.value
        fetcher.complete(currency: "USD", price: 100_000)
        await usdRequest.value

        XCTAssertEqual(service.currencyCode, "EUR")
        XCTAssertEqual(service.btcPriceUSD, 90_000, accuracy: 0)
        XCTAssertEqual(service.lastUpdated, updatedAt)
        XCTAssertEqual(
            try XCTUnwrap(settings.cachedPrice(currency: "EUR")),
            90_000,
            accuracy: 0
        )
        XCTAssertNil(settings.cachedPrice(currency: "USD"))
        XCTAssertFalse(service.isFetching)
    }

    func testResponseIsIgnoredAfterPricesAreDisabled() async {
        let settings = makeSettings(currency: "USD")
        let fetcher = ControlledPriceFetcher()
        let service = PriceService(
            settingsStore: settings,
            priceFetcher: fetcher.fetch,
            enableAutoRefresh: false
        )

        let request = Task { await service.fetchPrice() }
        let startedCurrency = await fetcher.nextStarted()
        XCTAssertEqual(startedCurrency, "USD")

        service.isEnabled = false
        fetcher.complete(currency: "USD", price: 100_000)
        await request.value

        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(service.isFetching)
        XCTAssertEqual(service.btcPriceUSD, 0, accuracy: 0)
        XCTAssertNil(settings.cachedPrice(currency: "USD"))
    }

    func testCancellingRefreshClearsFetchingWithoutPublishingAnError() async {
        let settings = makeSettings(currency: "USD")
        let fetcher = ControlledPriceFetcher()
        let service = PriceService(
            settingsStore: settings,
            priceFetcher: fetcher.fetch,
            enableAutoRefresh: false
        )

        let request = Task { await service.fetchPrice() }
        let startedCurrency = await fetcher.nextStarted()
        XCTAssertEqual(startedCurrency, "USD")

        request.cancel()
        await request.value

        XCTAssertTrue(request.isCancelled)
        XCTAssertFalse(service.isFetching)
        XCTAssertNil(service.errorMessage)
    }

    func testLegacyGlobalCacheMigratesOnceToTheSelectedCurrency() throws {
        let storage = InMemoryStorage()
        let cachedAt = Date(timeIntervalSince1970: 1_234)
        try storage.set(100_000.0, forKey: StorageKeys.Legacy.cachedBTCPrice)
        try storage.set(cachedAt, forKey: StorageKeys.Legacy.cachedBTCPriceDate)
        let settings = SettingsStore(storage: storage)

        XCTAssertEqual(
            try XCTUnwrap(settings.cachedPrice(currency: "USD")),
            100_000,
            accuracy: 0
        )
        XCTAssertEqual(settings.cachedPriceDate(currency: "USD"), cachedAt)
        XCTAssertFalse(storage.exists(forKey: StorageKeys.Legacy.cachedBTCPrice))
        XCTAssertFalse(storage.exists(forKey: StorageKeys.Legacy.cachedBTCPriceDate))
        XCTAssertNil(settings.cachedPrice(currency: "EUR"))
        XCTAssertNil(settings.cachedPriceDate(currency: "EUR"))

        try storage.set(95_000.0, forKey: StorageKeys.Legacy.cachedBTCPrice)
        try storage.set(cachedAt.addingTimeInterval(30), forKey: StorageKeys.Legacy.cachedBTCPriceDate)
        XCTAssertEqual(
            try XCTUnwrap(settings.cachedPrice(currency: "USD")),
            100_000,
            accuracy: 0
        )
        XCTAssertEqual(settings.cachedPriceDate(currency: "USD"), cachedAt)
        XCTAssertFalse(storage.exists(forKey: StorageKeys.Legacy.cachedBTCPrice))
        XCTAssertFalse(storage.exists(forKey: StorageKeys.Legacy.cachedBTCPriceDate))

        settings.setCachedPrice(90_000, currency: "EUR")
        settings.setCachedPriceDate(cachedAt.addingTimeInterval(60), currency: "EUR")

        XCTAssertNil(settings.cachedPrice(currency: "GBP"))
        XCTAssertNil(settings.cachedPriceDate(currency: "GBP"))
    }

    private func makeSettings(currency: String) -> SettingsStore {
        let settings = SettingsStore(storage: InMemoryStorage())
        settings.priceEnabled = true
        settings.priceCurrencyCode = currency
        return settings
    }
}

@MainActor
private final class ControlledPriceFetcher {
    private var startedCurrencies: [String] = []
    private var startedWaiters: [CheckedContinuation<String, Never>] = []
    private var responses: [String: CheckedContinuation<Double, Error>] = [:]

    func fetch(currency: String) async throws -> Double {
        announceStarted(currency)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                responses[currency] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(currency: currency)
            }
        }
    }

    func nextStarted() async -> String {
        if !startedCurrencies.isEmpty {
            return startedCurrencies.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func complete(currency: String, price: Double) {
        responses.removeValue(forKey: currency)?.resume(returning: price)
    }

    private func announceStarted(_ currency: String) {
        if !startedWaiters.isEmpty {
            startedWaiters.removeFirst().resume(returning: currency)
        } else {
            startedCurrencies.append(currency)
        }
    }

    private func cancel(currency: String) {
        responses.removeValue(forKey: currency)?.resume(throwing: CancellationError())
    }
}
