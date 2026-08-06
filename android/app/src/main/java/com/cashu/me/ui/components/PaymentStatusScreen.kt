package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.CashuTheme

// Exact geometry shared with iOS PaymentStatusView / PayFlowScaffold.
private val StatusIconSlotSize = 72.dp
private val StatusGlyphSize = 64.dp
private val StatusHeroMinHeight = 220.dp
private val StatusDescriptionMinHeight = 44.dp
private val StatusDescriptionHorizontalPadding = 32.dp
private const val StatusTopFraction = 0.16f
private val SpinnerSize = 64.dp

enum class PaymentStatusPhase { Processing, Success, Failure }

/**
 * The shared full-screen terminal for every pay flow (iOS PaymentStatusView):
 * processing → success/failure on the bare canvas. The glyph slot morphs
 * 64dp spinner (custom [SpinnerRing]) → green check / red X with a smooth
 * fade + scale-in from 0.9. The success check carries the one celebration
 * beat — a single bounce and a blur-to-sharp materialize; nothing else
 * springs, and failure stays deliberately still.
 * Success/failure require an explicit Done tap; processing shows no actions.
 * Callers may pass [rows] (InspectorRow metadata — Amount/Fee/Mint, the iOS
 * payment detail rows). Set [showRowsDuringProcessing] when the row set must
 * stay anchored across processing, success, and failure.
 */
@Composable
fun PaymentStatusScreen(
    phase: PaymentStatusPhase,
    title: String,
    detail: String? = null,
    modifier: Modifier = Modifier,
    doneLabel: String = "Done",
    onDone: (() -> Unit)? = null,
    rows: (@Composable ColumnScope.() -> Unit)? = null,
    showRowsDuringProcessing: Boolean = false,
) {
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(phase) {
        when (phase) {
            PaymentStatusPhase.Success -> haptics.performHapticFeedback(HapticFeedbackType.Confirm)
            PaymentStatusPhase.Failure -> haptics.performHapticFeedback(HapticFeedbackType.Reject)
            PaymentStatusPhase.Processing -> Unit
        }
    }
    // Screen entrance: the terminal fades + settles in over the form instead of
    // hard-cutting (callers mount it as a full replacement of the send body).
    val inspectionMode = LocalInspectionMode.current
    var appeared by remember { mutableStateOf(inspectionMode) }
    LaunchedEffect(Unit) { appeared = true }
    val entranceAlpha by animateFloatAsState(
        targetValue = if (appeared) 1f else 0f,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "status-entrance-alpha",
    )
    val entranceScale by animateFloatAsState(
        targetValue = if (appeared) 1f else 0.96f,
        animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
        label = "status-entrance-scale",
    )
    // Opted-in rows stay visible across every phase. The action arrives with the
    // terminal glyph morph; animateFloatAsState starts at its target for screens
    // mounted directly in a terminal phase.
    val terminalAlpha by animateFloatAsState(
        targetValue = if (phase != PaymentStatusPhase.Processing) 1f else 0f,
        animationSpec = tween(durationMillis = 220, delayMillis = 120),
        label = "status-details-alpha",
    )
    // No background here: the terminal inherits its host surface (sheet
    // container or full-screen Surface), so phases never shift the canvas color.
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .graphicsLayer {
                alpha = entranceAlpha
                scaleX = entranceScale
                scaleY = entranceScale
            },
    ) {
        val scaffoldHeight = maxHeight
        val failureTint = if (MaterialTheme.colorScheme.background.luminance() < 0.5f) {
            Color(0xFFFF453A)
        } else {
            Color(0xFFFF3B30)
        }
        val hasAction = phase != PaymentStatusPhase.Processing && onDone != null

        Column(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
            ) {
                Spacer(Modifier.height(scaffoldHeight * StatusTopFraction))
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = StatusHeroMinHeight),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    AnimatedContent(
                        targetState = phase,
                        transitionSpec = {
                            // The check/X grows in gently from 0.9; the spinner just fades.
                            val enter = if (targetState == PaymentStatusPhase.Processing) {
                                fadeIn(tween(200))
                            } else {
                                fadeIn(tween(200)) + scaleIn(
                                    animationSpec = spring(
                                        dampingRatio = 0.7f,
                                        stiffness = Spring.StiffnessMediumLow,
                                    ),
                                    initialScale = 0.9f,
                                )
                            }
                            enter togetherWith fadeOut(tween(150))
                        },
                        label = "payment-status-glyph",
                    ) { current ->
                        Box(
                            modifier = Modifier.size(StatusIconSlotSize),
                            contentAlignment = Alignment.Center,
                        ) {
                            when (current) {
                                PaymentStatusPhase.Processing -> SpinnerRing(
                                    size = SpinnerSize,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                                PaymentStatusPhase.Success -> {
                                    val bounce = rememberBounceScale(trigger = current, bounceOnEntry = true)
                                    StatusCircleGlyph(
                                        success = true,
                                        contentDescription = "Success",
                                        tint = CashuTheme.colors.received,
                                        modifier = Modifier
                                            .size(StatusGlyphSize)
                                            .graphicsLayer {
                                                scaleX = bounce
                                                scaleY = bounce
                                            }
                                            .materializeBlur(),
                                    )
                                }
                                PaymentStatusPhase.Failure -> StatusCircleGlyph(
                                    success = false,
                                    contentDescription = "Failed",
                                    tint = failureTint,
                                    modifier = Modifier.size(StatusGlyphSize),
                                )
                            }
                        }
                    }
                    Spacer(Modifier.height(CashuTheme.spacing.comfortable))
                    AnimatedContent(
                        targetState = title,
                        transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(150)) },
                        label = "payment-status-title",
                    ) { currentTitle ->
                        Text(
                            text = currentTitle,
                            style = MaterialTheme.typography.titleLarge.copy(
                                fontWeight = FontWeight.SemiBold,
                            ),
                            color = MaterialTheme.colorScheme.onSurface,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.padding(horizontal = CashuTheme.spacing.page),
                        )
                    }
                    Spacer(Modifier.height(CashuTheme.spacing.snug))
                    Text(
                        text = detail ?: " ",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        maxLines = 3,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = StatusDescriptionMinHeight)
                            .padding(horizontal = StatusDescriptionHorizontalPadding)
                            .graphicsLayer { alpha = if (detail == null) 0f else 1f },
                    )
                }
                if (rows != null && (phase != PaymentStatusPhase.Processing || showRowsDuringProcessing)) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = CashuTheme.spacing.snug)
                            .padding(horizontal = CashuTheme.spacing.comfortable)
                            .graphicsLayer {
                                alpha = if (showRowsDuringProcessing) 1f else terminalAlpha
                            },
                    ) { rows() }
                }
            }

            // iOS always reserves the footer footprint, including while processing,
            // so the anchored hero never shifts when the CTA appears.
            PrimaryButton(
                text = if (hasAction) doneLabel else " ",
                onClick = onDone ?: {},
                enabled = hasAction,
                modifier = Modifier
                    .padding(horizontal = CashuTheme.spacing.comfortable)
                    .navigationBarsPadding()
                    .padding(bottom = CashuTheme.spacing.comfortable)
                    .graphicsLayer { alpha = if (hasAction) terminalAlpha else 0f }
                    .then(if (hasAction) Modifier else Modifier.clearAndSetSemantics {}),
            )
        }
    }
}

