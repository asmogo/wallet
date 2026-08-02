package com.cashu.me.ui.mints

/**
 * A known public mint offered as a one-tap quick-add. Turns "type a mint URL
 * from memory" into recognition for users who have none configured yet.
 *
 * [iconUrl] is a curated logo: these mints aren't tracked yet, so there is no
 * fetched `MintInfo.iconUrl` to fall back on. A miss degrades to the monogram
 * in `MintAvatar`, so a stale URL never breaks the row.
 */
data class RecommendedMint(val name: String, val url: String, val iconUrl: String)

/**
 * The curated shortlist. Mirrors iOS `RecommendedMint.suggested`
 * (ios/CashuWallet/Views/Components/ActivityOrbView.swift) — keep both in sync.
 *
 * Shared by the onboarding first-mint picker and the connect-a-mint sheet.
 */
val RecommendedMints = listOf(
    RecommendedMint("Minibits", "https://mint.minibits.cash/Bitcoin", "https://minibits.cash/icon-192.png"),
    RecommendedMint("Chorus OFF Mint", "https://mint.chorus.community", "https://chorus.community/apple-touch-icon.png"),
    RecommendedMint("Macadamia", "https://mint.macadamia.cash", "https://cypherbase.cc/images/logo_w256.png"),
)
