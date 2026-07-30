package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.CashuTheme

// 64dp terminal glyph per the iOS PaymentStatusView spec; 40dp working spinner.
private val StatusGlyphSize = 64.dp
private val SpinnerSize = 40.dp

enum class PaymentStatusPhase { Processing, Success, Failure }

/**
 * The shared full-screen terminal for every pay flow (iOS PaymentStatusView):
 * processing → success/failure on the bare canvas. The glyph slot morphs
 * spinner (custom [SpinnerRing]) → 64dp green check / red X with a smooth
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
    Box(
        modifier = modifier
            .fillMaxSize()
            .graphicsLayer {
                alpha = entranceAlpha
                scaleX = entranceScale
                scaleY = entranceScale
            },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = CashuTheme.spacing.page),
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
                    modifier = Modifier.size(StatusGlyphSize),
                    contentAlignment = Alignment.Center,
                ) {
                    when (current) {
                        // Custom ring (iOS SpinnerRing port) — the shared
                        // processing loop across every pay flow.
                        PaymentStatusPhase.Processing -> SpinnerRing(
                            size = SpinnerSize,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        // The one celebration beat: the check bounces once and
                        // materializes blur-to-sharp (iOS .bounce + materializeBlur);
                        // everything else stays de-sprung.
                        PaymentStatusPhase.Success -> {
                            val bounce = rememberBounceScale(trigger = current, bounceOnEntry = true)
                            Icon(
                                imageVector = Icons.Filled.CheckCircle,
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
                        // Failure stays still — deliberately no bounce (iOS parity).
                        PaymentStatusPhase.Failure -> Icon(
                            imageVector = Icons.Filled.Cancel,
                            contentDescription = "Failed",
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(StatusGlyphSize),
                        )
                    }
                }
            }
            Spacer(Modifier.height(CashuTheme.spacing.section))
            // Crossfade the title so Processing → terminal reads as one screen
            // whose message changes, not a new screen (single-call hosts).
            AnimatedContent(
                targetState = title,
                transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(150)) },
                label = "payment-status-title",
            ) { currentTitle ->
                Text(
                    text = currentTitle,
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                )
            }
            if (detail != null) {
                Spacer(Modifier.height(CashuTheme.spacing.snug))
                Text(
                    text = detail,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
            // Opted-in payment flows keep the same metadata slot throughout
            // processing and terminal outcomes.
            if (rows != null && (phase != PaymentStatusPhase.Processing || showRowsDuringProcessing)) {
                Spacer(Modifier.height(CashuTheme.spacing.section))
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .graphicsLayer {
                            alpha = if (showRowsDuringProcessing) 1f else terminalAlpha
                        },
                ) { rows() }
            }
        }
        if (phase != PaymentStatusPhase.Processing && onDone != null) {
            PrimaryButton(
                text = doneLabel,
                onClick = onDone,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = CashuTheme.spacing.comfortable)
                    .navigationBarsPadding()
                    .padding(bottom = CashuTheme.spacing.comfortable)
                    .graphicsLayer { alpha = terminalAlpha },
            )
        }
    }
}
