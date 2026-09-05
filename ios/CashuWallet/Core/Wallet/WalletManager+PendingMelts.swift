import Foundation
import Cdk

/// Asynchronous melt settlement (NUT-05).
///
/// When a mint accepts a melt with `Prefer: respond-async` — on-chain payments
/// especially can take minutes to settle — `confirmPreferAsync()` hands back a
/// `PendingMelt` instead of a final result. Lightning melts await its `wait()`
/// *inside* the melt lease for a bounded window (see
/// `LightningService.MeltSettlementWait`), so they normally return settled. A
/// wait that outlives the cap keeps running as a detached settlement watcher —
/// the Swift bindings cannot cancel the native future, and CDK's docs direct
/// foreign callers to run `wait()` in a background task — whose only lane
/// re-entry is the coordinated balance/history refresh once it lands.
///
/// CDK 0.18 persists the melt as a Pending transaction backed by a durable
/// saga, so no app-side quote tracking is needed: `recoverIncompleteSagas()`
/// re-checks in-flight melts with their mints and flips the transactions to
/// completed/failed when settlement resolves — the safety net behind both the
/// watcher and an app relaunch.
extension WalletManager {
    /// Reconcile melts still recorded as pending — e.g. after a relaunch killed
    /// the in-process waiter. Cheap no-op when no saga is incomplete.
    func syncPendingMeltQuotes() async {
        guard walletRepository != nil else { return }

        do {
            try await operationCoordinator.performIfIdle(kind: .pendingMeltPoll) {
                var settledAny = false
                for wallet in await self.trackedWalletsAssumingWalletOperationLease() {
                    guard !Task.isCancelled else { break }
                    do {
                        let report = try await wallet.recoverIncompleteSagas()
                        settledAny = settledAny || report.recovered > 0 || report.compensated > 0
                    } catch is CancellationError {
                        break
                    } catch {
                        AppLogger.wallet.error(
                            "pending operation reconciliation failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                        )
                    }
                    if await self.operationCoordinator.hasWaitingUserOperation() { break }
                }

                if settledAny {
                    await self.refreshBalanceAssumingWalletOperationLease()
                    await self.loadTransactionsAssumingWalletOperationLease()
                }
            }
        } catch {
            // Passive settlement polling will retry on the next foreground tick.
        }
    }
}
