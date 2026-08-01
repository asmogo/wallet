package com.cashu.me.ui.testing

/**
 * Stable identifiers for app-level UI journeys.
 *
 * Tests should prefer visible text and accessibility semantics. These tags are
 * reserved for screen roots and controls whose meaning is otherwise ambiguous.
 */
object UiTestTags {
    const val AppRoot = "cashu.app"
    const val ScannerRoot = "cashu.scanner"
    const val OnboardingRoot = "cashu.onboarding"
    const val CreateWallet = "cashu.onboarding.create"
    const val RetryWalletStartup = "cashu.onboarding.startup.retry"
    const val RevealSeed = "cashu.onboarding.seed.reveal"
    const val SeedPhrase = "cashu.onboarding.seed.phrase"
    const val HiddenSeedPhrase = "cashu.onboarding.seed.hidden"
    const val AcknowledgeSeed = "cashu.onboarding.seed.acknowledge"
    const val SeedSaved = "cashu.onboarding.seed.saved"
    const val AddCustomMint = "cashu.onboarding.mint.custom"
    const val CustomMintUrl = "cashu.onboarding.mint.url"
    const val ContinueWithMint = "cashu.onboarding.mint.continue"
    const val SkipMint = "cashu.onboarding.mint.skip"

    const val WalletScreen = "cashu.screen.wallet"
    const val WalletScan = "cashu.wallet.scan"
    const val WalletReceive = "cashu.wallet.receive"
    const val WalletSend = "cashu.wallet.send"
    const val HistoryScreen = "cashu.screen.history"
    const val MintsScreen = "cashu.screen.mints"
    const val MintDetailScreen = "cashu.screen.mint-detail"
    const val MintDetailContent = "cashu.mint-detail.content"
    const val SettingsScreen = "cashu.screen.settings"
    const val SettingsList = "cashu.settings.list"
    const val BitcoinSymbolToggle = "cashu.settings.bitcoin-symbol"
    const val ReceiveSheet = "cashu.sheet.receive"
    const val ReceiveEcashDetail = "cashu.receive.ecash-detail"
    const val ReceiveLightningScreen = "cashu.receive.lightning"
    const val SendSheet = "cashu.sheet.send"
    const val SendDestination = "cashu.send.destination"
    const val SendPaymentSubmit = "cashu.send.payment.submit"
    const val SendEcashScreen = "cashu.sheet.send-ecash"
    const val SendEcashSubmit = "cashu.send.ecash.submit"
    const val LockEcashToggle = "cashu.send.ecash.lock-toggle"
    const val P2pkRecipientConfirmation = "cashu.send.ecash.p2pk-recipient"
    const val AddMintSheet = "cashu.sheet.add-mint"
    const val AddMintUrl = "cashu.sheet.add-mint.url"
    const val AddMintSubmit = "cashu.sheet.add-mint.submit"
    const val HistorySearch = "cashu.history.search"

    fun mintRow(url: String): String = "cashu.mint.${url.hashCode().toUInt().toString(16)}"

    fun transactionRow(id: String): String = "cashu.history.${id.hashCode().toUInt().toString(16)}"
}
