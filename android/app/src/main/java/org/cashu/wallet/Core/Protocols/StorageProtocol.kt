package org.cashu.wallet.Core.Protocols

interface KeyValueStore {
    fun string(key: String): String?
    fun putString(key: String, value: String?)
    fun remove(key: String)
    fun removePrefix(prefix: String)
}

interface SecureStorage {
    fun loadString(key: String): String?
    fun saveString(key: String, value: String)
    fun delete(key: String)
    fun contains(key: String): Boolean
}

fun SecureStorage.saveMnemonic(mnemonic: String) {
    saveString(StorageKeys.secureWalletMnemonic, mnemonic)
}

fun SecureStorage.loadMnemonic(): String? = loadString(StorageKeys.secureWalletMnemonic)

fun SecureStorage.deleteMnemonic() {
    delete(StorageKeys.secureWalletMnemonic)
}

fun SecureStorage.hasMnemonic(): Boolean = contains(StorageKeys.secureWalletMnemonic)

fun SecureStorage.saveNostrPrivateKey(privateKeyHex: String) {
    saveString(StorageKeys.secureNostrPrivateKey, privateKeyHex)
}

fun SecureStorage.loadNostrPrivateKey(): String? = loadString(StorageKeys.secureNostrPrivateKey)

fun SecureStorage.deleteNostrPrivateKey() {
    delete(StorageKeys.secureNostrPrivateKey)
}

fun SecureStorage.hasNostrPrivateKey(): Boolean = contains(StorageKeys.secureNostrPrivateKey)

object StorageKeys {
    const val walletDataPrefix = "wallet."
    const val settingsDataPrefix = "settings."
    const val npcDataPrefix = "npc."
    const val priceDataPrefix = "price."

    const val walletMints = "wallet.mints"
    const val walletActiveMintUrl = "wallet.activeMintUrl"
    const val walletPendingTokens = "wallet.pendingTokens"
    const val walletPendingReceiveTokens = "wallet.pendingReceiveTokens"
    const val walletClaimedTokens = "wallet.claimedTokens"
    const val walletTransactions = "wallet.transactions"
    const val walletSavedTokens = "wallet.savedTokens"
    const val walletPaymentPreimages = "wallet.paymentPreimages"
    const val walletMeltQuoteFees = "wallet.meltQuoteFees"
    const val walletMintQuoteTimestamps = "wallet.mintQuoteTimestamps"
    const val walletProcessedNPCQuotes = "wallet.processedNPCQuotes"
    const val walletProcessedCashuRequests = "wallet.processedCashuRequests"
    const val cashuRequests = "cashuRequests.v1"
    const val cashuRequestsCurrentId = "cashuRequests.currentId.v1"

    const val settingsUseBitcoinSymbol = "settings.useBitcoinSymbol"
    const val settingsShowFiatBalance = "settings.showFiatBalance"
    const val settingsBitcoinPriceCurrency = "settings.bitcoinPriceCurrency"
    const val settingsCheckPendingOnStartup = "settings.checkPendingOnStartup"
    const val settingsCheckSentTokens = "settings.checkSentTokens"
    const val settingsAutoPasteEcashReceive = "settings.autoPasteEcashReceive"
    const val settingsUseWebsockets = "settings.useWebsockets"
    const val settingsEnablePaymentRequests = "settings.enablePaymentRequests"
    const val settingsReceivePaymentRequestsAutomatically = "settings.receivePaymentRequestsAutomatically"
    const val settingsEnableNWC = "settings.enableNWC"
    const val settingsNwcConnections = "settings.nwcConnections"
    const val settingsShowP2PKButtonInDrawer = "settings.showP2PKButtonInDrawer"
    const val settingsP2PKKeys = "settings.p2pkKeys"
    const val settingsCheckIncomingInvoices = "settings.checkIncomingInvoices"
    const val settingsPeriodicallyCheckIncomingInvoices = "settings.periodicallyCheckIncomingInvoices"
    const val settingsNostrRelays = "settings.nostrRelays"
    const val settingsNostrSignerType = "settings.nostrSignerType"
    const val settingsAmountDisplayPrimary = "settings.amountDisplayPrimary"

    const val npcEnabled = "npc.enabled"
    const val npcAutomaticClaim = "npc.automaticClaim"
    const val npcSelectedMint = "npc.selectedMint"
    const val npcLastCheck = "npc.lastCheck"

    const val priceEnabled = "price.enabled"
    const val priceCurrencyCode = "price.currencyCode"
    const val priceCachedBTC = "price.cachedBTC"
    const val priceCachedBTCDate = "price.cachedBTCDate"

    fun priceCachedBTC(currency: String) = "$priceCachedBTC.${currency.uppercase()}"
    fun priceCachedBTCDate(currency: String) = "$priceCachedBTCDate.${currency.uppercase()}"

    const val secureWalletMnemonic = "wallet_mnemonic"
    const val secureNostrPrivateKey = "nostr_private_key"

    val walletBoundaryKeys = setOf(
        walletMints,
        walletActiveMintUrl,
        walletPendingTokens,
        walletPendingReceiveTokens,
        walletClaimedTokens,
        walletTransactions,
        walletSavedTokens,
        walletPaymentPreimages,
        walletMeltQuoteFees,
        walletMintQuoteTimestamps,
        walletProcessedNPCQuotes,
        walletProcessedCashuRequests,
        cashuRequests,
        cashuRequestsCurrentId,
        settingsNwcConnections,
        settingsP2PKKeys,
        npcEnabled,
        npcAutomaticClaim,
        npcSelectedMint,
        npcLastCheck,
    )
}
