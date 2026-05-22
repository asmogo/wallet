package org.cashu.wallet.ui.navigation

/**
 * Compose Navigation routes.
 *
 * Top-level tab routes are bare strings used as `NavController` `startDestination`s and tab keys.
 * Pushed detail destinations take typed arguments embedded in the route path.
 */
object Routes {
    // Top-level tabs
    const val HOME = "home"
    const val HISTORY = "history"
    const val MINTS = "mints"
    const val SETTINGS = "settings"

    // Pushed destinations (PR 1 stubs; expanded as later PRs land)
    const val SCANNER = "scanner"
    const val CONTACTLESS = "contactless"
    const val SEND_ECASH = "send/ecash"
    const val SEND_LIGHTNING = "send/lightning"
    const val RECEIVE_ECASH = "receive/ecash"
    const val RECEIVE_LIGHTNING = "receive/lightning"

    // With arguments
    const val MINT_DETAIL = "mints/{mintUrl}"
    const val TRANSACTION_DETAIL = "history/transaction/{transactionId}"
    const val CASHU_REQUEST_DETAIL = "request/{requestId}"
    const val RECEIVE_TOKEN_DETAIL = "receive/token-detail"

    // Settings sub-screens
    const val SETTINGS_BACKUP = "settings/backup"
    const val SETTINGS_LIGHTNING = "settings/lightning"
    const val SETTINGS_P2PK = "settings/p2pk"
    const val SETTINGS_NOSTR = "settings/nostr"
    const val SETTINGS_NWC = "settings/nwc"
    const val SETTINGS_PRIVACY = "settings/privacy"
    const val SETTINGS_APPEARANCE = "settings/appearance"

    /** Top tabs in display order. */
    val TopTabs: List<TopTab> = listOf(
        TopTab.Home,
        TopTab.History,
        TopTab.Mints,
        TopTab.Settings,
    )
}

enum class TopTab(val route: String, val label: String) {
    Home(Routes.HOME, "Wallet"),
    History(Routes.HISTORY, "History"),
    Mints(Routes.MINTS, "Mints"),
    Settings(Routes.SETTINGS, "Settings"),
}
