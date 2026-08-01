package com.cashu.me.Models

import kotlinx.serialization.Serializable

@Serializable
data class MintInfo(
    val url: String,
    val name: String = "Unknown Mint",
    val description: String? = null,
    val isActive: Boolean = true,
    val balance: Long = 0,
    val iconUrl: String? = null,
    val units: List<String> = listOf("sat"),
    // NUT-04 mintable units. Empty for records stored before multi-unit landed;
    // effectiveMintUnits falls back to the full unit set until the next refresh.
    val mintUnits: List<String> = emptyList(),
    // NUT-04/NUT-05 rails, tri-state: null = never fetched (unknown — the
    // compatibility default applies), empty = the live mint reported none
    // (absent — hide the direction), non-empty = the reported methods.
    val supportedMintMethods: List<PaymentMethodKind>? = null,
    val supportedMeltMethods: List<PaymentMethodKind>? = null,
    val onchainMintConfirmations: Int? = null,
    // NUT-06 self-reported metadata (contact / terms / software). Empty or null
    // when the mint did not report it — the UI never invents placeholders.
    val contacts: List<MintContact> = emptyList(),
    val tosUrl: String? = null,
    val software: MintSoftware? = null,
    val descriptionLong: String? = null,
    val motd: String? = null,
    val nutSupport: NutSupport = NutSupport(),
    val lastUpdatedEpochMillis: Long = System.currentTimeMillis(),
) {
    val id: String get() = url

    /**
     * Mint (receive) rails with the pre-fetch compatibility default: a mint whose
     * NUT-06 metadata was never fetched is assumed BOLT11; a mint that reported
     * an empty list stays empty.
     */
    val effectiveMintMethods: List<PaymentMethodKind>
        get() = supportedMintMethods ?: listOf(PaymentMethodKind.Bolt11)

    /** Melt (send) rails with the pre-fetch compatibility default (see [effectiveMintMethods]). */
    val effectiveMeltMethods: List<PaymentMethodKind>
        get() = supportedMeltMethods ?: listOf(PaymentMethodKind.Bolt11)

    val effectiveMintUnits: List<String> get() = mintUnits.ifEmpty { units }

    /** Ecash units this mint holds/advertises (send-side gating). */
    val supportsMultipleUnits: Boolean get() = units.size > 1
    val defaultUnit: String get() = defaultOf(units)
    fun resolvedUnit(unit: String?): String =
        if (unit != null && units.contains(unit)) unit else defaultUnit

    /** Units mintable over Lightning per NUT-04 (receive-side gating). */
    val supportsMultipleMintUnits: Boolean get() = effectiveMintUnits.size > 1
    val defaultMintUnit: String get() = defaultOf(effectiveMintUnits)
    fun resolvedMintUnit(unit: String?): String =
        if (unit != null && effectiveMintUnits.contains(unit)) unit else defaultMintUnit

    private fun defaultOf(candidates: List<String>): String = when {
        candidates.contains("sat") -> "sat"
        else -> candidates.sorted().firstOrNull() ?: "sat"
    }
}

/**
 * One contact channel the mint self-reports via NUT-06 (`method` is e.g.
 * "email", "nostr", "twitter"; `info` the address/handle/URL).
 */
@Serializable
data class MintContact(
    val method: String,
    val info: String,
)

/** Mint implementation name + version self-reported via NUT-06. */
@Serializable
data class MintSoftware(
    val name: String,
    val version: String,
)

/**
 * Per-NUT capability flags reported by the mint (NUT-06 info). All default false so
 * records persisted before this landed deserialize cleanly; only the live fetch
 * populates them.
 */
@Serializable
data class NutSupport(
    val tokenStateCheck: Boolean = false,    // NUT-07
    val lightningFeeReturn: Boolean = false, // NUT-08
    val restoreFromSeed: Boolean = false,    // NUT-09
    val spendingConditions: Boolean = false, // NUT-10
    val p2pk: Boolean = false,               // NUT-11
    val dleq: Boolean = false,               // NUT-12
    val htlc: Boolean = false,               // NUT-14
    val webSocket: Boolean = false,          // NUT-20
)
