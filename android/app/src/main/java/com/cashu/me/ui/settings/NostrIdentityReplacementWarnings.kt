package com.cashu.me.ui.settings

internal object NostrIdentityReplacementWarnings {
    const val Generate =
        "This replaces your current Nostr key with a newly generated key. " +
            "Your Lightning address will change, Nostr apps and messages will use a different identity, " +
            "and your old key will be replaced."

    const val Import =
        "This replaces your current Nostr key with the imported key. " +
            "Your Lightning address will change, Nostr apps and messages will use a different identity, " +
            "and your old key will be replaced."

    const val Reset =
        "This switches to the Nostr key derived from your wallet seed. " +
            "Your Lightning address will change, Nostr apps and messages will use a different identity, " +
            "and your old custom key will be deleted and replaced."

    fun switchTo(destination: String): String =
        "This switches your Nostr key source to $destination. " +
            "Your Lightning address will change, Nostr apps and messages will use a different identity, " +
            "and your old key will be replaced."
}
