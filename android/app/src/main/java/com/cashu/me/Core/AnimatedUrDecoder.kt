package com.cashu.me.Core

import org.cashudevkit.TokenUrDecoder

data class AnimatedUrDecodeUpdate(
    val content: String?,
    val progress: Float,
    val errorMessage: String? = null,
)

/**
 * Reassembles a Cashu token from scanned NUT-16 animated-QR frames
 * (`ur:bytes/…`). Thin wrapper over CDK's fountain-code decoder: frames can
 * arrive in any order and enough of them recover the token.
 *
 * The native decoder is created lazily so rejecting non-UR content never
 * touches the CDK library.
 */
class AnimatedUrDecoder {
    private var decoder: TokenUrDecoder? = null

    private fun activeDecoder(): TokenUrDecoder =
        decoder ?: TokenUrDecoder().also { decoder = it }

    fun reset() {
        decoder = null
    }

    fun receivePart(part: String): AnimatedUrDecodeUpdate {
        val trimmed = part.trim()
        if (!trimmed.startsWith("ur:", ignoreCase = true)) {
            return AnimatedUrDecodeUpdate(content = null, progress = progress(), errorMessage = "Not a UR fragment.")
        }

        return runCatching {
            val active = activeDecoder()
            active.receive(trimmed)
            if (active.complete()) {
                val token = active.token()
                    ?: return@runCatching AnimatedUrDecodeUpdate(
                        content = null,
                        progress = progress(),
                        errorMessage = "Unable to decode animated QR.",
                    )
                AnimatedUrDecodeUpdate(content = token.encode(), progress = 1f)
            } else {
                AnimatedUrDecodeUpdate(content = null, progress = progress())
            }
        }.getOrElse { error ->
            AnimatedUrDecodeUpdate(
                content = null,
                progress = progress(),
                errorMessage = error.message ?: "Unable to decode animated QR.",
            )
        }
    }

    private fun progress(): Float {
        val active = decoder ?: return 0f
        val total = active.fragmentCount().toInt()
        if (total <= 0) return 0f
        // Fountain parts count fragments recovered via the code too, so this
        // tracks real decode progress rather than just distinct frames seen.
        val resolved = active.resolvedFragmentCount()?.toInt() ?: return 0f
        return (resolved.toFloat() / total.toFloat()).coerceIn(0f, 0.99f)
    }
}
