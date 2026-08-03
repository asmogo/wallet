package com.cashu.me.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

object CashuTheme {
    val colors: CashuColors
        @Composable get() = LocalCashuColors.current
    val spacing: CashuSpacing
        @Composable get() = LocalCashuSpacing.current
    val iconSizes: CashuIconSizes
        @Composable get() = LocalCashuIconSizes.current
    val type: CashuTypeRoles
        @Composable get() = LocalCashuTypeRoles.current
    val fonts: CashuFonts
        @Composable get() = LocalCashuFonts.current
}

/**
 * Material 3 Expressive with the brand's monochrome "inverted ink" scheme.
 *
 * - Color: custom zero-chroma [LightInkColorScheme] / [DarkInkColorScheme] —
 *   white canvas + black ink in light mode, black canvas + white ink in dark
 *   mode (shared brand identity with iOS). No Material You dynamic color:
 *   the palette never shifts with the wallpaper. Chromatic color is reserved
 *   for payment state (received green / pending orange / error red).
 * - Motion: [MotionScheme.expressive] — spring physics drive all component
 *   motion (sheets, switches, indicators) instead of hand-tuned tweens.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun CashuTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkInkColorScheme else LightInkColorScheme
    val cashuColors = if (darkTheme) DarkCashuColors else LightCashuColors

    // Status/navigation bar tinting. enableEdgeToEdge() makes the bars transparent;
    // here we only flip the icon-tint (light vs dark) based on background luminance.
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            val controller = WindowCompat.getInsetsController(window, view)
            val lightSurface = colorScheme.background.luminance() > 0.5f
            controller.isAppearanceLightStatusBars = lightSurface
            controller.isAppearanceLightNavigationBars = lightSurface
        }
    }

    val fonts = CashuFonts.Geist

    CompositionLocalProvider(
        LocalCashuColors provides cashuColors,
        LocalCashuSpacing provides CashuSpacing(),
        LocalCashuIconSizes provides CashuIconSizes(),
        LocalCashuFonts provides fonts,
        LocalCashuTypeRoles provides cashuTypeRoles(fonts),
    ) {
        MaterialExpressiveTheme(
            colorScheme = colorScheme,
            motionScheme = MotionScheme.expressive(),
            shapes = CashuShapes,
            typography = cashuTypography(fonts),
            content = content,
        )
    }
}
