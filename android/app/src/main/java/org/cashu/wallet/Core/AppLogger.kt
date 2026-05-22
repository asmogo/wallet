package org.cashu.wallet.Core

import android.util.Log

object AppLogger {
    private const val prefix = "CashuWallet"
    private val nostrSecretPattern = Regex("""\bnsec1[023456789acdefghjklmnpqrstuvwxyz]+\b""", RegexOption.IGNORE_CASE)
    private val labeledSecretPattern = Regex(
        pattern = """(?i)\b(mnemonic|seed phrase|private key|secret)\s*[:=]\s*([^\s,;]+(?:\s+[^\s,;]+){0,23})""",
    )

    object wallet {
        fun info(message: String) = Log.i("$prefix.Wallet", privacySafeMessage(message))
        fun debug(message: String) = Log.d("$prefix.Wallet", privacySafeMessage(message))
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.Wallet", privacySafeMessage(message), throwable)
    }

    object security {
        fun info(message: String) = Log.i("$prefix.Security", privacySafeMessage(message))
        fun debug(message: String) = Log.d("$prefix.Security", privacySafeMessage(message))
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.Security", privacySafeMessage(message), throwable)
    }

    object network {
        fun info(message: String) = Log.i("$prefix.Network", privacySafeMessage(message))
        fun debug(message: String) = Log.d("$prefix.Network", privacySafeMessage(message))
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.Network", privacySafeMessage(message), throwable)
    }

    object ui {
        fun info(message: String) = Log.i("$prefix.UI", privacySafeMessage(message))
        fun debug(message: String) = Log.d("$prefix.UI", privacySafeMessage(message))
        fun error(message: String, throwable: Throwable? = null) = Log.e("$prefix.UI", privacySafeMessage(message), throwable)
    }

    internal fun privacySafeMessage(message: String): String {
        return message
            .replace(nostrSecretPattern, "<redacted-nsec>")
            .replace(labeledSecretPattern) { match ->
                "${match.groupValues[1]}=<redacted>"
            }
    }
}
