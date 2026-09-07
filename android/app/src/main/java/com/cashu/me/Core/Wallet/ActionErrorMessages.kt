package com.cashu.me.Core.Wallet

/** Context for settings failures. Unrecognized technical details never become UI copy. */
object ActionErrorMessages {
    enum class Context(val fallback: String) {
        LightningConnection("Couldn't connect to the Lightning address service. Try again shortly."),
        LightningPayments("Couldn't check for Lightning payments. Try again shortly."),
        LightningMint("Couldn't change your receiving mint. Try again shortly."),
        WalletConnect("Couldn't start Wallet Connect. Check your relays and try again."),
        MintBackup("Couldn't back up your mint list. Check your relays and try again."),
        KeyUpdate("Couldn't update your Nostr key. Try again."),
        KeyGenerate("Couldn't generate a key. Try again."),
        KeyImport("Couldn't import this key. Check it and try again."),
        KeyRemove("Couldn't remove this key. Try again."),
        KeyRename("Couldn't save the key name. Try again."),
    }

    fun message(error: Throwable, context: Context): String {
        val raw = generateSequence(error) { it.cause?.takeUnless { cause -> cause === it } }
            .take(5).joinToString(" ") { it.message.orEmpty() }.lowercase()
        return resolve(raw, context)
    }

    private fun resolve(raw: String, context: Context): String {
        if (context == Context.KeyImport) {
            if ("already" in raw && ("exist" in raw || "added" in raw || "wallet" in raw)) {
                return "This key is already in your wallet."
            }
            val invalidKey = "invalid" in raw && listOf("nsec", "private key", "privatekey", "padding").any { it in raw }
            val invalidEncoding = ("bech32" in raw || "nsec" in raw) &&
                listOf("decode", "decoding", "checksum").any { it in raw }
            if (invalidKey || invalidEncoding) {
                return "That private key doesn't look right. Check that you copied the complete nsec key."
            }
        }
        if (context in setOf(Context.KeyUpdate, Context.KeyGenerate, Context.KeyImport) &&
            ("not initialized" in raw || "no wallet seed" in raw || "no seed available" in raw)) {
            return "Your wallet is still starting up. Try again shortly."
        }
        return context.fallback
    }
}
