import XCTest
@testable import CashuWallet

@MainActor
final class MintServiceTests: XCTestCase {
    private enum RepositoryFailure: Error {
        case unavailable
    }

    private actor NativeRemovalGate {
        private var started = false
        private var releaseContinuation: CheckedContinuation<Void, Never>?

        func suspendUntilReleased() async {
            started = true
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }

        func hasStarted() -> Bool {
            started
        }

        func release() {
            releaseContinuation?.resume()
            releaseContinuation = nil
        }
    }

    private var service: MintService!

    override func setUp() {
        super.setUp()
        service = MintService(
            walletRepository: { nil },
            walletStore: WalletStore(storage: InMemoryStorage())
        )
    }

    // MARK: - validateMintUrl

    func testValidHttpsUrlAccepted() {
        XCTAssertNil(service.validateMintUrl("https://mint.example.com"))
    }

    func testValidHttpLocalhostAccepted() {
        XCTAssertNil(service.validateMintUrl("http://localhost:3338"))
    }

    func testTrailingSlashNormalizationBeforeValidation() {
        XCTAssertNil(service.validateMintUrl("https://mint.example.com/"))
    }

    func testMissingHostReturnsError() {
        XCTAssertNotNil(service.validateMintUrl("not-a-url-at-all"))
    }

    func testFtpSchemeReturnsError() {
        XCTAssertNotNil(service.validateMintUrl("ftp://mint.example.com"))
    }

    func testCustomSchemeReturnsError() {
        // A syntactically valid but non-http(s) scheme must be rejected.
        XCTAssertNotNil(service.validateMintUrl("cashu://mint.example.com"))
    }

    // MARK: - validateMintUrl — host validation (isValidMintHost)

    func testSingleLabelHostRejected() {
        // No dot, not localhost, not an IP — not a usable mint host.
        XCTAssertNotNil(service.validateMintUrl("https://localmint"))
    }

    func testLocalhostWithoutPortAccepted() {
        XCTAssertNil(service.validateMintUrl("http://localhost"))
    }

    func testIPv4HostAccepted() {
        XCTAssertNil(service.validateMintUrl("http://192.168.1.50"))
    }

    func testIPv4HostWithPortAccepted() {
        XCTAssertNil(service.validateMintUrl("http://127.0.0.1:3338"))
    }

    func testDottedHostWithPortAccepted() {
        XCTAssertNil(service.validateMintUrl("https://mint.example.com:443"))
    }

    // MARK: - isMintTracked

    func testIsMintTrackedFalseWhenEmpty() {
        XCTAssertFalse(service.isMintTracked(url: "https://mint.example.com"))
    }

    func testIsMintTrackedTrueAfterLoad() {
        let storage = InMemoryStorage()
        let ws = WalletStore(storage: storage)
        ws.saveMints([mint("https://mint.example.com", name: "Test")])

        let s = MintService(walletRepository: { nil }, walletStore: ws)
        s.loadCachedMints()
        XCTAssertTrue(s.isMintTracked(url: "https://mint.example.com"))
    }

    func testIsMintTrackedNormalizesTrailingSlash() {
        let storage = InMemoryStorage()
        let ws = WalletStore(storage: storage)
        ws.saveMints([mint("https://mint.example.com", name: "Test")])

        let s = MintService(walletRepository: { nil }, walletStore: ws)
        s.loadCachedMints()
        XCTAssertTrue(s.isMintTracked(url: "https://mint.example.com/"))
    }

    // MARK: - loadCachedMints / activeMint

    func testLoadCachedMintsSetsFirstAsActive() {
        let storage = InMemoryStorage()
        let ws = WalletStore(storage: storage)
        let m = mint("https://mint.example.com", name: "First")
        ws.saveMints([m])
        ws.activeMintURL = m.url

        let s = MintService(walletRepository: { nil }, walletStore: ws)
        s.loadCachedMints()
        XCTAssertEqual(s.activeMint?.url, "https://mint.example.com")
    }

