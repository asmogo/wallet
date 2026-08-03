package com.cashu.me.ui.components

import androidx.compose.foundation.shape.CornerBasedShape
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp

/**
 * Corner treatment for one row inside a "grouped card" (the KeyCard-style
 * surfaceContainerHigh + shapes.medium convention, applied per row instead of
 * to one static Column so a LazyColumn can keep animating each row via
 * `Modifier.animateItem()` on add/remove).
 *
 * - A lone row ([count] == 1) keeps all four corners of [base].
 * - The first row ([index] == 0) keeps [base]'s top corners, squares the bottom.
 * - The last row keeps the bottom corners, squares the top.
 * - Any row strictly in between is squared on all four corners.
 *
 * Pass the actual theme shape ([MaterialTheme.shapes.medium] in practice) as
 * [base] rather than a raw corner radius, so a group always matches whatever
 * the current M3 `Shapes()` scale defines instead of a hardcoded literal.
 */
fun groupItemShape(index: Int, count: Int, base: CornerBasedShape): Shape {
    require(count > 0) { "count must be > 0" }
    require(index in 0 until count) { "index ($index) out of range for count ($count)" }
    val square = CornerSize(0.dp)
    return when {
        count == 1 -> base
        index == 0 -> base.copy(bottomStart = square, bottomEnd = square)
        index == count - 1 -> base.copy(topStart = square, topEnd = square)
        else -> base.copy(square)
    }
}
