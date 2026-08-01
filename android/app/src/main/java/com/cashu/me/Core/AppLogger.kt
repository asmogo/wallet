package com.cashu.me.Core

import android.util.Log

object AppLogger {
    private const val prefix = "CashuWallet"
    private val nostrSecretPattern = Regex("""\bnsec1[023456789acdefghjklmnpqrstuvwxyz]+\b""", RegexOption.IGNORE_CASE)
    private val nwcUriPattern = Regex("""\bnostr\+walletconnect://[^\s,;)"']+""", RegexOption.IGNORE_CASE)
    private val cashuTokenPattern = Regex("""\bcashu[ab][a-z0-9_\-=]{16,}\b""", RegexOption.IGNORE_CASE)
    private val cashuRequestPattern = Regex("""\bcreq(?:a|b1)[a-z0-9_\-=]{8,}\b""", RegexOption.IGNORE_CASE)
    private val lightningPayloadPattern = Regex(
        """\b(?:lnbc|lntb|lnbcrt|lno|lni|lnr|lnurl)[a-z0-9]{16,}\b""",
        RegexOption.IGNORE_CASE,
    )
    private val bitcoinUriPattern = Regex("""\bbitcoin:(?://)?[^\s,;)"']+""", RegexOption.IGNORE_CASE)
    private val bech32BitcoinAddressPattern = Regex("""\b(?:bc1|tb1|bcrt1)[a-z0-9]{20,}\b""", RegexOption.IGNORE_CASE)
    private val base58BitcoinAddressPattern = Regex("""\b[13mn2][a-km-zA-HJ-NP-Z1-9]{25,34}\b""")
    private val emailPattern = Regex("""\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b""", RegexOption.IGNORE_CASE)
    private val urlPattern = Regex("""https?://[^\s,;)"']+""", RegexOption.IGNORE_CASE)
    private val localPathPattern = Regex("""(?<![A-Za-z0-9])/(?:Users|private|data|var|tmp|storage|sdcard)/[^\s,;)"']+""")
    private val labeledSecretPattern = Regex(
        pattern = """(?i)\b(mnemonic|seed phrase|private key|secret)\s*[:=]\s*([^\s,;]+(?:\s+[^\s,;]+){0,23})""",
    )

    object wallet {
        fun info(message: String) = Log.i("$prefix.Wallet", privacySafeMessage(message))
        fun debug(message: String) = Log.d("$prefix.Wallet", privacySafeMessage(message))
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.Wallet", privacySafeError(message, throwable))
    }

    object security {
        fun info(message: String) = Log.i("$prefix.Security", privacySafeMessage(message))
        fun debug(message: String) = Log.d("$prefix.Security", privacySafeMessage(message))
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.Security", privacySafeError(message, throwable))
    }

    object network {
        fun info(message: String) = Log.i("$prefix.Network", privacySafeMessage(message))
        fun debug(message: String) = Log.d("$prefix.Network", privacySafeMessage(message))
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.Network", privacySafeError(message, throwable))
    }

    object ui {
        fun info(message: String) = Log.i("$prefix.UI", privacySafeMessage(message))
        fun debug(message: String) = Log.d("$prefix.UI", privacySafeMessage(message))
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.UI", privacySafeError(message, throwable))
    }

    internal fun privacySafeMessage(message: String): String {
        return message
            .replace(nostrSecretPattern, "<redacted-nsec>")
            .replace(nwcUriPattern, "<redacted-nwc-uri>")
            .replace(cashuTokenPattern, "<redacted-cashu-token>")
            .replace(cashuRequestPattern, "<redacted-cashu-request>")
            .replace(lightningPayloadPattern, "<redacted-lightning-payload>")
            .replace(bitcoinUriPattern, "<redacted-bitcoin-uri>")
            .replace(bech32BitcoinAddressPattern, "<redacted-bitcoin-address>")
            .replace(base58BitcoinAddressPattern, "<redacted-bitcoin-address>")
            .replace(emailPattern, "<redacted-email>")
            .replace(urlPattern, "<redacted-url>")
            .replace(localPathPattern, "<redacted-path>")
            .replace(labeledSecretPattern) { match ->
                "${match.groupValues[1]}=<redacted>"
            }
    }

    internal fun privacySafeThrowable(error: Throwable): Throwable {
        val safe = RuntimeException(
            "${error::class.java.simpleName}: ${privacySafeMessage(error.message.orEmpty())}",
        )
        safe.stackTrace = error.stackTrace
        return safe
    }

    private fun privacySafeError(message: String, throwable: Throwable?): String {
        val safeMessage = privacySafeMessage(message)
        val safeThrowable = throwable ?: return safeMessage
        val throwableMessage = privacySafeMessage(safeThrowable.message.orEmpty())
        return "$safeMessage (${safeThrowable::class.java.simpleName}: $throwableMessage)"
    }
}