    func testLoadCachedMintsFallsBackToFirstWhenNoActiveSaved() {
        let storage = InMemoryStorage()
        let ws = WalletStore(storage: storage)
        ws.saveMints([
            mint("https://mint1.example.com", name: "Mint 1"),
            mint("https://mint2.example.com", name: "Mint 2"),
        ])

        let s = MintService(walletRepository: { nil }, walletStore: ws)
        s.loadCachedMints()
        XCTAssertEqual(s.activeMint?.url, "https://mint1.example.com")
    }

    // MARK: - Safe mint removal

    func testRegisteredRemovalUnitsNormalizeAndDeduplicate() {
        XCTAssertEqual(
            MintRemovalPolicy.normalizedUnits([" EUR ", "eur", "EuR", " "]),
            ["eur"]
        )
        XCTAssertTrue(MintRemovalPolicy.normalizedUnits([]).isEmpty)
    }

    func testMintIdentityFoldsHostButPreservesCaseSensitivePath() {
        XCTAssertTrue(MintRemovalPolicy.matches(
            "https://MINT.example.com/Mint/",
            "HTTPS://mint.example.com/Mint"
        ))
        XCTAssertFalse(MintRemovalPolicy.matches(
            "https://mint.example.com/Mint",
            "https://mint.example.com/mint"
        ))
        XCTAssertFalse(MintRemovalPolicy.matches(
            "https://mint.example.com/foo%2F",
            "https://mint.example.com/foo/"
        ))

        let upperPath = mint("https://mint.example.com/Mint", name: "Upper")
        let lowerPath = mint("https://mint.example.com/mint", name: "Lower")
        XCTAssertEqual(
            MintRemovalPolicy.removingMint(withURL: upperPath.url, from: [upperPath, lowerPath]),
            [lowerPath]
        )
    }

