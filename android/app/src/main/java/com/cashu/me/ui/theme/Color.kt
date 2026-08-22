package com.cashu.me.ui.theme

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color

// Semantic state hues. Received/pending/error communicate payment state and are
// the only chromatic colors in the app. Everything else is the monochrome
// "inverted ink" scheme below.
val ReceivedGreen = Color(0xFF34C759)
// Apple's systemOrange, the way ReceivedGreen is already Apple's systemGreen.
// Was Material Orange 800 (#EF6C00) — the only state hue that had drifted off
// iOS, which showed as a muddy orange next to an iOS-matched green.
val PendingOrange = Color(0xFFFF9500)
val ErrorRed = Color(0xFFC62828)

// ---------------------------------------------------------------------------
// Inverted-ink monochrome scheme.
//
// Brand identity shared with iOS: pure white canvas + black ink in light mode,
// pure black canvas + white ink in dark mode. All neutrals are zero-chroma
// grays; color is reserved for payment state (green/orange/red).
// ---------------------------------------------------------------------------

internal val LightInkColorScheme = lightColorScheme(
    primary = Color(0xFF000000),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFE8E8E8),
    onPrimaryContainer = Color(0xFF000000),
    inversePrimary = Color(0xFFFFFFFF),
    secondary = Color(0xFF5C5C5C),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFECECEC),
    onSecondaryContainer = Color(0xFF1A1A1A),
    tertiary = Color(0xFF5C5C5C),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFECECEC),
    onTertiaryContainer = Color(0xFF1A1A1A),
    background = Color(0xFFFFFFFF),
    onBackground = Color(0xFF000000),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF000000),
    surfaceVariant = Color(0xFFF2F2F2),
    onSurfaceVariant = Color(0xFF6B6B6B),
    surfaceTint = Color(0xFF000000),
    inverseSurface = Color(0xFF1A1A1A),
    inverseOnSurface = Color(0xFFF2F2F2),
    error = ErrorRed,
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF8C1D18),
    outline = Color(0xFFB8B8B8),
    outlineVariant = Color(0xFFE0E0E0),
    scrim = Color(0xFF000000),
    surfaceBright = Color(0xFFFFFFFF),
    surfaceDim = Color(0xFFE0E0E0),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFF7F7F7),
    surfaceContainer = Color(0xFFF2F2F2),
    surfaceContainerHigh = Color(0xFFEDEDED),
    surfaceContainerHighest = Color(0xFFE8E8E8),
)

internal val DarkInkColorScheme = darkColorScheme(
    primary = Color(0xFFFFFFFF),
    onPrimary = Color(0xFF000000),
    primaryContainer = Color(0xFF2A2A2A),
    onPrimaryContainer = Color(0xFFFFFFFF),
    inversePrimary = Color(0xFF000000),
    secondary = Color(0xFFB3B3B3),
    onSecondary = Color(0xFF000000),
    secondaryContainer = Color(0xFF262626),
    onSecondaryContainer = Color(0xFFECECEC),
    tertiary = Color(0xFFB3B3B3),
    onTertiary = Color(0xFF000000),
    tertiaryContainer = Color(0xFF262626),
    onTertiaryContainer = Color(0xFFECECEC),
    background = Color(0xFF000000),
    onBackground = Color(0xFFFFFFFF),
    surface = Color(0xFF000000),
    onSurface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFF1F1F1F),
    onSurfaceVariant = Color(0xFF9E9E9E),
    surfaceTint = Color(0xFFFFFFFF),
    inverseSurface = Color(0xFFECECEC),
    inverseOnSurface = Color(0xFF1A1A1A),
    // Solid red (Material Red 400), not the desaturated Red 200 that read as
    // pink on the black canvas. Matches the 300/400 tonal weight of the dark
    // received-green / pending-orange, and stays clearly red for destructive
    // affordances (Remove mint, swipe-to-delete) while keeping AA contrast.
    error = Color(0xFFEF5350),
    onError = Color(0xFF4E0002),
    errorContainer = Color(0xFF8C1D18),
    onErrorContainer = Color(0xFFFFDAD6),
    outline = Color(0xFF5A5A5A),
    outlineVariant = Color(0xFF2C2C2C),
    scrim = Color(0xFF000000),
    surfaceBright = Color(0xFF383838),
    surfaceDim = Color(0xFF000000),
    surfaceContainerLowest = Color(0xFF000000),
    surfaceContainerLow = Color(0xFF0D0D0D),
    surfaceContainer = Color(0xFF141414),
    surfaceContainerHigh = Color(0xFF1C1C1C),
    surfaceContainerHighest = Color(0xFF262626),
)

// Semantic extensions for state hues that don't fit into MaterialColorScheme.
// Accessed via LocalCashuColors.current.
@Immutable
data class CashuColors(
    val received: Color,
    val pending: Color,
    val receivedContainer: Color,
    val pendingContainer: Color,
    // Content roles for the two containers above. Material pairs every container
    // fill with an `on*Container` colour; these hues live outside
    // MaterialColorScheme, so the pair has to be declared here. Without them
    // callers reach for the full-strength hue as text, which is the fill colour,
    // not the content colour.
    val onPendingContainer: Color,
    val onReceivedContainer: Color,
    val canvasDivider: Color,
)

internal val LightCashuColors = CashuColors(
    received = ReceivedGreen,
    pending = PendingOrange,
    receivedContainer = ReceivedGreen.copy(alpha = 0.12f),
    pendingContainer = PendingOrange.copy(alpha = 0.10f),
    // Light mode can't use systemOrange as text: #FF9500 is 2.2:1 on white, far
    // under AA. Same hue, darkened until it passes (6.1:1 on the canvas, 5.6:1
    // on the container above).
    onPendingContainer = Color(0xFF96500A),
    onReceivedContainer = Color(0xFF0B5227),
    canvasDivider = Color(0xFFEBEBEB),
)

internal val DarkCashuColors = CashuColors(
    received = Color(0xFF30D158),
    pending = Color(0xFFFF9F0A),
    receivedContainer = ReceivedGreen.copy(alpha = 0.20f),
    pendingContainer = PendingOrange.copy(alpha = 0.18f),
    // Dark mode carries systemOrange itself — 10.2:1 on the canvas, 7.1:1 on the
    // container — so caution text reads as orange rather than the pale cream
    // (#FFDCB0) it used to be.
    onPendingContainer = Color(0xFFFF9F0A),
    onReceivedContainer = Color(0xFFB7F0C8),
    canvasDivider = Color(0xFF262626),
)

val LocalCashuColors = compositionLocalOf { LightCashuColors }
