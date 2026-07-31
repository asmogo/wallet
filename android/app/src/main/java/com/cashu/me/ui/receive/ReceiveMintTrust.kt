package com.cashu.me.ui.receive

import java.net.IDN
import java.net.URI
import com.cashu.me.Core.normalizedMintUrlForSelection

/**
 * Trust context for the mint encoded in a received bearer token.
 *
 * Receiving from an untracked mint adds it to the wallet after redemption, so
 * the review screen shows a caution notice (iOS parity). Claim stays one-tap;
 * the notice is the trust gate — not a second dialog.
 */
internal data class ReceiveMintTrust(
    val host: String,
    val mintKnown: Boolean,
) {
    val showWarning: Boolean get() = !mintKnown
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