    func testMultiUnitRemovalRefusesBeforeNativeCallOrMetadataCommit() async {
        var multiUnitMint = mint("https://mint.example.com", name: "Test")
        multiUnitMint.units = ["sat", " EUR ", "eur"]
        var nativeCalls: [String] = []
        var metadataCommitted = false

        do {
            try await MintRemovalPolicy.removeBeforeCommit(
                mint: multiUnitMint,
                registeredUnits: ["sat", " EUR ", "eur"],
                removeWallet: { _, unit in nativeCalls.append(unit) },
                commitMetadata: { metadataCommitted = true }
            )
            XCTFail("Expected multi-unit removal to be refused")
        } catch MintRemovalPolicyError.multipleUnits {
            // Expected: validation runs before the repository is touched.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(nativeCalls.isEmpty)
        XCTAssertFalse(metadataCommitted)
    }

    func testSingleNonSatUnitIsRemovedBeforeMetadataCommit() async throws {
        var euroMint = mint("https://mint.example.com", name: "Test")
        // Advertised metadata can differ from wallets actually registered in CDK.
        euroMint.units = ["sat"]
        var events: [String] = []

        try await MintRemovalPolicy.removeBeforeCommit(
            mint: euroMint,
            registeredUnits: [" EUR ", "eur"],
            removeWallet: { _, unit in events.append("remove:\(unit)") },
            commitMetadata: { events.append("commit") }
        )

        XCTAssertEqual(events, ["remove:eur", "commit"])
    }

    func testMissingNativeWalletCommitsMetadataWithoutInventingSatWallet() async throws {
        let advertisedSatMint = mint("https://mint.example.com", name: "Test")
        var events: [String] = []

        try await MintRemovalPolicy.removeBeforeCommit(
            mint: advertisedSatMint,
            registeredUnits: [],
            removeWallet: { _, unit in events.append("remove:\(unit)") },
            commitMetadata: { events.append("commit") }
        )

        XCTAssertEqual(events, ["commit"])
    }

    func testNativeRemovalFailurePreservesMetadata() async {
        var dollarMint = mint("https://mint.example.com", name: "Test")
        dollarMint.units = ["usd"]
        var metadataCommitted = false

        do {
            try await MintRemovalPolicy.removeBeforeCommit(
                mint: dollarMint,
                registeredUnits: ["usd"],
                removeWallet: { _, _ in throw RepositoryFailure.unavailable },
                commitMetadata: { metadataCommitted = true }
            )
            XCTFail("Expected repository failure")
        } catch RepositoryFailure.unavailable {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(metadataCommitted)
    }

    func testRemovalPreservesCancellationWithoutMetadataCommit() async {
        let satMint = mint("https://mint.example.com", name: "Test")
        var metadataCommitted = false

        do {
            try await MintRemovalPolicy.removeBeforeCommit(
                mint: satMint,
                registeredUnits: ["sat"],
                removeWallet: { _, _ in throw CancellationError() },
                commitMetadata: { metadataCommitted = true }
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(metadataCommitted)
    }

    func testCancellationAfterNativeSuccessStillCommitsMetadata() async {
        let satMint = mint("https://mint.example.com", name: "Test")
        let gate = NativeRemovalGate()
        var metadataCommitted = false

        let request = Task { @MainActor in
            try await MintRemovalPolicy.removeBeforeCommit(
                mint: satMint,
                registeredUnits: ["sat"],
                removeWallet: { _, _ in
                    await gate.suspendUntilReleased()
                },
                commitMetadata: { metadataCommitted = true }
            )
        }

        for _ in 0..<100 {
            if await gate.hasStarted() { break }
            await Task.yield()
        }
        let nativeRemovalStarted = await gate.hasStarted()
        XCTAssertTrue(nativeRemovalStarted)
        request.cancel()
        await gate.release()

        do {
            try await request.value
            XCTFail("Expected cancellation after the commit boundary")
        } catch is CancellationError {
            // Expected after the local metadata follows the native commit.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(metadataCommitted)
    }

    func testStableMintIdentityDoesNotShiftAfterEarlierRemoval() {
        let first = mint("https://first.example.com", name: "First")
        let second = mint("https://second.example.com", name: "Second")
        let third = mint("https://third.example.com", name: "Third")

        let afterFirst = MintRemovalPolicy.removingMint(
            withURL: first.url,
            from: [first, second, third]
        )
        let afterSecond = MintRemovalPolicy.removingMint(
            withURL: second.url,
            from: afterFirst
        )

        XCTAssertEqual(afterSecond.map(\.url), [third.url])
    }

    // MARK: - updateMintBalances

    func testUpdateMintBalanceUpdatesMatchingURL() {
        service.mints = [mint("https://mint.example.com", name: "X")]
        service.updateMintBalance(url: "https://mint.example.com", balance: 100)
        XCTAssertEqual(service.mints[0].balance, 100)
    }

    func testUpdateMintBalanceIgnoresUnknownURL() {
        service.mints = [mint("https://mint.example.com", name: "X")]
        service.updateMintBalance(url: "https://other.example.com", balance: 999)
        XCTAssertEqual(service.mints[0].balance, 0)
    }

    func testUpdateMintBalanceNormalizesTrailingSlash() {
        service.mints = [mint("https://mint.example.com", name: "X")]
        service.updateMintBalance(url: "https://mint.example.com/", balance: 42)
        XCTAssertEqual(service.mints[0].balance, 42)
    }

    func testUpdateMintBalancesUpdatesActiveMintBalance() {
        let m = mint("https://mint.example.com", name: "Active")
        service.mints = [m]
        service.activeMint = m
        service.updateMintBalance(url: "https://mint.example.com", balance: 77)
        XCTAssertEqual(service.activeMint?.balance, 77)
    }

    func testUpdateMintBalancesNoOpWhenUnchanged() {
        var m = mint("https://mint.example.com", name: "X")
        m.balance = 50
        service.mints = [m]
        let before = service.mints[0].balance
        service.updateMintBalance(url: "https://mint.example.com", balance: 50)
        XCTAssertEqual(service.mints[0].balance, before)
    }

    func testUpdateMultipleBalancesInOneCall() {
        service.mints = [
            mint("https://mint1.example.com", name: "A"),
            mint("https://mint2.example.com", name: "B"),
        ]
        service.updateMintBalances([
            "https://mint1.example.com": 10,
            "https://mint2.example.com": 20,
        ])
        XCTAssertEqual(service.mints[0].balance, 10)
        XCTAssertEqual(service.mints[1].balance, 20)
    }

    // MARK: - saveMints / persistence

    func testSaveMintsPersistsToStore() {
        let storage = InMemoryStorage()
        let ws = WalletStore(storage: storage)
        let s = MintService(walletRepository: { nil }, walletStore: ws)
        s.mints = [mint("https://mint.example.com", name: "Saved")]
        s.saveMints()

        let s2 = MintService(walletRepository: { nil }, walletStore: ws)
        s2.loadCachedMints()
        XCTAssertEqual(s2.mints.count, 1)
        XCTAssertEqual(s2.mints[0].name, "Saved")
    }

    // MARK: - Helpers

    private func mint(_ url: String, name: String) -> MintInfo {
        MintInfo(url: url, name: name, description: nil, isActive: true, balance: 0)
    }
}

/// Multi-unit support: mint unit discovery/selection, unit string ↔ CurrencyUnit
/// mapping, and unit-native amount entry.
final class MultiUnitSupportTests: XCTestCase {
    private func mint(units: [String], mintUnits: [String] = ["sat"]) -> MintInfo {
        MintInfo(url: "https://mint.example", name: "Mint", description: nil,
                 isActive: true, balance: 0, iconUrl: nil, units: units, mintUnits: mintUnits)
    }

    // MARK: - MintInfo unit helpers

    func testSingleUnitMintHidesSelector() {
        XCTAssertFalse(mint(units: ["sat"]).supportsMultipleUnits)
    }

    func testMultiUnitMintShowsSelector() {
        XCTAssertTrue(mint(units: ["sat", "eur"]).supportsMultipleUnits)
    }

    func testDefaultUnitPrefersSat() {
        XCTAssertEqual(mint(units: ["eur", "sat", "usd"]).defaultUnit, "sat")
    }

    func testDefaultUnitFallsBackToFirstSorted() {
        XCTAssertEqual(mint(units: ["usd", "eur"]).defaultUnit, "eur")
    }

    func testDefaultUnitEmptyIsSat() {
        XCTAssertEqual(mint(units: []).defaultUnit, "sat")
    }

    func testResolvedUnitKeepsSupported() {
        XCTAssertEqual(mint(units: ["sat", "eur"]).resolvedUnit("eur"), "eur")
    }

    func testResolvedUnitResetsUnsupported() {
        // usd isn't supported → falls back to the mint's default (sat).
        XCTAssertEqual(mint(units: ["sat", "eur"]).resolvedUnit("usd"), "sat")
    }

    // MARK: - MintInfo mintable-unit helpers (Receive/mint selector)

    func testSingleMintUnitHidesReceiveSelector() {
        // A mint that MELTS eur but only MINTS sat must not offer eur for minting.
        XCTAssertFalse(mint(units: ["sat", "eur"], mintUnits: ["sat"]).supportsMultipleMintUnits)
    }

    func testMultiMintUnitShowsReceiveSelector() {
        XCTAssertTrue(mint(units: ["sat", "eur"], mintUnits: ["sat", "eur"]).supportsMultipleMintUnits)
    }

    func testDefaultMintUnitPrefersSat() {
        XCTAssertEqual(mint(units: ["sat", "eur"], mintUnits: ["eur", "sat"]).defaultMintUnit, "sat")
    }

    func testDefaultMintUnitFallsBackToFirstSorted() {
        XCTAssertEqual(mint(units: ["usd", "eur"], mintUnits: ["usd", "eur"]).defaultMintUnit, "eur")
    }

    func testResolvedMintUnitKeepsMintable() {
        XCTAssertEqual(mint(units: ["sat", "eur"], mintUnits: ["sat", "eur"]).resolvedMintUnit("eur"), "eur")
    }

    func testResolvedMintUnitResetsNonMintable() {
        // eur is meltable but not mintable → falls back to the default mint unit.
        XCTAssertEqual(mint(units: ["sat", "eur"], mintUnits: ["sat"]).resolvedMintUnit("eur"), "sat")
    }

    // MARK: - Home balance pager ordering

    func testHomeBalanceSatOnly() {
        XCTAssertEqual(HomeBalance.homeBalanceUnits(["sat": 1000]), ["sat"])
    }

    func testHomeBalanceEmptyIsSat() {
        XCTAssertEqual(HomeBalance.homeBalanceUnits([:]), ["sat"])
    }

    func testHomeBalanceIncludesHeldNonSatSorted() {
        XCTAssertEqual(
            HomeBalance.homeBalanceUnits(["sat": 1000, "usd": 500, "eur": 200]),
            ["sat", "eur", "usd"]
        )
    }

    func testHomeBalanceExcludesZeroNonSat() {
        // A unit the mint lists but the user doesn't hold gets no page.
        XCTAssertEqual(
            HomeBalance.homeBalanceUnits(["sat": 1000, "eur": 0, "usd": 300]),
            ["sat", "usd"]
        )
    }

    func testHomeBalanceAllZeroNonSatIsSat() {
        XCTAssertEqual(HomeBalance.homeBalanceUnits(["sat": 0, "eur": 0]), ["sat"])
    }

    func testResolvedHomeUnitKeepsAvailable() {
        XCTAssertEqual(HomeBalance.resolvedUnit("eur", in: ["sat", "eur"]), "eur")
    }

    func testResolvedHomeUnitFallsBackToSat() {
        // Stored unit dropped to zero balance and left the pager → back to sat.
        XCTAssertEqual(HomeBalance.resolvedUnit("eur", in: ["sat"]), "sat")
    }

    // MARK: - Pager gate (active/default mint)

    func testShowsPagerWhenMultiUnitDefaultAndNonSatHeld() {
        XCTAssertTrue(HomeBalance.showsUnitPager(
            activeMintSupportsMultipleUnits: true,
            balancesByUnit: ["sat": 100, "eur": 5]
        ))
    }

    func testNoPagerWhenDefaultMintIsSingleUnit() {
        // Non-sat balance held elsewhere, but the default mint is single-unit.
        XCTAssertFalse(HomeBalance.showsUnitPager(
            activeMintSupportsMultipleUnits: false,
            balancesByUnit: ["sat": 100, "eur": 5]
        ))
    }

    func testNoPagerWhenNoNonSatBalance() {
        XCTAssertFalse(HomeBalance.showsUnitPager(
            activeMintSupportsMultipleUnits: true,
            balancesByUnit: ["sat": 100]
        ))
    }

    func testNoPagerWhenNonSatBalanceIsZero() {
        XCTAssertFalse(HomeBalance.showsUnitPager(
            activeMintSupportsMultipleUnits: true,
            balancesByUnit: ["sat": 100, "eur": 0]
        ))
    }

    func testResolvedUnitNilUsesDefault() {
        XCTAssertEqual(mint(units: ["eur", "usd"]).resolvedUnit(nil), "eur")
    }

    // MARK: - Unit string ↔ CurrencyUnit round-trip

    func testCurrencyUnitRoundTripsKnownUnits() {
        for unit in ["sat", "msat", "usd", "eur", "auth"] {
            let roundTripped = PaymentRequestDecoder.unitDescription(
                PaymentRequestDecoder.currencyUnit(from: unit)
            )
            XCTAssertEqual(roundTripped, unit)
        }
    }

    func testCurrencyUnitPreservesCustomUnit() {
        let roundTripped = PaymentRequestDecoder.unitDescription(
            PaymentRequestDecoder.currencyUnit(from: "hour")
        )
        XCTAssertEqual(roundTripped, "hour")
    }

    // MARK: - Currency lookup is never nil (arbitrary units supported)

    func testCurrencyForKnownUnits() {
        XCTAssertEqual(CurrencyRegistry.currency(forMintUnit: "sat").decimals, 0)
        XCTAssertEqual(CurrencyRegistry.currency(forMintUnit: "eur").decimals, 2)
        XCTAssertEqual(CurrencyRegistry.currency(forMintUnit: "usd").decimals, 2)
    }

    func testCurrencyForCustomUnitFallsBack() {
        let currency = CurrencyRegistry.currency(forMintUnit: "hour")
        XCTAssertEqual(currency.decimals, 0)
        XCTAssertEqual(currency.code, "HOUR")
    }

    // MARK: - Unit-native amount entry
    //
    // Whole-number-first. These vectors are mirrored verbatim in the Android
    // suite (UnitAmountEntryTest) — the raw string is the contract between the
    // two platforms, so they must agree.

    func testEntryBaseUnitsTwoDecimals() {
        XCTAssertEqual(AmountFormatter.entryBaseUnits(raw: "5.00", decimals: 2), 500)
        XCTAssertEqual(AmountFormatter.entryBaseUnits(raw: "14.54", decimals: 2), 1454)
    }

    func testEntryBaseUnitsInteger() {
        XCTAssertEqual(AmountFormatter.entryBaseUnits(raw: "500", decimals: 0), 500)
    }

    /// The regression this whole change exists for: "21" is $21, not $0.21.
    func testDigitsBuildTheIntegerPartLeftToRight() {
        var raw = ""
        raw = AmountFormatter.entryAppendUnit("2", to: raw, decimals: 2)
        XCTAssertEqual(raw, "2")
        raw = AmountFormatter.entryAppendUnit("1", to: raw, decimals: 2)
        XCTAssertEqual(raw, "21")
        XCTAssertEqual(AmountFormatter.entryBaseUnits(raw: raw, decimals: 2), 2100)
    }

    func testSeparatorArmsTheFraction() {
        var raw = AmountFormatter.entryAppendUnit("2", to: "", decimals: 2)
        raw = AmountFormatter.entryAppendUnit("1", to: raw, decimals: 2)
        raw = AmountFormatter.entryAppendSeparatorUnit(raw, decimals: 2)
        XCTAssertEqual(raw, "21.")
        XCTAssertEqual(AmountFormatter.entryBaseUnits(raw: raw, decimals: 2), 2100)
        raw = AmountFormatter.entryAppendUnit("5", to: raw, decimals: 2)
        XCTAssertEqual(raw, "21.5")
        XCTAssertEqual(AmountFormatter.entryBaseUnits(raw: raw, decimals: 2), 2150)
        raw = AmountFormatter.entryAppendUnit("0", to: raw, decimals: 2)
        XCTAssertEqual(raw, "21.50")
        XCTAssertEqual(AmountFormatter.entryBaseUnits(raw: raw, decimals: 2), 2150)
    }

    func testSeparatorOnAnEmptyPadOpensWithALeadingZero() {
        let raw = AmountFormatter.entryAppendSeparatorUnit("", decimals: 2)
        XCTAssertEqual(raw, "0.")
        XCTAssertEqual(AmountFormatter.entryBaseUnits(raw: raw, decimals: 2), 0)
        XCTAssertEqual(
            AmountFormatter.entryBaseUnits(
                raw: AmountFormatter.entryAppendUnit("5", to: raw, decimals: 2),
                decimals: 2
            ),
            50
        )
    }

    func testSeparatorIsInertWhenItCannotApply() {
        // Already armed.
        XCTAssertEqual(AmountFormatter.entryAppendSeparatorUnit("21.5", decimals: 2), "21.5")
        // No fraction exists for a 0-decimal unit, and no key is rendered for it.
        XCTAssertEqual(AmountFormatter.entryAppendSeparatorUnit("21", decimals: 0), "21")
    }

    func testFractionStopsAtTheUnitsPrecision() {
        XCTAssertEqual(AmountFormatter.entryAppendUnit("7", to: "21.50", decimals: 2), "21.50")
    }

    func testIntegerAppendCollapsesLeadingZero() {
        XCTAssertEqual(AmountFormatter.entryAppendUnit("5", to: "0", decimals: 0), "5")
        XCTAssertEqual(AmountFormatter.entryAppendUnit("5", to: "", decimals: 2), "5")
    }

    func testBackspaceDropsCharactersIncludingTheSeparator() {
        XCTAssertEqual(AmountFormatter.entryBackspaceUnit("21.50"), "21.5")
        XCTAssertEqual(AmountFormatter.entryBackspaceUnit("21.5"), "21.")
        XCTAssertEqual(AmountFormatter.entryBackspaceUnit("21."), "21")
        XCTAssertEqual(AmountFormatter.entryBackspaceUnit("21"), "2")
        XCTAssertEqual(AmountFormatter.entryBackspaceUnit("2"), "")
    }

    func testEntryStringSeedsInMinimalForm() {
        XCTAssertEqual(AmountFormatter.entryString(baseUnits: 0, decimals: 2), "")
        XCTAssertEqual(AmountFormatter.entryString(baseUnits: 600, decimals: 2), "6")
        XCTAssertEqual(AmountFormatter.entryString(baseUnits: 610, decimals: 2), "6.10")
        XCTAssertEqual(AmountFormatter.entryString(baseUnits: 617, decimals: 2), "6.17")
        XCTAssertEqual(AmountFormatter.entryString(baseUnits: 9, decimals: 2), "0.09")
        XCTAssertEqual(AmountFormatter.entryString(baseUnits: 1234, decimals: 0), "1234")
    }

    func testEntryStringRoundTrips() {
        for value: UInt64 in [1, 9, 600, 610, 617, 2150, 99_999_999_999] {
            XCTAssertEqual(
                AmountFormatter.entryBaseUnits(
                    raw: AmountFormatter.entryString(baseUnits: value, decimals: 2),
                    decimals: 2
                ),
                value
            )
        }
        // A seeded whole and its padded twin are the same amount.
        XCTAssertEqual(AmountFormatter.entryBaseUnits(raw: "6", decimals: 2), 600)
        XCTAssertEqual(AmountFormatter.entryBaseUnits(raw: "6.00", decimals: 2), 600)
        XCTAssertEqual(AmountFormatter.entryString(baseUnits: 500, decimals: 0), "500")
    }

    func testIntegerPartStopsAtTwelveDigits() {
        let maxed = "999999999999"
        XCTAssertEqual(AmountFormatter.entryAppendUnit("9", to: maxed, decimals: 2), maxed)
        XCTAssertEqual(AmountFormatter.entryAppendUnit("9", to: maxed, decimals: 0), maxed)
        // Still extendable into the fraction.
        XCTAssertEqual(
            AmountFormatter.entryAppendUnit("9", to: "999999999999.", decimals: 2),
            "999999999999.9"
        )
    }

    /// An over-long raw can only arrive pre-seeded; it must clamp rather than
    /// parse-fail into a silent zero. Sat entry had no cap at all before this.
    func testOversizedRawClampsInsteadOfCollapsingToZero() {
        XCTAssertEqual(
            AmountFormatter.entryBaseUnits(raw: "99999999999999999999", decimals: 2),
            99_999_999_999_999
        )
        XCTAssertEqual(
            AmountFormatter.entryBaseUnits(raw: "99999999999999999999", decimals: 0),
            999_999_999_999
        )
    }

    func testNonDigitKeysAreIgnored() {
        XCTAssertEqual(AmountFormatter.entryAppendUnit("x", to: "5.00", decimals: 2), "5.00")
        XCTAssertEqual(AmountFormatter.entryAppendUnit("x", to: "500", decimals: 0), "500")
        // The separator has its own entry point; it is not a digit.
        XCTAssertEqual(AmountFormatter.entryAppendUnit(".", to: "500", decimals: 2), "500")
    }

    func testUSDDisplayUsesLeadingBareDollarSymbol() {
        XCTAssertEqual(AmountFormatter.fiat(60, currencyCode: "USD"), "$60.00")
        XCTAssertEqual(
            AmountFormatter.fiat(sats: 122_300, btcPrice: 10_000, currencyCode: "USD"),
            "$12.23"
        )
    }

    func testFiatPrimaryDisplayOrdersFiatBeforeSats() {
        let display = AmountFormatter.displayText(
            amountSats: 300_000,
            preferredPrimary: .fiat,
            showFiat: true,
            btcPrice: 20_000,
            currencyCode: "USD",
            useBitcoinSymbol: false
        )

        XCTAssertEqual(display.primary, "$60.00")
        XCTAssertEqual(display.secondary, "300,000 sat")
        XCTAssertEqual(display.effectivePrimary, .fiat)
    }

    func testSatsPrimaryDisplayOrdersSatsBeforeFiat() {
        let display = AmountFormatter.displayText(
            amountSats: 300_000,
            preferredPrimary: .sats,
            showFiat: true,
            btcPrice: 20_000,
            currencyCode: "USD",
            useBitcoinSymbol: false
        )

        XCTAssertEqual(display.primary, "300,000 sat")
        XCTAssertEqual(display.secondary, "$60.00")
        XCTAssertEqual(display.effectivePrimary, .sats)
    }

    func testSatsPrimaryDisplayHidesFiatWhenDisplayIsDisabled() {
        let display = AmountFormatter.displayText(
            amountSats: 300_000,
            preferredPrimary: .sats,
            showFiat: false,
            btcPrice: 20_000,
            currencyCode: "USD",
            useBitcoinSymbol: false
        )

        XCTAssertEqual(display.primary, "300,000 sat")
        XCTAssertNil(display.secondary)
        XCTAssertEqual(display.effectivePrimary, .sats)
    }

    func testHistoryAmountConvertsEverySatoshiUnitAlias() {
        for unit in ["sat", "SAT", " sats ", "satoshi", "satoshis"] {
            let display = AmountFormatter.displayMintUnitAmount(
                amount: 300_000,
                unit: unit,
                preferredPrimary: .fiat,
                showFiat: true,
                btcPrice: 20_000,
                currencyCode: "USD",
                useBitcoinSymbol: false
            )

            XCTAssertEqual(display.primary, "$60.00", "Failed for unit: \(unit)")
            XCTAssertEqual(display.secondary, "300,000 sat", "Failed for unit: \(unit)")
            XCTAssertEqual(display.effectivePrimary, .fiat, "Failed for unit: \(unit)")
        }
    }

    func testHistoryAmountKeepsNonBitcoinMintUnitNative() {
        let display = AmountFormatter.displayMintUnitAmount(
            amount: 500,
            unit: "usd",
            preferredPrimary: .fiat,
            showFiat: true,
            btcPrice: 20_000,
            currencyCode: "EUR",
            useBitcoinSymbol: false
        )

        XCTAssertEqual(display.primary, "$5.00")
        XCTAssertNil(display.secondary)
    }

    func testHomeBalancePrimaryDefaultsToSatsAndPersistsIndependently() {
        let store = SettingsStore(storage: InMemoryStorage())

        XCTAssertEqual(store.homeBalancePrimary, "sats")
        XCTAssertEqual(store.amountDisplayPrimary, "fiat")

        store.homeBalancePrimary = "fiat"

        XCTAssertEqual(store.homeBalancePrimary, "fiat")
        XCTAssertEqual(store.amountDisplayPrimary, "fiat")
    }
}
