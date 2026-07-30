package com.cashu.me.ui.receive

import java.net.IDN
import java.net.URI
import com.cashu.me.Core.normalizedMintUrlForSelection

internal enum class ReceiveMintClaimAction {
    Claim,
    RequestConfirmation,
}

/**
 * Trust decision for the mint encoded in a received bearer token.
 *
 * Receiving from an untracked mint adds it to the wallet after redemption, so
 * the first receive must require an explicit second confirmation. Tracked mints
 * keep the normal one-tap claim path.
 */
internal data class ReceiveMintTrust(
    val host: String,
    val mintKnown: Boolean,
) {
    val requiresConfirmation: Boolean get() = !mintKnown

    fun claimAction(userConfirmed: Boolean): ReceiveMintClaimAction =
        if (requiresConfirmation && !userConfirmed) {
            ReceiveMintClaimAction.RequestConfirmation
        } else {
            ReceiveMintClaimAction.Claim
        }
}

internal fun receiveMintTrust(
    mintUrl: String,
    knownMintUrls: Iterable<String>,
): ReceiveMintTrust {
    val normalizedTarget = normalizedMintUrlForSelection(mintUrl)
    val mintKnown = normalizedTarget != null && knownMintUrls.any {
        normalizedMintUrlForSelection(it) == normalizedTarget
    }
    return ReceiveMintTrust(
        host = normalizedMintHost(mintUrl),
        mintKnown = mintKnown,
    )
}

/** A stable, scheme/path-free host for the trust warning. */
internal fun normalizedMintHost(mintUrl: String): String {
    val trimmed = mintUrl.trim()
    val withScheme = if (trimmed.contains("://")) trimmed else "https://$trimmed"
    val host = runCatching { URI(withScheme).host }
        .getOrNull()
        ?.trim()
        ?.trimEnd('.')
        ?.takeIf { it.isNotBlank() }
        ?: return trimmed

    return runCatching { IDN.toASCII(host).lowercase() }
        .getOrDefault(host.lowercase())
}
