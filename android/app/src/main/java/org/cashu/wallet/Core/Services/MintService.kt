package org.cashu.wallet.Core.Services

import org.cashu.wallet.Core.WalletManager

/**
 * Compatibility anchor for Swift `MintService.swift`.
 *
 * Android keeps mint orchestration in `WalletManager` and CDK-specific calls in
 * `CdkWalletGateway` so wallet state updates stay transactional.
 */
typealias MintService = WalletManager