/**
 * SF Symbols-style filled status glyph. Compose's Material check/cancel vectors
 * use square stroke ends, while iOS `checkmark.circle.fill` and
 * `xmark.circle.fill` use rounded caps. Drawing the two strokes explicitly keeps
 * Android's silhouette, line weight, and negative space aligned with iOS.
 */
@Composable
private fun StatusCircleGlyph(
    success: Boolean,
    contentDescription: String,
    tint: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(
        modifier = modifier.semantics {
            this.contentDescription = contentDescription
        },
    ) {
        drawCircle(color = tint)
        val strokeWidth = 6.dp.toPx()
        if (success) {
            drawLine(
                color = Color.White,
                start = Offset(size.width * 0.29f, size.height * 0.52f),
                end = Offset(size.width * 0.44f, size.height * 0.67f),
                strokeWidth = strokeWidth,
                cap = StrokeCap.Round,
            )
            drawLine(
                color = Color.White,
                start = Offset(size.width * 0.44f, size.height * 0.67f),
                end = Offset(size.width * 0.72f, size.height * 0.34f),
                strokeWidth = strokeWidth,
                cap = StrokeCap.Round,
            )
        } else {
            drawLine(
                color = Color.White,
                start = Offset(size.width * 0.34f, size.height * 0.34f),
                end = Offset(size.width * 0.66f, size.height * 0.66f),
                strokeWidth = strokeWidth,
                cap = StrokeCap.Round,
            )
            drawLine(
                color = Color.White,
                start = Offset(size.width * 0.66f, size.height * 0.34f),
                end = Offset(size.width * 0.34f, size.height * 0.66f),
                strokeWidth = strokeWidth,
                cap = StrokeCap.Round,
            )
        }
    }
}
