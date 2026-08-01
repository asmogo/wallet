package com.cashu.me.ui.mints

import java.net.URI

/**
 * Build a tappable target for a mint-reported contact (iOS `contactURL`).
 * The scheme allowlist is mailto:/http(s) with a parseable host — everything
 * else (javascript:, intent:, garbage) returns null and the row renders as
 * plain text instead of a dead or unsafe link.
 */
internal fun mintContactLink(method: String, info: String): String? {
    val trimmed = info.trim()
    if (trimmed.isEmpty()) return null
    val candidate = when (method.trim().lowercase()) {
        "email" -> if (isPlausibleEmail(trimmed)) "mailto:$trimmed" else null
        "website", "url", "web" -> withHttpScheme(trimmed)        "twitter", "x" ->
            if (trimmed.startsWith("http")) trimmed
            else "https://twitter.com/${trimmed.removePrefix("@")}"
        "telegram" ->
            if (trimmed.startsWith("http")) trimmed
            else "https://t.me/${trimmed.removePrefix("@")}"
        else -> if (trimmed.startsWith("http")) trimmed else null
    } ?: return null
    return candidate.takeIf(::isSafeExternalLink)
}

/**
 * A mint-reported external URL (e.g. Terms of Service) that is safe to open:
 * trimmed, http(s) only, with a non-blank host. Null when invalid or absent,
 * so callers render no row rather than a dead one.
 */
internal fun safeExternalHttpUrl(raw: String?): String? {
    val trimmed = raw?.trim().orEmpty()
    if (trimmed.isEmpty()) return null
    return trimmed.takeIf(::isSafeExternalLink)
}

/** Host portion of a safe external URL, for labeling the link's destination. */
internal fun externalUrlHost(url: String): String? =
    runCatching { URI(url).host }.getOrNull()

// Bare hosts gain https://; anything already carrying a non-http scheme
// (intent:, ftp:, javascript:, …) is rejected rather than disguised.
private val explicitScheme = Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:")

private fun withHttpScheme(raw: String): String? = when {
    raw.startsWith("http") -> raw
    explicitScheme.containsMatchIn(raw) -> null
    else -> "https://$raw"
}

private fun isPlausibleEmail(value: String): Boolean =
    value.length <= 254 && value.none { it.isWhitespace() } && value.count { it == '@' } == 1

private fun isSafeExternalLink(url: String): Boolean {
    val uri = runCatching { URI(url) }.getOrNull() ?: return false
    return when (uri.scheme?.lowercase()) {
        "mailto" -> true
        "http", "https" -> !uri.host.isNullOrBlank()
        else -> false
    }
}
