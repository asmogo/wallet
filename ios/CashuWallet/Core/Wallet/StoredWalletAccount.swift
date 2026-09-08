import Cdk
import Foundation

/// Local account identity, independent of a mint's advertised payment options.
struct StoredWalletAccount: Hashable {
    let mintURL: String
    let unit: CurrencyUnit

    init(mintURL: String, unit: CurrencyUnit) {
        // CDK preserves default ports in its storage keys. Keep that exact URL
        // for reads, even when the app tracks an equivalent URL without a port.
        self.mintURL = mintURL
        self.unit = unit
    }

    var unitName: String { PaymentRequestDecoder.unitDescription(unit) }

    func matches(mintURL: String) -> Bool {
        MintURLIdentity.normalized(self.mintURL) == MintURLIdentity.normalized(mintURL)
    }

    static func discover(database: WalletSqliteDatabase, repository: WalletRepository) async throws -> [Self] {
        // A failed scan must not become a successful, incomplete projection.
        var accounts = Set(await repository.getWallets().map { Self(mintURL: $0.mintUrl().url, unit: $0.unit()) })
        for proof in try await database.getProofs(mintUrl: nil, unit: nil, state: nil, spendingConditions: nil) {
            accounts.insert(Self(mintURL: proof.mintUrl.url, unit: proof.unit))
        }
        for transaction in try await database.listTransactions(mintUrl: nil, direction: nil, unit: nil) {
            accounts.insert(Self(mintURL: transaction.mintUrl.url, unit: transaction.unit))
        }
        for quote in try await database.getMintQuotes() {
            accounts.insert(Self(mintURL: quote.mintUrl.url, unit: quote.unit))
        }
        for quote in try await database.getMeltQuotes() {
            if let url = quote.mintUrl { accounts.insert(Self(mintURL: url.url, unit: quote.unit)) }
        }
        return accounts.sorted { ($0.mintURL, $0.unitName) < ($1.mintURL, $1.unitName) }
    }
}

struct StoredBalanceProjection {
    let totals: [String: UInt64]
    let balances: [StoredWalletAccount: UInt64]
    let failedAccounts: Set<StoredWalletAccount>

    /// A tracked mint may have multiple CDK storage URLs for the same endpoint.
    func balance(mintURL: String, unit: CurrencyUnit) -> UInt64? {
        guard !failedAccounts.contains(where: { $0.unit == unit && $0.matches(mintURL: mintURL) }) else {
            return nil
        }
        return balances.filter { $0.key.unit == unit && $0.key.matches(mintURL: mintURL) }
            .values.reduce(0, +)
    }

    /// Retain the previous complete total if any account in a currency fails.
    static func load(
        accounts: [StoredWalletAccount],
        previousTotals: [String: UInt64],
        read: (StoredWalletAccount) async throws -> UInt64
    ) async throws -> Self {
        var balances: [StoredWalletAccount: UInt64] = [:]
        var totals: [String: UInt64] = [:]
        var failedAccounts: Set<StoredWalletAccount> = []
        for (unit, group) in Dictionary(grouping: Set(accounts), by: \.unitName) {
            var complete = true
            var total: UInt64 = 0
            for account in group {
                do {
                    let amount = try await read(account)
                    balances[account] = amount
                    total += amount
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    complete = false
                    failedAccounts.insert(account)
                }
            }
            totals[unit] = complete ? total : previousTotals[unit]
        }
        return Self(totals: totals, balances: balances, failedAccounts: failedAccounts)
    }
}
