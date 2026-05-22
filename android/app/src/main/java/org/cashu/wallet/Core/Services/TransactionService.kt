package org.cashu.wallet.Core.Services

import org.cashu.wallet.Core.WalletManager

/**
 * Compatibility anchor for Swift `TransactionService.swift`.
 *
 * Android aggregates CDK transactions, local pending/claimed token rows, quote
 * fallback rows, metadata enrichment, and transaction update signals in
 * `WalletManager` with helper files under `Core`.
 */
typealias TransactionService = WalletManager
