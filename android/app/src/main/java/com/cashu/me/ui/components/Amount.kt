package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import com.cashu.me.ui.theme.withMonoDigits

/**
 * Monospaced-digit amount text. Use everywhere balances, amounts, and fees
 * appear. Cross-fades on change — the same quiet, no-slide transition the
 * app's other amount swaps already use (see [AmountFlipDisplay], [BalanceDisplay]).
 *
 * @param annotated a pre-composed styled string to render in place of [text],
 *   used by [AmountHero] to set the value and its unit as two runs of one
 *   string. [text] still supplies the cross-fade key and the fallback
 *   accessibility reading, so the animation keys on the value rather than on
 *   incidental styling.
 * @param semanticsLabel replaces the node's reading entirely. Amount strings
 *   contain glyphs like `₿` that announce as nothing useful, so a hero should
 *   always pass a spoken form.
 */
@Composable
fun AmountText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    color: Color = Color.Unspecified,
    animated: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    // Ellipsis, not Clip: a hard cut mid-glyph reads as a rendering fault,
    // and every caller that had thought about it was already overriding this.
    overflow: TextOverflow = TextOverflow.Ellipsis,
    autoSize: TextAutoSize? = null,
    annotated: AnnotatedString? = null,
    semanticsLabel: String? = null,
) {
    val resolvedColor = if (color == Color.Unspecified) LocalContentColor.current else color
    val finalStyle = style.withMonoDigits().copy(color = resolvedColor)
    val contentAlignment = when (finalStyle.textAlign) {
        TextAlign.Center -> Alignment.Center
        TextAlign.End, TextAlign.Right -> Alignment.CenterEnd
        else -> Alignment.CenterStart
    }
    val semantics = semanticsLabel?.let { label ->
        Modifier.clearAndSetSemantics { contentDescription = label }
    } ?: Modifier
    // Auto-size needs a bounded width; fill so the Text sees the parent's max.
    val textModifier = (if (autoSize != null) Modifier.fillMaxWidth() else Modifier).then(semantics)

    if (!animated) {
        Text(
            text = annotated ?: AnnotatedString(text),
            style = finalStyle,
            modifier = modifier.then(textModifier),
            maxLines = maxLines,
            overflow = overflow,
            autoSize = autoSize,
        )
        return
    }
    AnimatedContent(
        // Keyed on the plain value: styling changes must not trigger a fade.
        targetState = text,
        transitionSpec = {
            fadeIn(spring(stiffness = Spring.StiffnessMedium))
                .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
        },
        modifier = modifier,
        contentAlignment = contentAlignment,
        label = "amount-text",
    ) { targetText ->
        Text(
            text = if (targetText == text && annotated != null) annotated else AnnotatedString(targetText),
            style = finalStyle,
            modifier = textModifier,
            maxLines = maxLines,
            overflow = overflow,
            autoSize = autoSize,
        )
    }
}
