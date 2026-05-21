package org.cashu.wallet.Core

import java.net.URL

internal fun normalizeUserMintUrl(rawUrl: String): String? {
    var url = rawUrl.trim()
    if (url.isBlank()) return null

    url = url.trim('"', '\'')
    if (!url.startsWith("http://", ignoreCase = true) && !url.startsWith("https://", ignoreCase = true)) {
        url = "https://$url"
    }
    url = url.trimEnd('/')
    if (url.any { it.isWhitespace() }) return null

    val parsed = runCatching { URL(url) }.getOrNull() ?: return null
    if (parsed.host.isNullOrBlank()) return null
    if (parsed.protocol != "https") return null
    return url
}

internal fun mintUrlCandidates(rawInput: String): List<String> =
    rawInput
        .split(Regex("""[\s,;]+"""))
        .mapNotNull { normalizeUserMintUrl(it) }
        .distinct()

internal fun shortenMintUrl(url: String): String =
    url.removePrefix("https://")
        .removePrefix("http://")
        .trimEnd('/')
