package com.cashu.me.ui.onboarding

import com.cashu.me.Core.normalizeUserMintUrl

internal const val InvalidFirstMintUrlMessage = "That doesn't look like a mint URL."

internal data class FirstMintUrlDraft(
    val input: String = "",
    val error: String? = null,
) {
    fun updateInput(value: String): FirstMintUrlDraft =
        if (value == input) this else copy(input = value, error = null)

    fun stage(existingUrls: Collection<String>): FirstMintUrlStage {
        val normalized = normalizeUserMintUrl(input)
            ?: return FirstMintUrlStage(
                draft = copy(error = InvalidFirstMintUrlMessage),
            )
        if (existingUrls.any { it.equals(normalized, ignoreCase = true) }) {
            return FirstMintUrlStage(
                draft = copy(error = "That mint is already in the list."),
            )
        }
        return FirstMintUrlStage(
            draft = FirstMintUrlDraft(),
            stagedUrl = normalized,
        )
    }
}

internal data class FirstMintUrlStage(
    val draft: FirstMintUrlDraft,
    val stagedUrl: String? = null,
)
