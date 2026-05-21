package org.cashu.wallet.Core

object MnemonicInput {
    private val supportedWordCounts = setOf(12, 24)
    val supportedWordCountLabel = supportedWordCounts.sorted().joinToString(" or ")

    fun normalize(phrase: String): String =
        phrase.trim().lowercase().split(Regex("\\s+")).filter(String::isNotBlank).joinToString(" ")

    fun words(phrase: String): List<String> =
        normalize(phrase).split(" ").filter(String::isNotBlank)

    fun hasSupportedWordCount(phrase: String): Boolean =
        words(phrase).size in supportedWordCounts

    fun matches(left: String, right: String): Boolean =
        normalize(left) == normalize(right)
}
