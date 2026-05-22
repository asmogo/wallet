package org.cashu.wallet.Views.Components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp

@Composable
fun Modifier.liquidGlass(
    shape: Shape = RoundedCornerShape(10.dp),
    interactive: Boolean = false,
): Modifier {
    val tintAlpha = if (interactive) 0.72f else 0.58f
    return this
        .clip(shape)
        .background(MaterialTheme.colorScheme.surface.copy(alpha = tintAlpha))
        .border(
            BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f)),
            shape,
        )
}

@Composable
fun Modifier.liquidGlassMaterial(
    shape: Shape = RoundedCornerShape(10.dp),
): Modifier = liquidGlass(shape = shape, interactive = false)

@Composable
fun Modifier.fullWidthCapsuleSurface(): Modifier = this
    .fillMaxWidth()
    .liquidGlass(shape = CircleShape, interactive = true)

@Composable
fun CanvasDivider(
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(0.5.dp)
            .background(MaterialTheme.colorScheme.outlineVariant),
    )
}
